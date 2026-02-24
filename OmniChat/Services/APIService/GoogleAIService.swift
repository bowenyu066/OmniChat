import Foundation

/// Google AI (Gemini) API service implementation
final class GoogleAIService: APIServiceProtocol {
    let provider: AIProvider = .google

    private let keychainService: KeychainService
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
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
        guard let key = keychainService.getAPIKey(for: .google) else { return false }
        return !key.isEmpty
    }

    func sendMessage(messages: [ChatMessage], model: AIModel) async throws -> String {
        guard let apiKey = keychainService.getAPIKey(for: .google), !apiKey.isEmpty else {
            throw APIServiceError.invalidAPIKey
        }

        let request = try buildRequest(messages: messages, model: model, apiKey: apiKey, stream: false)

        let (data, response) = try await Self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw APIServiceError.invalidAPIKey
        }

        if httpResponse.statusCode == 429 {
            throw APIServiceError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data) {
                throw APIServiceError.serverError(statusCode: httpResponse.statusCode, message: errorResponse.error.message)
            }
            throw APIServiceError.serverError(statusCode: httpResponse.statusCode, message: nil)
        }

        do {
            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

            guard let candidate = geminiResponse.candidates.first else {
                throw APIServiceError.invalidResponse
            }

            guard let content = candidate.content else {
                throw APIServiceError.invalidResponse
            }

            let text = content.parts
                .compactMap(\.text)
                .joined()

            guard !text.isEmpty else {
                throw APIServiceError.invalidResponse
            }

            return text
        } catch {
            throw APIServiceError.decodingError(error)
        }
    }

    func streamMessage(messages: [ChatMessage], model: AIModel) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { [self] in
                do {
                    guard let apiKey = self.keychainService.getAPIKey(for: AIProvider.google), !apiKey.isEmpty else {
                        continuation.finish(throwing: APIServiceError.invalidAPIKey)
                        return
                    }

                    let request = try self.buildRequest(messages: messages, model: model, apiKey: apiKey, stream: true)

                    let (bytes, response) = try await Self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: APIServiceError.invalidResponse)
                        return
                    }

                    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
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
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty || trimmed.hasPrefix("event:") {
                            continue
                        }

                        var payload = trimmed
                        if payload.hasPrefix("data:") {
                            payload = payload.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        }

                        if payload.isEmpty {
                            continue
                        }

                        if payload == "[DONE]" {
                            break
                        }

                        guard let data = payload.data(using: .utf8) else { continue }

                        let streamResponse: GeminiStreamResponse
                        do {
                            streamResponse = try JSONDecoder().decode(GeminiStreamResponse.self, from: data)
                        } catch {
                            continue
                        }

                        for candidate in streamResponse.candidates ?? [] {
                            let text = candidate.content?.parts
                                .compactMap(\.text)
                                .joined() ?? ""
                            if !text.isEmpty {
                                continuation.yield(text)
                            }

                            if candidate.finishReason == "MAX_TOKENS" {
                                continuation.yield("\n\n[Response truncated at Gemini output token limit]")
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
        let endpoint = stream ? "streamGenerateContent" : "generateContent"
        // For streaming, add ?alt=sse parameter
        let streamParam = stream ? "?alt=sse" : ""
        let urlString = "\(baseURL)/\(model.rawValue):\(endpoint)\(streamParam)"

        guard let url = URL(string: urlString) else {
            throw APIServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // API key goes in header, not URL
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        // Convert messages to Gemini format
        let geminiContents = convertToGeminiFormat(messages: messages)

        // Configure thinking level for Gemini 3 models
        let maxOutputTokens = model == .gemini3ProPreview ? 16384 : 8192
        var generationConfig: [String: Any] = [
            "maxOutputTokens": maxOutputTokens
        ]

        // Add thinking config for Gemini 3 models
        if model.rawValue.hasPrefix("gemini-3") {
            // Use "high" for Pro (default), "medium" for Flash for balanced performance
            let thinkingLevel = model.rawValue.contains("pro") ? "high" : "medium"
            generationConfig["thinkingConfig"] = [
                "thinkingLevel": thinkingLevel
            ]
        }

        let body: [String: Any] = [
            "contents": geminiContents,
            "generationConfig": generationConfig
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return request
    }

    private func convertToGeminiFormat(messages: [ChatMessage]) -> [[String: Any]] {
        var contents: [[String: Any]] = []

        for message in messages {
            // Gemini uses "user" and "model" roles
            let role: String
            switch message.role {
            case "user":
                role = "user"
            case "assistant":
                role = "model"
            case "system":
                // Gemini handles system prompts differently - prepend to first user message
                // For simplicity, treat as user message with context
                role = "user"
            default:
                role = "user"
            }

            // Build parts array
            var parts: [[String: Any]] = []

            for content in message.contents {
                switch content {
                case .text(let text):
                    parts.append(["text": text])
                case .image(let data, let mimeType):
                    let base64 = data.base64EncodedString()
                    parts.append([
                        "inlineData": [
                            "mimeType": mimeType,
                            "data": base64
                        ]
                    ])
                case .pdf(let data):
                    // Gemini supports PDF via inlineData
                    let base64 = data.base64EncodedString()
                    parts.append([
                        "inlineData": [
                            "mimeType": "application/pdf",
                            "data": base64
                        ]
                    ])
                }
            }

            contents.append([
                "role": role,
                "parts": parts
            ])
        }

        return contents
    }
}

// MARK: - Response Models

private struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]
}

private struct GeminiStreamResponse: Codable {
    let candidates: [GeminiCandidate]?
    let promptFeedback: GeminiPromptFeedback?
}

private struct GeminiCandidate: Codable {
    let content: GeminiContent?
    let finishReason: String?
    let safetyRatings: [GeminiSafetyRating]?

    // For non-optional content in non-streaming
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent(GeminiContent.self, forKey: .content)
        finishReason = try container.decodeIfPresent(String.self, forKey: .finishReason)
        safetyRatings = try container.decodeIfPresent([GeminiSafetyRating].self, forKey: .safetyRatings)
    }

    enum CodingKeys: String, CodingKey {
        case content, finishReason, safetyRatings
    }
}

private struct GeminiContent: Codable {
    let role: String
    let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    let text: String?
    let thoughtSignature: String?  // Gemini 3 includes this for thinking mode

    enum CodingKeys: String, CodingKey {
        case text
        case thoughtSignature
    }
}

private struct GeminiSafetyRating: Codable {
    let category: String
    let probability: String
}

private struct GeminiPromptFeedback: Codable {
    let safetyRatings: [GeminiSafetyRating]?
}

private struct GeminiErrorResponse: Codable {
    let error: GeminiError
}

private struct GeminiError: Codable {
    let code: Int
    let message: String
    let status: String
}
