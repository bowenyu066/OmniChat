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
/// SwiftData operations are marked @MainActor, but similarity calculations run on background threads
final class RAGService {
    static let shared = RAGService()

    private let embeddingService: EmbeddingService
    private let minimumSimilarity: Double = 0.3 // Lower threshold for better recall

    /// Message data extracted from SwiftData for thread-safe processing
    private struct MessageData {
        let content: String
        let summary: String?
        let embedding: [Double]
        let conversationTitle: String
    }

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
    @MainActor
    func retrieveRelevantContext(
        for query: String,
        excludeConversation: Conversation?,
        modelContext: ModelContext,
        limit: Int = 5
    ) async throws -> [RAGResult] {
        let startTime = Date()

        guard isConfigured else {
            logger.warning("RAG not configured - OpenAI API key missing")
            return []
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        // 1. Extract message data on MainActor (safe SwiftData access)
        let extractStartTime = Date()
        let messageDataList = try extractMessageData(
            excludeConversation: excludeConversation,
            modelContext: modelContext
        )
        let extractMs = Int(Date().timeIntervalSince(extractStartTime) * 1000)

        if messageDataList.isEmpty {
            logger.debug("No messages with embeddings found for RAG")
            return []
        }

        logger.info("RAG: Found \(messageDataList.count) messages with embeddings to search")

        // 2. Generate query embedding (network call, can be off main thread)
        let embeddingStartTime = Date()
        let queryEmbedding: [Double]
        do {
            queryEmbedding = try await embeddingService.generateEmbedding(for: trimmedQuery)
        } catch {
            logger.error("Failed to generate query embedding: \(error.localizedDescription)")
            throw error
        }
        let embeddingMs = Int(Date().timeIntervalSince(embeddingStartTime) * 1000)

        // 3. Calculate similarities on background thread to avoid blocking UI
        let similarityStartTime = Date()
        let results = await calculateSimilaritiesAsync(
            messageData: messageDataList,
            queryEmbedding: queryEmbedding,
            limit: limit
        )
        let similarityMs = Int(Date().timeIntervalSince(similarityStartTime) * 1000)

        let totalMs = Int(Date().timeIntervalSince(startTime) * 1000)
        print("PERF_RAG total_ms=\(totalMs) extract_ms=\(extractMs) embedding_ms=\(embeddingMs) similarity_ms=\(similarityMs) messages_searched=\(messageDataList.count) results=\(results.count)")

        return results
    }

    /// Extract message data from SwiftData on MainActor
    /// This ensures all SwiftData access happens on the correct thread before going async
    @MainActor
    private func extractMessageData(
        excludeConversation: Conversation?,
        modelContext: ModelContext
    ) throws -> [MessageData] {
        let messagesWithEmbeddings = try fetchMessagesWithEmbeddings(
            excludeConversation: excludeConversation,
            modelContext: modelContext
        )

        return messagesWithEmbeddings.compactMap { message in
            guard let embedding = message.embeddingVector else { return nil }
            return MessageData(
                content: message.content,
                summary: message.summary,
                embedding: embedding,
                conversationTitle: message.conversation?.title ?? "Unknown Conversation"
            )
        }
    }

    /// Calculate similarities on a background thread to avoid blocking the UI
    /// This is the performance-critical section that processes 500 messages × 1536 dimensions
    private func calculateSimilaritiesAsync(
        messageData: [MessageData],
        queryEmbedding: [Double],
        limit: Int
    ) async -> [RAGResult] {
        // Run on background thread with user-initiated priority for responsiveness
        await Task.detached(priority: .userInitiated) {
            var scoredResults: [(data: MessageData, similarity: Double)] = []
            var maxSimilarity: Double = 0

            // This loop processes 768,000 floating-point operations (500 × 1536)
            // By running on a detached task, it won't block the main thread
            for data in messageData {
                let similarity = Self.cosineSimilarity(queryEmbedding, data.embedding)
                maxSimilarity = max(maxSimilarity, similarity)

                if similarity >= self.minimumSimilarity {
                    scoredResults.append((data: data, similarity: similarity))
                }
            }

            logger.info("RAG: Max similarity found: \(String(format: "%.3f", maxSimilarity)), threshold: \(self.minimumSimilarity), matches: \(scoredResults.count)")

            // Sort by similarity (highest first) and take top results
            scoredResults.sort { $0.similarity > $1.similarity }
            let topResults = Array(scoredResults.prefix(limit))

            // Convert to RAGResults
            return topResults.map { result -> RAGResult in
                let summary = result.data.summary ?? Self.truncateForSummary(result.data.content)

                return RAGResult(
                    summary: summary,
                    similarity: result.similarity,
                    conversationTitle: result.data.conversationTitle
                )
            }
        }.value
    }

    /// Fetch messages that have embeddings, excluding the specified conversation
    /// Limited to most recent messages for performance with large datasets
    @MainActor
    private func fetchMessagesWithEmbeddings(
        excludeConversation: Conversation?,
        modelContext: ModelContext
    ) throws -> [Message] {
        // Build predicate to fetch messages with embeddings
        // IMPORTANT: Limit to 500 most recent messages for performance
        // This prevents slowdowns when importing large conversation histories
        var descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.embeddingData != nil
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        // Limit to 500 most recent messages to avoid performance issues
        descriptor.fetchLimit = 500

        var messages = try modelContext.fetch(descriptor)

        // Filter out messages from the excluded conversation
        if let excludeConversation = excludeConversation {
            messages = messages.filter { $0.conversation?.id != excludeConversation.id }
        }

        logger.info("RAG: Searching through \(messages.count) recent messages (limited for performance)")
        return messages
    }

    /// Calculate cosine similarity between two vectors
    /// - Returns: Similarity score between -1 and 1 (1 = identical, 0 = orthogonal)
    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
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
    private static func truncateForSummary(_ content: String, maxLength: Int = 100) -> String {
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
