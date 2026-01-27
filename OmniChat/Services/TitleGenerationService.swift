import Foundation
import os.log

private let logger = Logger(subsystem: "com.omnichat.app", category: "TitleGeneration")

/// Service for generating conversation titles using GPT-4o
final class TitleGenerationService {
    static let shared = TitleGenerationService()

    private let keychainService: KeychainService
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    private init(keychainService: KeychainService = .shared) {
        self.keychainService = keychainService
    }

    /// Generate a short title for a conversation based on the first user message
    func generateTitle(for userMessage: String) async -> String? {
        guard let apiKey = keychainService.getAPIKey(for: .openAI), !apiKey.isEmpty else {
            logger.warning("No OpenAI API key found")
            return nil
        }

        logger.info("Generating title for message...")

        // System prompt
        let systemPrompt = """
        Generate a very short title (3-6 words max) that summarizes the user's message.
        The title should be concise and descriptive.
        Do NOT use quotes around the title.
        Do NOT include any explanation or extra text.
        Just output the title directly.
        """

        // Build messages payload: system + user message
        let messagesPayload: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userMessage]
        ]

        do {
            let title = try await callChatCompletionsWithMessages(
                model: "gpt-4o",
                paramKey: "max_tokens",
                maxTokens: 16,
                messages: messagesPayload,
                apiKey: apiKey
            )
            logger.info("Generated title: \(title)")
            return title
        } catch {
            logger.error("Failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Generate a short title using conversation context (user + assistant texts)
    func generateTitle(for chatMessages: [ChatMessage]) async -> String? {
        guard let apiKey = keychainService.getAPIKey(for: .openAI), !apiKey.isEmpty else {
            logger.warning("No OpenAI API key found")
            return nil
        }

        // System prompt for context-based title
        let systemPrompt = """
        Generate a very short title (3-6 words max) that summarizes the conversation.
        The title should be concise and descriptive.
        Do NOT use quotes around the title.
        Do NOT include any explanation or extra text.
        Just output the title directly.
        """

        // Build messages payload: system + provided chat messages (text-only)
        var messagesPayload: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for msg in chatMessages {
            if let text = msg.textContent?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                messagesPayload.append([
                    "role": msg.role,
                    "content": text
                ])
            }
        }

        // If no usable text, return nil early
        if messagesPayload.count <= 1 {
            return nil
        }

        do {
            let title = try await callChatCompletionsWithMessages(
                model: "gpt-4o",
                paramKey: "max_tokens",
                maxTokens: 16,
                messages: messagesPayload,
                apiKey: apiKey
            )
            logger.info("Generated title: \(title)")
            return title
        } catch {
            logger.error("Failed: \(error.localizedDescription)")
            return nil
        }
    }

    // Generic chat/completions caller that accepts a prepared messages payload
    private func callChatCompletionsWithMessages(
        model: String,
        paramKey: String,
        maxTokens: Int,
        messages: [[String: Any]],
        apiKey: String
    ) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw TitleGenerationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "messages": messages
        ]
        body[paramKey] = maxTokens

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TitleGenerationError.apiError
        }

        if httpResponse.statusCode != 200 {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("API error (\(httpResponse.statusCode)): \(errorString)")
            throw TitleGenerationError.apiError
        }

        let result = try JSONDecoder().decode(TitleResponse.self, from: data)

        guard let rawTitle = result.choices.first.flatMap({ $0.message?.content ?? $0.text }),
              !rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let raw = String(data: data, encoding: .utf8) {
                logger.error("No content in title response: \(raw)")
            }
            throw TitleGenerationError.noContent
        }

        let cleanedTitle = rawTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        if cleanedTitle.isEmpty {
            throw TitleGenerationError.noContent
        }

        return cleanedTitle
    }
}

// MARK: - Response Models

private struct TitleResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message?
        let text: String?
    }

    struct Message: Decodable {
        let content: String?
    }
}

// MARK: - Errors

enum TitleGenerationError: Error {
    case invalidURL
    case apiError
    case noContent
}
