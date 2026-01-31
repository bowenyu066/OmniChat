import Foundation
import os.log

private let logger = Logger(subsystem: "com.omnichat.app", category: "EmbeddingService")

/// Service for generating text embeddings using OpenAI's text-embedding-3-small model
final class EmbeddingService {
    static let shared = EmbeddingService()

    private let keychainService: KeychainService
    private let baseURL = "https://api.openai.com/v1/embeddings"
    private let model = "text-embedding-3-small"
    private let maxTokens = 8000 // Truncate long text to avoid API limits

    private init(keychainService: KeychainService = .shared) {
        self.keychainService = keychainService
    }

    /// Check if the embedding service is configured (requires OpenAI API key)
    var isConfigured: Bool {
        guard let key = keychainService.getAPIKey(for: .openAI) else { return false }
        return !key.isEmpty
    }

    private var apiKey: String? {
        keychainService.getAPIKey(for: .openAI)
    }

    /// Generate embedding for a single text
    /// - Parameter text: The text to embed
    /// - Returns: A 1536-dimensional embedding vector
    func generateEmbedding(for text: String) async throws -> [Double] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw EmbeddingError.notConfigured
        }

        let truncatedText = truncateText(text)
        guard !truncatedText.isEmpty else {
            throw EmbeddingError.emptyText
        }

        let request = try createRequest(texts: [truncatedText], apiKey: apiKey)

        let (data, response) = try await URLSession.shared.data(for: request)

        try validateResponse(response, data: data)

        let embeddingResponse = try JSONDecoder().decode(EmbeddingResponse.self, from: data)

        guard let embedding = embeddingResponse.data.first?.embedding else {
            throw EmbeddingError.noEmbeddingReturned
        }

        logger.debug("Generated embedding for text of length \(text.count)")
        return embedding
    }

    /// Generate embeddings for multiple texts in a single API call (more efficient)
    /// - Parameter texts: Array of texts to embed
    /// - Returns: Array of 1536-dimensional embedding vectors
    func generateEmbeddings(for texts: [String]) async throws -> [[Double]] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw EmbeddingError.notConfigured
        }

        let truncatedTexts = texts.map { truncateText($0) }.filter { !$0.isEmpty }
        guard !truncatedTexts.isEmpty else {
            throw EmbeddingError.emptyText
        }

        let request = try createRequest(texts: truncatedTexts, apiKey: apiKey)

        let (data, response) = try await URLSession.shared.data(for: request)

        try validateResponse(response, data: data)

        let embeddingResponse = try JSONDecoder().decode(EmbeddingResponse.self, from: data)

        let embeddings = embeddingResponse.data.sorted(by: { $0.index < $1.index }).map { $0.embedding }

        guard embeddings.count == truncatedTexts.count else {
            throw EmbeddingError.mismatchedCount
        }

        logger.debug("Generated \(embeddings.count) embeddings in batch")
        return embeddings
    }

    /// Truncate text to approximately maxTokens to avoid API limits
    private func truncateText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Rough estimate: 4 characters per token on average
        let maxChars = maxTokens * 4
        if trimmed.count > maxChars {
            return String(trimmed.prefix(maxChars))
        }
        return trimmed
    }

    private func createRequest(texts: [String], apiKey: String) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw EmbeddingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "input": texts
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw EmbeddingError.invalidAPIKey
        case 429:
            throw EmbeddingError.rateLimited
        default:
            let errorMessage = try? JSONDecoder().decode(OpenAIEmbeddingErrorResponse.self, from: data)
            throw EmbeddingError.serverError(
                statusCode: httpResponse.statusCode,
                message: errorMessage?.error.message
            )
        }
    }
}

// MARK: - Response Models

private struct EmbeddingResponse: Decodable {
    let data: [EmbeddingData]

    struct EmbeddingData: Decodable {
        let embedding: [Double]
        let index: Int
    }
}

private struct OpenAIEmbeddingErrorResponse: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String
    }
}

// MARK: - Errors

enum EmbeddingError: LocalizedError {
    case notConfigured
    case emptyText
    case invalidURL
    case invalidResponse
    case invalidAPIKey
    case rateLimited
    case serverError(statusCode: Int, message: String?)
    case noEmbeddingReturned
    case mismatchedCount

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Embedding service not configured. Please add your OpenAI API key."
        case .emptyText:
            return "Cannot generate embedding for empty text."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Invalid response from embedding API."
        case .invalidAPIKey:
            return "Invalid OpenAI API key."
        case .rateLimited:
            return "Rate limited by OpenAI. Please wait and try again."
        case .serverError(let statusCode, let message):
            return "Embedding API error (\(statusCode)): \(message ?? "Unknown error")"
        case .noEmbeddingReturned:
            return "No embedding returned from API."
        case .mismatchedCount:
            return "Mismatch between input texts and returned embeddings."
        }
    }
}
