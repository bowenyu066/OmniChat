import Foundation

/// OpenAI API service implementation
final class OpenAIService: APIServiceProtocol {
    let provider: AIProvider = .openAI

    private let keychainService: KeychainService
    private let chatCompletionsURL = "https://api.openai.com/v1/chat/completions"
    private let responsesURL = "https://api.openai.com/v1/responses"
    private let reasoningEffortKey = "openai_reasoning_effort"
    private static let requestTimeout: TimeInterval = 600
    private static let resourceTimeout: TimeInterval = 1800
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

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

        if usesResponsesAPI(for: model) {
            let request = try createResponsesRequest(messages: messages, model: model, stream: false, apiKey: apiKey)
            let (data, response) = try await Self.session.data(for: request)
            try validateResponse(response, data: data)
            return try extractTextFromResponsesPayload(data)
        }

        let request = try createChatCompletionsRequest(messages: messages, model: model, stream: false, apiKey: apiKey)

        let (data, response) = try await Self.session.data(for: request)

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

                    if usesResponsesAPI(for: model) {
                        let request = try createResponsesRequest(messages: messages, model: model, stream: true, apiKey: apiKey)
                        try await streamResponses(request: request, continuation: continuation)
                    } else {
                        let request = try createChatCompletionsRequest(messages: messages, model: model, stream: true, apiKey: apiKey)
                        try await streamChatCompletions(request: request, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func streamChatCompletions(
        request: URLRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let (bytes, response) = try await Self.session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            throw try await streamingHTTPError(statusCode: httpResponse.statusCode, bytes: bytes)
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
    }

    private func streamResponses(
        request: URLRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let (bytes, response) = try await Self.session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            throw try await streamingHTTPError(statusCode: httpResponse.statusCode, bytes: bytes)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))

            if jsonString == "[DONE]" {
                break
            }

            guard let data = jsonString.data(using: .utf8),
                  let event = try? JSONDecoder().decode(OpenAIResponsesStreamEvent.self, from: data) else {
                continue
            }

            if event.type == "response.output_text.delta", let delta = event.delta {
                continuation.yield(delta)
            } else if event.type == "error", let message = event.error?.message {
                throw APIServiceError.streamingError(message)
            }
        }
    }

    private func streamingHTTPError(
        statusCode: Int,
        bytes: URLSession.AsyncBytes
    ) async throws -> APIServiceError {
        var payload = ""
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("data: ") {
                payload += String(trimmed.dropFirst(6))
            } else {
                payload += trimmed
            }
            if payload.count > 16_000 {
                break
            }
        }

        let message = extractOpenAIErrorMessage(from: Data(payload.utf8))
        return .serverError(statusCode: statusCode, message: message)
    }

    private func usesResponsesAPI(for model: AIModel) -> Bool {
        // GPT-5.2 Pro is Responses-only.
        model == .gpt5_2Pro
    }

    private func createChatCompletionsRequest(messages: [ChatMessage], model: AIModel, stream: Bool, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: chatCompletionsURL) else {
            throw APIServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout
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

    private func createResponsesRequest(messages: [ChatMessage], model: AIModel, stream: Bool, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: responsesURL) else {
            throw APIServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let inputMessages = messages.map { convertToResponsesFormat($0) }
        var body: [String: Any] = [
            "model": model.rawValue,
            "input": inputMessages,
            "stream": stream
        ]

        if let effort = effectiveReasoningEffort(for: model) {
            body["reasoning"] = ["effort": effort]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return request
    }

    private func extractTextFromResponsesPayload(_ data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIServiceError.invalidResponse
        }

        if let outputText = object["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }

        if let outputTextArray = object["output_text"] as? [String] {
            let joined = outputTextArray.joined()
            if !joined.isEmpty {
                return joined
            }
        }

        var combined = ""
        if let output = object["output"] as? [[String: Any]] {
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else { continue }
                for part in content where (part["type"] as? String) == "output_text" {
                    if let text = part["text"] as? String {
                        combined += text
                    }
                }
            }
        }

        guard !combined.isEmpty else {
            throw APIServiceError.invalidResponse
        }
        return combined
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
                return "medium" // Pro only supports medium/high/xhigh
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

    private func convertToResponsesFormat(_ message: ChatMessage) -> [String: Any] {
        var content: [[String: Any]] = []

        for part in message.contents {
            switch part {
            case .text(let text):
                content.append([
                    "type": "input_text",
                    "text": text
                ])
            case .image(let data, let mimeType):
                let base64 = data.base64EncodedString()
                content.append([
                    "type": "input_image",
                    "image_url": "data:\(mimeType);base64,\(base64)"
                ])
            case .pdf(let data):
                let base64 = data.base64EncodedString()
                content.append([
                    "type": "input_file",
                    "filename": "document.pdf",
                    "file_data": "data:application/pdf;base64,\(base64)"
                ])
            }
        }

        if content.isEmpty {
            content = [[
                "type": "input_text",
                "text": message.textContent ?? ""
            ]]
        }

        return [
            "role": message.role,
            "content": content
        ]
    }

    private func extractOpenAIErrorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data))?.error.message
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
            let errorMessage = extractOpenAIErrorMessage(from: data)
            throw APIServiceError.serverError(
                statusCode: httpResponse.statusCode,
                message: errorMessage
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

private struct OpenAIResponsesStreamEvent: Decodable {
    let type: String?
    let delta: String?
    let error: OpenAIResponsesStreamError?
}

private struct OpenAIResponsesStreamError: Decodable {
    let message: String
}
