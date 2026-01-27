import Foundation

/// Anthropic (Claude) API service implementation
final class AnthropicService: APIServiceProtocol {
    let provider: AIProvider = .anthropic

    private let keychainService: KeychainService
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2024-10-22"  // Updated for vision support

    init(keychainService: KeychainService = .shared) {
        self.keychainService = keychainService
    }

    var isConfigured: Bool {
        guard let key = keychainService.getAPIKey(for: .anthropic) else { return false }
        return !key.isEmpty
    }

    func sendMessage(messages: [ChatMessage], model: AIModel) async throws -> String {
        guard let apiKey = keychainService.getAPIKey(for: .anthropic), !apiKey.isEmpty else {
            throw APIServiceError.invalidAPIKey
        }

        let request = try buildRequest(messages: messages, model: model, apiKey: apiKey, stream: false)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIServiceError.invalidAPIKey
        }

        if httpResponse.statusCode == 429 {
            throw APIServiceError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data) {
                throw APIServiceError.serverError(statusCode: httpResponse.statusCode, message: errorResponse.error.message)
            }
            throw APIServiceError.serverError(statusCode: httpResponse.statusCode, message: nil)
        }

        let messageResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)

        // Extract text from content blocks
        let text = messageResponse.content
            .compactMap { block -> String? in
                if case .text(let text) = block {
                    return text
                }
                return nil
            }
            .joined()

        return text
    }

    func streamMessage(messages: [ChatMessage], model: AIModel) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { [self] in
                do {
                    guard let apiKey = self.keychainService.getAPIKey(for: AIProvider.anthropic), !apiKey.isEmpty else {
                        continuation.finish(throwing: APIServiceError.invalidAPIKey)
                        return
                    }

                    let request = try self.buildRequest(messages: messages, model: model, apiKey: apiKey, stream: true)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: APIServiceError.invalidResponse)
                        return
                    }

                    if httpResponse.statusCode == 401 {
                        continuation.finish(throwing: APIServiceError.invalidAPIKey)
                        return
                    }

                    if httpResponse.statusCode == 429 {
                        continuation.finish(throwing: APIServiceError.rateLimited)
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: APIServiceError.serverError(statusCode: httpResponse.statusCode, message: nil))
                        return
                    }

                    for try await line in bytes.lines {
                        // Anthropic SSE format: "event: <event_type>\ndata: <json>"
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))

                            // Skip empty data
                            if jsonString.isEmpty { continue }

                            // Parse the streaming event
                            if let data = jsonString.data(using: .utf8),
                               let event = try? JSONDecoder().decode(AnthropicStreamEvent.self, from: data) {

                                switch event.type {
                                case "content_block_delta":
                                    if let delta = event.delta,
                                       case .textDelta(let text) = delta {
                                        continuation.yield(text)
                                    }
                                case "message_stop":
                                    break
                                case "error":
                                    if let error = event.error {
                                        continuation.finish(throwing: APIServiceError.streamingError(error.message))
                                        return
                                    }
                                default:
                                    break
                                }
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

    private func buildRequest(messages: [ChatMessage], model: AIModel, apiKey: String, stream: Bool) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw APIServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        // Separate system message from user/assistant messages
        var systemPrompt: String?
        var anthropicMessages: [[String: Any]] = []

        for message in messages {
            if message.role == "system" {
                systemPrompt = message.textContent
            } else {
                anthropicMessages.append(convertToAnthropicFormat(message))
            }
        }

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 4096,
            "messages": anthropicMessages,
            "stream": stream
        ]

        if let system = systemPrompt {
            body["system"] = system
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return request
    }

    private func convertToAnthropicFormat(_ message: ChatMessage) -> [String: Any] {
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
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": mimeType,
                            "data": base64
                        ]
                    ])
                case .pdf(let data):
                    // Claude supports native PDF via document type
                    let base64 = data.base64EncodedString()
                    content.append([
                        "type": "document",
                        "source": [
                            "type": "base64",
                            "media_type": "application/pdf",
                            "data": base64
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
}

// MARK: - Response Models

private struct AnthropicResponse: Codable {
    let id: String
    let type: String
    let role: String
    let content: [ContentBlock]
    let model: String
    let stopReason: String?
    let stopSequence: String?

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
    }
}

private enum ContentBlock: Codable {
    case text(String)
    case other

    enum CodingKeys: String, CodingKey {
        case type, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        if type == "text" {
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        } else {
            self = .other
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .other:
            try container.encode("other", forKey: .type)
        }
    }
}

private struct AnthropicErrorResponse: Codable {
    let type: String
    let error: AnthropicError
}

private struct AnthropicError: Codable {
    let type: String
    let message: String
}

// MARK: - Streaming Models

private struct AnthropicStreamEvent: Codable {
    let type: String
    let index: Int?
    let delta: StreamDelta?
    let error: AnthropicError?
    let message: AnthropicStreamMessage?

    enum CodingKeys: String, CodingKey {
        case type, index, delta, error, message
    }
}

private enum StreamDelta: Codable {
    case textDelta(String)
    case other

    enum CodingKeys: String, CodingKey {
        case type, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        if type == "text_delta" {
            let text = try container.decode(String.self, forKey: .text)
            self = .textDelta(text)
        } else {
            self = .other
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .textDelta(let text):
            try container.encode("text_delta", forKey: .type)
            try container.encode(text, forKey: .text)
        case .other:
            try container.encode("other", forKey: .type)
        }
    }
}

private struct AnthropicStreamMessage: Codable {
    let id: String
    let type: String
    let role: String
    let model: String
}
