import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.omnichat.app", category: "RAGService")

enum RAGContextKind: String {
    case fullConversation = "full"
    case snippet = "snippet"
}

/// Result from RAG retrieval containing relevant past conversation context
struct RAGResult {
    let conversationId: UUID
    let summary: String
    let similarity: Double
    let conversationTitle: String
    let kind: RAGContextKind
}

/// Service for retrieving relevant past conversation context using semantic search
/// SwiftData operations are marked @MainActor, but similarity calculations run on background threads
final class RAGService {
    static let shared = RAGService()

    private let embeddingService: EmbeddingService

    // Base relevance threshold.
    private let minimumSimilarity: Double = 0.3

    // If even the best hit is below this, skip RAG context entirely.
    private let weakSignalCutoff: Double = 0.34

    // Conversations above this (or close to top hit) may be included as full context.
    private let strongConversationThreshold: Double = 0.58
    private let strongRelativeDelta: Double = 0.07

    private let maxFullConversations = 5
    private let maxMessagesToFetch = 3000
    private let maxTranscriptCharsPerConversation = 2800

    /// Message data extracted from SwiftData for thread-safe processing
    private struct MessageData {
        let conversationId: UUID
        let conversationTitle: String
        let conversationUpdatedAt: Date
        let timestamp: Date
        let content: String
        let summary: String?
        let embedding: [Double]
    }

    private struct ConversationContextData {
        let id: UUID
        let title: String
        let updatedAt: Date
        let transcript: String
    }

    private struct RAGCorpusData {
        let messages: [MessageData]
        let conversationContexts: [UUID: ConversationContextData]
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
    ///   - limit: Baseline number of snippet results to target
    /// - Returns: Array of RAGResult with deduplicated conversation coverage
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

        let extractStartTime = Date()
        let corpus = try extractCorpus(
            excludeConversation: excludeConversation,
            modelContext: modelContext
        )
        let extractMs = Int(Date().timeIntervalSince(extractStartTime) * 1000)

        guard !corpus.messages.isEmpty else {
            logger.debug("No messages with embeddings found for RAG")
            return []
        }

        logger.info("RAG: Found \(corpus.messages.count) embedded messages across \(corpus.conversationContexts.count) conversations")

        let embeddingStartTime = Date()
        let queryEmbedding: [Double]
        do {
            queryEmbedding = try await embeddingService.generateEmbedding(for: trimmedQuery)
        } catch {
            logger.error("Failed to generate query embedding: \(error.localizedDescription)")
            throw error
        }
        let embeddingMs = Int(Date().timeIntervalSince(embeddingStartTime) * 1000)

        let similarityStartTime = Date()
        let results = await calculateAdaptiveResultsAsync(
            corpus: corpus,
            queryEmbedding: queryEmbedding,
            baselineLimit: limit
        )
        let similarityMs = Int(Date().timeIntervalSince(similarityStartTime) * 1000)

        let totalMs = Int(Date().timeIntervalSince(startTime) * 1000)
        let fullCount = results.filter { $0.kind == .fullConversation }.count
        let snippetCount = results.filter { $0.kind == .snippet }.count
        print(
            "PERF_RAG total_ms=\(totalMs) extract_ms=\(extractMs) embedding_ms=\(embeddingMs) similarity_ms=\(similarityMs) " +
            "messages_searched=\(corpus.messages.count) results=\(results.count) full=\(fullCount) snippets=\(snippetCount)"
        )

        return results
    }

    /// Extract and prepare thread-safe RAG corpus on MainActor.
    @MainActor
    private func extractCorpus(
        excludeConversation: Conversation?,
        modelContext: ModelContext
    ) throws -> RAGCorpusData {
        let messagesWithEmbeddings = try fetchMessagesWithEmbeddings(
            excludeConversation: excludeConversation,
            modelContext: modelContext
        )

        var messageData: [MessageData] = []
        messageData.reserveCapacity(messagesWithEmbeddings.count)

        var conversationsById: [UUID: Conversation] = [:]

        for message in messagesWithEmbeddings {
            guard message.role != .system else { continue }
            guard let embedding = message.embeddingVector else { continue }
            guard let conversation = message.conversation else { continue }

            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }

            conversationsById[conversation.id] = conversation

            messageData.append(
                MessageData(
                    conversationId: conversation.id,
                    conversationTitle: conversation.title,
                    conversationUpdatedAt: conversation.updatedAt,
                    timestamp: message.timestamp,
                    content: content,
                    summary: message.summary,
                    embedding: embedding
                )
            )
        }

        var conversationContexts: [UUID: ConversationContextData] = [:]
        conversationContexts.reserveCapacity(conversationsById.count)

        for (_, conversation) in conversationsById {
            let transcript = buildConversationTranscript(conversation)
            guard !transcript.isEmpty else { continue }

            conversationContexts[conversation.id] = ConversationContextData(
                id: conversation.id,
                title: conversation.title,
                updatedAt: conversation.updatedAt,
                transcript: transcript
            )
        }

