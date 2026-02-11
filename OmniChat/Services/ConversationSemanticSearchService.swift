import Foundation

struct ConversationSemanticSearchResult {
    let conversationId: UUID
    let similarity: Double
}

/// Semantic search over conversations using existing message embeddings.
final class ConversationSemanticSearchService {
    static let shared = ConversationSemanticSearchService()

    private let embeddingService: EmbeddingService
    private let minimumSimilarity: Double = 0.35
    private let maxConversationsToScore = 400
    private let maxEmbeddingsPerConversation = 30

    private struct ConversationData {
        let id: UUID
        let updatedAt: Date
        let embeddings: [[Double]]
    }

    private init(embeddingService: EmbeddingService = .shared) {
        self.embeddingService = embeddingService
    }

    @MainActor
    func search(
        query: String,
        conversations: [Conversation],
        limit: Int = 20
    ) async throws -> [ConversationSemanticSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        guard embeddingService.isConfigured else { return [] }

        let conversationData = extractConversationData(from: conversations)
        guard !conversationData.isEmpty else { return [] }

        let queryEmbedding = try await embeddingService.generateEmbedding(for: trimmedQuery)
        return await scoreConversations(
            queryEmbedding: queryEmbedding,
            conversationData: conversationData,
            limit: limit
        )
    }

    @MainActor
    private func extractConversationData(from conversations: [Conversation]) -> [ConversationData] {
        let recentConversations = conversations
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxConversationsToScore)

        return recentConversations.compactMap { conversation in
            let embeddings = conversation.messages
                .sorted { $0.timestamp > $1.timestamp }
                .compactMap { $0.embeddingVector }

            guard !embeddings.isEmpty else { return nil }

            return ConversationData(
                id: conversation.id,
                updatedAt: conversation.updatedAt,
                embeddings: Array(embeddings.prefix(maxEmbeddingsPerConversation))
            )
        }
    }

    private func scoreConversations(
        queryEmbedding: [Double],
        conversationData: [ConversationData],
        limit: Int
    ) async -> [ConversationSemanticSearchResult] {
        await Task.detached(priority: .userInitiated) {
            var scored: [(id: UUID, similarity: Double, updatedAt: Date)] = []

            for conversation in conversationData {
                if Task.isCancelled { return [] }

                var bestSimilarity = -1.0
                for embedding in conversation.embeddings {
                    let similarity = Self.cosineSimilarity(queryEmbedding, embedding)
                    if similarity > bestSimilarity {
                        bestSimilarity = similarity
                    }
                }

                if bestSimilarity >= self.minimumSimilarity {
                    scored.append((
                        id: conversation.id,
                        similarity: bestSimilarity,
                        updatedAt: conversation.updatedAt
                    ))
                }
            }

            scored.sort {
                if $0.similarity != $1.similarity {
                    return $0.similarity > $1.similarity
                }
                return $0.updatedAt > $1.updatedAt
            }

            return scored.prefix(limit).map {
                ConversationSemanticSearchResult(
                    conversationId: $0.id,
                    similarity: $0.similarity
                )
            }
        }.value
    }

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

        guard magnitudeA > 0, magnitudeB > 0 else { return 0 }
        return dotProduct / (sqrt(magnitudeA) * sqrt(magnitudeB))
    }
}
