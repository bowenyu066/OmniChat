import Foundation

/// Google AI (Gemini) API service implementation
final class GoogleAIService: APIServiceProtocol {
    let provider: AIProvider = .google

    private let keychainService: KeychainService
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    init(keychainService: KeychainService = .shared) {
        self.keychainService = keychainService
    }

    var isConfigured: Bool {
        guard let key = keychainService.getAPIKey(for: .google) else { return false }
        return !key.isEmpty
    }

    func sendMessage(messages: [ChatMessage], model: AIModel) async throws -> String {
        guard let apiKey = keychainService.getAPIKey(for: .google), !apiKey.isEmpty else {
            print("❌ [Gemini] No API key found")
            throw APIServiceError.invalidAPIKey
        }

        let request = try buildRequest(messages: messages, model: model, apiKey: apiKey, stream: false)
        print("🌐 [Gemini] Sending request to: \(request.url?.absoluteString ?? "unknown")")
        print("📝 [Gemini] Request headers: \(request.allHTTPHeaderFields ?? [:])")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [Gemini] Invalid HTTP response")
            throw APIServiceError.invalidResponse
        }

        print("📊 [Gemini] Status code: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            print("❌ [Gemini] Authentication failed")
            throw APIServiceError.invalidAPIKey
        }

        if httpResponse.statusCode == 429 {
            print("❌ [Gemini] Rate limited")
            throw APIServiceError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "unknown"
            print("❌ [Gemini] Error response: \(responseString)")
            if let errorResponse = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data) {
                throw APIServiceError.serverError(statusCode: httpResponse.statusCode, message: errorResponse.error.message)
            }
            throw APIServiceError.serverError(statusCode: httpResponse.statusCode, message: nil)
        }

        let responseString = String(data: data, encoding: .utf8) ?? "unknown"
        print("📥 [Gemini] Response: \(responseString.prefix(500))...")

        do {
            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            print("✅ [Gemini] Decoded response successfully")

            // Extract text from candidates
            guard let candidate = geminiResponse.candidates.first else {
                print("❌ [Gemini] No candidates in response")
                throw APIServiceError.invalidResponse
            }

            guard let content = candidate.content else {
                print("❌ [Gemini] No content in candidate")
                throw APIServiceError.invalidResponse
            }

            guard let part = content.parts.first else {
                print("❌ [Gemini] No parts in content")
                throw APIServiceError.invalidResponse
            }

            print("✅ [Gemini] Extracted text: \(part.text.prefix(100))...")
            return part.text
        } catch {
            print("❌ [Gemini] Decoding error: \(error)")
            throw APIServiceError.decodingError(error)
        }
    }

    func streamMessage(messages: [ChatMessage], model: AIModel) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { [self] in
                do {
                    guard let apiKey = self.keychainService.getAPIKey(for: AIProvider.google), !apiKey.isEmpty else {
                        print("❌ [Gemini Stream] No API key found")
                        continuation.finish(throwing: APIServiceError.invalidAPIKey)
                        return
                    }

                    let request = try self.buildRequest(messages: messages, model: model, apiKey: apiKey, stream: true)
                    print("🌐 [Gemini Stream] Sending request to: \(request.url?.absoluteString ?? "unknown")")

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("❌ [Gemini Stream] Invalid HTTP response")
                        continuation.finish(throwing: APIServiceError.invalidResponse)
                        return
                    }

                    print("📊 [Gemini Stream] Status code: \(httpResponse.statusCode)")

                    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        print("❌ [Gemini Stream] Authentication failed")
                        continuation.finish(throwing: APIServiceError.invalidAPIKey)
                        return
                    }

                    if httpResponse.statusCode == 429 {
                        print("❌ [Gemini Stream] Rate limited")
                        continuation.finish(throwing: APIServiceError.rateLimited)
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        print("❌ [Gemini Stream] Error status: \(httpResponse.statusCode)")
                        continuation.finish(throwing: APIServiceError.serverError(statusCode: httpResponse.statusCode, message: nil))
                        return
                    }

                    print("✅ [Gemini Stream] Connected, reading stream...")

                    // Google's streaming format is newline-delimited JSON
                    var buffer = ""
                    var lineCount = 0

                    for try await line in bytes.lines {
                        lineCount += 1
                        print("📨 [Gemini Stream] Line \(lineCount): \(line.prefix(100))...")

                        // Skip empty lines
                        if line.trimmingCharacters(in: .whitespaces).isEmpty {
                            continue
                        }

                        // Handle SSE format or raw JSON
                        var jsonLine = line
                        if line.hasPrefix("data: ") {
                            jsonLine = String(line.dropFirst(6))
                            print("📝 [Gemini Stream] Extracted data: \(jsonLine.prefix(100))...")
                        }

                        // Skip [DONE] marker
                        if jsonLine == "[DONE]" {
                            print("✅ [Gemini Stream] Received [DONE] marker")
                            break
                        }

                        // Handle chunked JSON (may come in multiple pieces)
                        buffer += jsonLine

                        // Try to parse the buffer
                        if let data = buffer.data(using: .utf8) {
                            do {
                                let streamResponse = try JSONDecoder().decode(GeminiStreamResponse.self, from: data)
                                print("✅ [Gemini Stream] Decoded chunk successfully")

                                // Extract text from the response
                                if let candidate = streamResponse.candidates?.first,
                                   let part = candidate.content?.parts.first {
                                    print("📤 [Gemini Stream] Yielding: \(part.text.prefix(50))...")
                                    continuation.yield(part.text)
                                } else {
                                    print("⚠️ [Gemini Stream] No text in chunk")
                                }

                                // Clear buffer on successful parse
                                buffer = ""
                            } catch {
                                // JSON might be incomplete, continue buffering
                                print("⚠️ [Gemini Stream] Parse error (buffering): \(error)")
                                // But if buffer is getting too large, try alternative parsing
                                if buffer.count > 10000 {
                                    print("❌ [Gemini Stream] Buffer too large, clearing")
                                    buffer = ""
                                }
                            }
                        }
                    }

                    print("✅ [Gemini Stream] Stream finished, total lines: \(lineCount)")
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
        var generationConfig: [String: Any] = [
            "maxOutputTokens": 4096
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

            contents.append([
                "role": role,
                "parts": [
                    ["text": message.content]
                ]
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
    let text: String
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