        return RAGCorpusData(messages: messageData, conversationContexts: conversationContexts)
    }

    @MainActor
    private func buildConversationTranscript(_ conversation: Conversation) -> String {
        let visible = visibleMessages(in: conversation)
        guard !visible.isEmpty else { return "" }

        var lines: [String] = []
        lines.reserveCapacity(visible.count)

        for message in visible {
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let prefix: String
            switch message.role {
            case .user:
                prefix = "User"
            case .assistant:
                prefix = "Assistant"
            case .system:
                prefix = "System"
            }

            lines.append("\(prefix): \(text)")
        }

        guard !lines.isEmpty else { return "" }

        let full = lines.joined(separator: "\n")
        return Self.truncateMiddle(full, maxLength: maxTranscriptCharsPerConversation)
    }

    @MainActor
    private func visibleMessages(in conversation: Conversation) -> [Message] {
        let sorted = conversation.messages.sorted { $0.timestamp < $1.timestamp }
        var visibleIds = Set<UUID>()
        var visible: [Message] = []

        for message in sorted {
            guard message.isActive else { continue }

            let shouldShow: Bool
            if message.precedingMessageId == nil {
                shouldShow = true
            } else if let precedingId = message.precedingMessageId {
                shouldShow = visibleIds.contains(precedingId)
            } else {
                shouldShow = false
            }

            guard shouldShow else { continue }
            visibleIds.insert(message.id)
            visible.append(message)
        }

        return visible
    }

    /// Adaptive retrieval with conversation-level dedup and mixed full/snippet context.
    private func calculateAdaptiveResultsAsync(
        corpus: RAGCorpusData,
        queryEmbedding: [Double],
        baselineLimit: Int
    ) async -> [RAGResult] {
        let task: Task<[RAGResult], Never> = Task.detached(priority: .userInitiated) {
            struct ScoredMessage {
                let data: MessageData
                let similarity: Double
            }

            struct ConversationScore {
                let conversationId: UUID
                let title: String
                let similarity: Double
                let updatedAt: Date
            }

            var scoredMessages: [ScoredMessage] = []
            scoredMessages.reserveCapacity(corpus.messages.count)
            var maxSimilarity: Double = 0

            for data in corpus.messages {
                if Task.isCancelled { return [] }

                let similarity = Self.cosineSimilarity(queryEmbedding, data.embedding)
                maxSimilarity = max(maxSimilarity, similarity)

                if similarity >= self.minimumSimilarity {
                    scoredMessages.append(ScoredMessage(data: data, similarity: similarity))
                }
            }

            guard !scoredMessages.isEmpty else {
                logger.info("RAG: No messages above similarity threshold")
                return []
            }

            scoredMessages.sort {
                if $0.similarity != $1.similarity {
                    return $0.similarity > $1.similarity
                }
                return $0.data.timestamp > $1.data.timestamp
            }

            guard let topScore = scoredMessages.first?.similarity else {
                return []
            }

            if topScore < self.weakSignalCutoff {
                logger.info("RAG: Top similarity \(String(format: "%.3f", topScore)) below weak cutoff \(self.weakSignalCutoff), skipping context")
                return []
            }

            let groupedByConversation = Dictionary(grouping: scoredMessages, by: { $0.data.conversationId })

            var conversationScores: [ConversationScore] = []
            conversationScores.reserveCapacity(groupedByConversation.count)

            for (conversationId, candidates) in groupedByConversation {
                guard let best = candidates.first else { continue }
                conversationScores.append(
                    ConversationScore(
                        conversationId: conversationId,
                        title: best.data.conversationTitle,
                        similarity: best.similarity,
                        updatedAt: best.data.conversationUpdatedAt
                    )
                )
            }

            conversationScores.sort {
                if $0.similarity != $1.similarity {
                    return $0.similarity > $1.similarity
                }
                return $0.updatedAt > $1.updatedAt
            }

            var scoreByConversationId: [UUID: Double] = [:]
            for item in conversationScores {
                scoreByConversationId[item.conversationId] = item.similarity
            }

            let maxFullByConfidence: Int
            switch topScore {
            case 0.80...:
                maxFullByConfidence = 5
            case 0.72...:
                maxFullByConfidence = 4
            case 0.64...:
                maxFullByConfidence = 3
            case 0.58...:
                maxFullByConfidence = 2
            default:
                maxFullByConfidence = 1
            }

            let fullThreshold = max(self.strongConversationThreshold, topScore - self.strongRelativeDelta)
            let fullConversationIds = Array(
                conversationScores
                    .filter { $0.similarity >= fullThreshold }
                    .prefix(min(self.maxFullConversations, maxFullByConfidence))
                    .map { $0.conversationId }
            )
            let fullConversationSet = Set(fullConversationIds)

            var results: [RAGResult] = []
            results.reserveCapacity(12)

            // 1) Full context for strongest conversations.
            for conversationId in fullConversationIds {
                guard let context = corpus.conversationContexts[conversationId] else { continue }
                guard let score = scoreByConversationId[conversationId] else { continue }

                results.append(
                    RAGResult(
                        conversationId: conversationId,
                        summary: context.transcript,
                        similarity: score,
                        conversationTitle: context.title,
                        kind: .fullConversation
                    )
                )
            }

            // 2) Snippets from other conversations for breadth.
            let snippetLimit: Int
            switch topScore {
            case 0.78...:
                snippetLimit = 6
            case 0.65...:
                snippetLimit = 5
            case 0.52...:
                snippetLimit = 4
            default:
                snippetLimit = 2
            }

            let baselineSnippetTarget = max(1, baselineLimit)
            let targetSnippets = min(8, max(snippetLimit, baselineSnippetTarget))

            // Keep snippet coverage broad: at most one snippet per conversation.
            let perConversationSnippetCap = 1
            var snippetsAdded = 0

            for conversation in conversationScores where !fullConversationSet.contains(conversation.conversationId) {
                guard snippetsAdded < targetSnippets else { break }
                guard let candidates = groupedByConversation[conversation.conversationId] else { continue }

                var addedForConversation = 0
                for candidate in candidates {
                    guard snippetsAdded < targetSnippets else { break }
                    guard addedForConversation < perConversationSnippetCap else { break }

                    let snippet = candidate.data.summary ?? Self.truncateForSummary(candidate.data.content)
                    let cleanSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanSnippet.isEmpty else { continue }

                    results.append(
                        RAGResult(
                            conversationId: candidate.data.conversationId,
                            summary: cleanSnippet,
                            similarity: candidate.similarity,
                            conversationTitle: candidate.data.conversationTitle,
                            kind: .snippet
                        )
                    )
                    snippetsAdded += 1
                    addedForConversation += 1
                }
            }

            let fullCount = results.filter { $0.kind == .fullConversation }.count
            let snippetCount = results.filter { $0.kind == .snippet }.count
            print(
                "RAG_SELECTION top=\(String(format: "%.3f", topScore)) full=\(fullCount) " +
                "snippets=\(snippetCount) conversations=\(conversationScores.count)"
            )

            return results
        }
        return await task.value
    }

    /// Fetch messages that have embeddings, excluding the specified conversation
    /// Limited to most recent messages for performance with large datasets
    @MainActor
    private func fetchMessagesWithEmbeddings(
        excludeConversation: Conversation?,
        modelContext: ModelContext
    ) throws -> [Message] {
        var descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { message in
                message.embeddingData != nil
            },
            sortBy: [SortDescriptor(\Message.timestamp, order: .reverse)]
        )

        descriptor.fetchLimit = maxMessagesToFetch

        var messages = try modelContext.fetch(descriptor)

        if let excludeConversation = excludeConversation {
            messages = messages.filter { $0.conversation?.id != excludeConversation.id }
        }

        logger.info("RAG: Searching through \(messages.count) recent embedded messages")
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

    private static func truncateForSummary(_ content: String, maxLength: Int = 120) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > maxLength {
            return String(trimmed.prefix(maxLength)) + "..."
        }
        return trimmed
    }

    private static func truncateMiddle(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength, maxLength > 40 else { return text }

        let headCount = Int(Double(maxLength) * 0.55)
        let tailCount = maxLength - headCount - 14

        let head = String(text.prefix(headCount))
        let tail = String(text.suffix(max(0, tailCount)))
        return "\(head)\n\n...[truncated]...\n\n\(tail)"
    }
}

