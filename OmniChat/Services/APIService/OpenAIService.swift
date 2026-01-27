import Foundation

/// OpenAI API service implementation
final class OpenAIService: APIServiceProtocol {
    let provider: AIProvider = .openAI

    private let keychainService: KeychainService
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    init(keychainService: KeychainService = .shared) {
        self.keychainService = keychainService
    }

    var isConfigured: Bool {
        guard let key = keychainService.getAPIKey(for: .openAI) else { return false }
        return !key.isEmpty
    }

    private var apiKey: String? {
        keychainService.getAPIKey(for: .openAI)
    }

    func sendMessage(messages: [ChatMessage], model: AIModel) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw APIServiceError.invalidAPIKey
        }

        let request = try createRequest(messages: messages, model: model, stream: false, apiKey: apiKey)

        let (data, response) = try await URLSession.shared.data(for: request)

        try validateResponse(response, data: data)

        let completionResponse = try JSONDecoder().decode(OpenAICompletionResponse.self, from: data)

        guard let content = completionResponse.choices.first?.message.content else {
            throw APIServiceError.invalidResponse
        }

        return content
    }

    func streamMessage(messages: [ChatMessage], model: AIModel) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = apiKey, !apiKey.isEmpty else {
                        throw APIServiceError.invalidAPIKey
                    }

                    let request = try createRequest(messages: messages, model: model, stream: true, apiKey: apiKey)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIServiceError.invalidResponse
                    }

                    if httpResponse.statusCode != 200 {
                        throw APIServiceError.serverError(statusCode: httpResponse.statusCode, message: nil)
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))

                            if jsonString == "[DONE]" {
                                break
                            }

                            if let data = jsonString.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
                               let content = chunk.choices.first?.delta.content {
                                continuation.yield(content)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func createRequest(messages: [ChatMessage], model: AIModel, stream: Bool, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw APIServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add reasoning_effort for GPT-5.2 (default to "medium" for balanced performance)
        let reasoningEffort: String? = (model.rawValue == "gpt-5.2") ? "medium" : nil

        let body = OpenAIRequest(
            model: model.rawValue,
            messages: messages,
            stream: stream,
            reasoning_effort: reasoningEffort
        )

        request.httpBody = try JSONEncoder().encode(body)

        return request
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw APIServiceError.invalidAPIKey
        case 429:
            throw APIServiceError.rateLimited
        default:
            let errorMessage = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            throw APIServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: errorMessage?.error.message
            )
        }
    }
}

// MARK: - Request/Response Models

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let reasoning_effort: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, reasoning_effort
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        if let reasoning_effort = reasoning_effort {
            try container.encode(reasoning_effort, forKey: .reasoning_effort)
        }
    }
}

private struct OpenAICompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

private struct OpenAIStreamChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}

private struct OpenAIErrorResponse: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String
    }
}
