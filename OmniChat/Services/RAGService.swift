import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.omnichat.app", category: "RAGService")

/// Result from RAG retrieval containing relevant past conversation context
struct RAGResult {
    let summary: String
    let similarity: Double
    let conversationTitle: String
}

/// Service for retrieving relevant past conversation context using semantic search
/// Marked as @MainActor to ensure all ModelContext operations happen on the main thread
@MainActor
final class RAGService {
    static let shared = RAGService()

    private let embeddingService: EmbeddingService
    private let minimumSimilarity: Double = 0.3 // Lower threshold for better recall

    private init(embeddingService: EmbeddingService = .shared) {
        self.embeddingService = embeddingService
    }

    /// Check if RAG is available (requires OpenAI API key for embeddings)
    nonisolated var isConfigured: Bool {
        EmbeddingService.shared.isConfigured
    }

    /// Retrieve relevant past conversation context for a query
    /// - Parameters:
    ///   - query: The user's current query/message
    ///   - excludeConversation: The current conversation to exclude from results
    ///   - modelContext: SwiftData model context for querying messages
    ///   - limit: Maximum number of results to return
    /// - Returns: Array of RAGResult sorted by similarity (highest first)
    func retrieveRelevantContext(
        for query: String,
        excludeConversation: Conversation?,
        modelContext: ModelContext,
        limit: Int = 5
    ) async throws -> [RAGResult] {
        guard isConfigured else {
            logger.warning("RAG not configured - OpenAI API key missing")
            return []
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        // IMPORTANT: Fetch messages BEFORE any await calls to stay on MainActor
        // ModelContext is not thread-safe and must be used on the actor it was created on
        let messagesWithEmbeddings = try fetchMessagesWithEmbeddings(
            excludeConversation: excludeConversation,
            modelContext: modelContext
        )

        if messagesWithEmbeddings.isEmpty {
            logger.debug("No messages with embeddings found for RAG")
            return []
        }

        // Extract the data we need from messages BEFORE going async
        // This ensures we don't access SwiftData objects after suspension points
        struct MessageData {
            let content: String
            let summary: String?
            let embedding: [Double]
            let conversationTitle: String
        }

        let messageDataList: [MessageData] = messagesWithEmbeddings.compactMap { message in
            guard let embedding = message.embeddingVector else { return nil }
            return MessageData(
                content: message.content,
                summary: message.summary,
                embedding: embedding,
                conversationTitle: message.conversation?.title ?? "Unknown Conversation"
            )
        }

        logger.info("RAG: Found \(messageDataList.count) messages with embeddings to search")
        if messageDataList.isEmpty {
            logger.warning("RAG: No embedded messages found - embeddings may not have been generated yet")
        }

        // NOW we can safely do the async embedding call
        let queryEmbedding: [Double]
        do {
            queryEmbedding = try await embeddingService.generateEmbedding(for: trimmedQuery)
        } catch {
            logger.error("Failed to generate query embedding: \(error.localizedDescription)")
            throw error
        }

        // Calculate similarity scores using the extracted data (not SwiftData objects)
        var scoredResults: [(data: MessageData, similarity: Double)] = []
        var maxSimilarity: Double = 0

        for data in messageDataList {
            let similarity = cosineSimilarity(queryEmbedding, data.embedding)
            maxSimilarity = max(maxSimilarity, similarity)

            if similarity >= minimumSimilarity {
                scoredResults.append((data: data, similarity: similarity))
                logger.debug("RAG: Match found (similarity: \(String(format: "%.3f", similarity))): \(data.conversationTitle)")
            }
        }

        logger.info("RAG: Max similarity found: \(String(format: "%.3f", maxSimilarity)), threshold: \(self.minimumSimilarity), matches: \(scoredResults.count)")

        // Sort by similarity (highest first) and take top results
        scoredResults.sort { $0.similarity > $1.similarity }
        let topResults = Array(scoredResults.prefix(limit))

        // Convert to RAGResults (using extracted data, not SwiftData objects)
        let ragResults = topResults.map { result -> RAGResult in
            let summary = result.data.summary ?? truncateForSummary(result.data.content)

            return RAGResult(
                summary: summary,
                similarity: result.similarity,
                conversationTitle: result.data.conversationTitle
            )
        }

        logger.info("RAG retrieved \(ragResults.count) relevant results")
        return ragResults
    }

    /// Fetch all messages that have embeddings, excluding the specified conversation
    private func fetchMessagesWithEmbeddings(
        excludeConversation: Conversation?,
        modelContext: ModelContext
    ) throws -> [Message] {
        // Build predicate to fetch messages with embeddings
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.embeddingData != nil
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        var messages = try modelContext.fetch(descriptor)

        // Filter out messages from the excluded conversation
        if let excludeConversation = excludeConversation {
            messages = messages.filter { $0.conversation?.id != excludeConversation.id }
        }

        return messages
    }

    /// Calculate cosine similarity between two vectors
    /// - Returns: Similarity score between -1 and 1 (1 = identical, 0 = orthogonal)
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Double = 0
        var magnitudeA: Double = 0
        var magnitudeB: Double = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }

        magnitudeA = sqrt(magnitudeA)
        magnitudeB = sqrt(magnitudeB)

        guard magnitudeA > 0, magnitudeB > 0 else { return 0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    /// Create a brief summary from content when no summary is available
    private func truncateForSummary(_ content: String, maxLength: Int = 100) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > maxLength {
            return String(trimmed.prefix(maxLength)) + "..."
        }
        return trimmed
    }
}

// MARK: - RAGResult Formatting

extension RAGService {
    /// Format RAG results as a string for inclusion in system prompt
    static func formatResultsForPrompt(_ results: [RAGResult]) -> String {
        guard !results.isEmpty else { return "" }

        var formatted = "## Relevant Past Conversations\n"
        formatted += "The user has discussed similar topics before:\n"

        for result in results {
            formatted += "\n### From \"\(result.conversationTitle)\"\n"
            formatted += "Summary: \(result.summary)\n"
        }

        return formatted
    }
}
