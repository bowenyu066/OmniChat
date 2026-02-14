import Foundation

/// OpenAI API service implementation
final class OpenAIService: APIServiceProtocol {
    let provider: AIProvider = .openAI

    private let keychainService: KeychainService
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let reasoningEffortKey = "openai_reasoning_effort"

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

        let reasoningEffort = effectiveReasoningEffort(for: model)

        // Convert messages to OpenAI format
        let openAIMessages = messages.map { convertToOpenAIFormat($0) }

        var body: [String: Any] = [
            "model": model.rawValue,
            "messages": openAIMessages,
            "stream": stream
        ]

        if let effort = reasoningEffort {
            body["reasoning_effort"] = effort
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return request
    }

    private func effectiveReasoningEffort(for model: AIModel) -> String? {
        guard model.supportsReasoningEffort else { return nil }

        let selected = OpenAIReasoningEffort(
            rawValue: UserDefaults.standard.string(forKey: reasoningEffortKey) ?? ""
        ) ?? .auto

        guard selected != .auto else { return nil } // Let API choose defaults

        if model.supportsXHighReasoningEffort {
            switch selected {
            case .none:
                return "none"
            case .low:
                return "medium" // GPT-5.2-pro does not expose "low"; map to nearest valid tier
            case .medium:
                return "medium"
            case .high:
                return "high"
            case .xhigh:
                return "xhigh"
            case .auto:
                return nil
            }
        } else {
            switch selected {
            case .none:
                return "none"
            case .low:
                return "low"
            case .medium:
                return "medium"
            case .high:
                return "high"
            case .xhigh:
                return "high" // xhigh is not available for non-pro GPT-5 models
            case .auto:
                return nil
            }
        }
    }

    private func convertToOpenAIFormat(_ message: ChatMessage) -> [String: Any] {
        // Check if message has attachments
        if message.hasAttachments {
            var content: [[String: Any]] = []

            for part in message.contents {
                switch part {
                case .text(let text):
                    content.append([
                        "type": "text",
                        "text": text
                    ])
                case .image(let data, let mimeType):
                    let base64 = data.base64EncodedString()
                    content.append([
                        "type": "image_url",
                        "image_url": [
                            "url": "data:\(mimeType);base64,\(base64)"
                        ]
                    ])
                case .pdf(let data):
                    // OpenAI supports native PDF via file type (added March 2025)
                    let base64 = data.base64EncodedString()
                    content.append([
                        "type": "file",
                        "file": [
                            "filename": "document.pdf",
                            "file_data": "data:application/pdf;base64,\(base64)"
                        ]
                    ])
                }
            }

            return [
                "role": message.role,
                "content": content
            ]
        } else {
            // Text-only message
            return [
                "role": message.role,
                "content": message.textContent ?? ""
            ]
        }
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

// MARK: - Response Models

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