// MARK: - RAGResult Formatting

extension RAGService {
    /// Format RAG results as a string for inclusion in system prompt
    static func formatResultsForPrompt(_ results: [RAGResult]) -> String {
        guard !results.isEmpty else { return "" }

        let maxTotalChars = 9000
        var remainingChars = maxTotalChars
        var formatted = "## Relevant Past Conversations\n"
        formatted += "Use the following prior context only when relevant to the current user request.\n"
        remainingChars -= formatted.count

        func appendLimited(_ text: String) {
            guard remainingChars > 0 else { return }
            if text.count <= remainingChars {
                formatted += text
                remainingChars -= text.count
            } else {
                formatted += String(text.prefix(remainingChars))
                remainingChars = 0
            }
        }

        let fullResults = results.filter { $0.kind == .fullConversation }
        let snippetResults = results.filter { $0.kind == .snippet }

        if !fullResults.isEmpty {
            appendLimited("\n### Highly Relevant Conversations (Full Context)\n")
            for result in fullResults {
                guard remainingChars > 0 else { break }

                let header = "\n#### From \"\(result.conversationTitle)\" (score: \(String(format: "%.2f", result.similarity)))\n"
                appendLimited(header)

                let bodyMax = min(2800, max(0, remainingChars - 4))
                let body = truncateMiddle(result.summary, maxLength: bodyMax)
                appendLimited(body + "\n")
            }
        }

        if !snippetResults.isEmpty && remainingChars > 0 {
            appendLimited("\n### Additional Relevant Snippets\n")
            for result in snippetResults {
                guard remainingChars > 0 else { break }

                let snippet = truncateForSummary(result.summary, maxLength: 220)
                let line = "\n- \"\(result.conversationTitle)\" (score: \(String(format: "%.2f", result.similarity))): \(snippet)\n"
                appendLimited(line)
            }
        }

        return formatted
    }
}
