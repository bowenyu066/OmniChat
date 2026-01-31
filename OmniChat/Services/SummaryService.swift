import Foundation
import os.log

private let logger = Logger(subsystem: "com.omnichat.app", category: "SummaryService")

/// Service for generating concise summaries of conversation exchanges using OpenAI
final class SummaryService {
    static let shared = SummaryService()

    private let keychainService: KeychainService
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4o-mini" // Fast and cheap for summarization

    private init(keychainService: KeychainService = .shared) {
        self.keychainService = keychainService
    }

    /// Check if the summary service is configured (requires OpenAI API key)
    var isConfigured: Bool {
        guard let key = keychainService.getAPIKey(for: .openAI) else { return false }
        return !key.isEmpty
    }

    private var apiKey: String? {
        keychainService.getAPIKey(for: .openAI)
    }

    /// Generate a one-sentence summary of a user+assistant message exchange
    /// - Parameters:
    ///   - userMessage: The user's message content
    ///   - assistantMessage: The assistant's response content
    /// - Returns: A concise one-sentence summary of the exchange
    func generateSummary(userMessage: String, assistantMessage: String) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw SummaryError.notConfigured
        }

        // Truncate messages if too long (keep first ~2000 chars of each)
        let truncatedUser = truncateText(userMessage, maxLength: 2000)
        let truncatedAssistant = truncateText(assistantMessage, maxLength: 2000)

        guard !truncatedUser.isEmpty || !truncatedAssistant.isEmpty else {
            throw SummaryError.emptyContent
        }

        let systemPrompt = """
        You are a concise summarizer. Given a conversation exchange between a user and an assistant, \
        generate a single sentence (max 100 characters) that captures the key topic or question discussed. \
        Focus on WHAT was discussed, not HOW. Be specific and informative. \
        Do not use quotes or say "The user asked..." - just state the topic directly.
        """

        let userContent = """
        User: \(truncatedUser)

        Assistant: \(truncatedAssistant)
        """

        let request = try createRequest(
            systemPrompt: systemPrompt,
            userContent: userContent,
            apiKey: apiKey
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        try validateResponse(response, data: data)

        let completionResponse = try JSONDecoder().decode(SummaryCompletionResponse.self, from: data)

        guard let summary = completionResponse.choices.first?.message.content else {
            throw SummaryError.noSummaryReturned
        }

        let cleanedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.debug("Generated summary: \(cleanedSummary)")
        return cleanedSummary
    }

    /// Truncate text to a maximum length
    private func truncateText(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > maxLength {
            return String(trimmed.prefix(maxLength)) + "..."
        }
        return trimmed
    }

    private func createRequest(systemPrompt: String, userContent: String, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw SummaryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "max_tokens": 50,
            "temperature": 0.3
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummaryError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw SummaryError.invalidAPIKey
        case 429:
            throw SummaryError.rateLimited
        default:
            let errorMessage = try? JSONDecoder().decode(SummaryErrorResponse.self, from: data)
            throw SummaryError.serverError(
                statusCode: httpResponse.statusCode,
                message: errorMessage?.error.message
            )
        }
    }
}

// MARK: - Response Models

private struct SummaryCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

private struct SummaryErrorResponse: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String
    }
}

// MARK: - Errors

enum SummaryError: LocalizedError {
    case notConfigured
    case emptyContent
    case invalidURL
    case invalidResponse
    case invalidAPIKey
    case rateLimited
    case serverError(statusCode: Int, message: String?)
    case noSummaryReturned

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Summary service not configured. Please add your OpenAI API key."
        case .emptyContent:
            return "Cannot generate summary for empty content."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Invalid response from summary API."
        case .invalidAPIKey:
            return "Invalid OpenAI API key."
        case .rateLimited:
            return "Rate limited by OpenAI. Please wait and try again."
        case .serverError(let statusCode, let message):
            return "Summary API error (\(statusCode)): \(message ?? "Unknown error")"
        case .noSummaryReturned:
            return "No summary returned from API."
        }
    }
}
