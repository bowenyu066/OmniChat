import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.omnichat.app", category: "ChatGPTImport")

/// Service for importing ChatGPT conversation history into OmniChat
@MainActor
@Observable
final class ChatGPTImportService {
    static let shared = ChatGPTImportService()

    private init() {}

    // Background embedding task tracking
    private var backgroundEmbeddingTask: Task<Void, Never>?
    var isGeneratingEmbeddings = false
    var embeddingProgressCount = 0
    var embeddingTotalCount = 0

    // MARK: - Import Progress & Result

    enum ImportPhase: String {
        case parsing = "Parsing JSON..."
        case importing = "Importing conversations..."
        case embedding = "Generating embeddings..."
        case complete = "Complete"
    }

    struct ImportProgress {
        var totalConversations: Int
        var importedConversations: Int
        var currentTitle: String
        var phase: ImportPhase
        var embeddingProgress: Int = 0
        var totalMessagesToEmbed: Int = 0

        var progressFraction: Double {
            guard totalConversations > 0 else { return 0 }
            return Double(importedConversations) / Double(totalConversations)
        }
    }

    struct ImportResult {
        var conversationsImported: Int
        var messagesImported: Int
        var conversationsSkipped: Int
        var errors: [String]
    }

    // MARK: - Main Import Function

    /// Import conversations from a ChatGPT export file
    /// - Parameters:
    ///   - url: URL to the conversations.json file
    ///   - modelContext: SwiftData model context for persistence
    ///   - generateEmbeddings: Whether to generate embeddings for imported messages
    ///   - progressHandler: Callback for progress updates
    /// - Returns: Import result summary
    @MainActor
    func importFromFile(
        _ url: URL,
        modelContext: ModelContext,
        generateEmbeddings: Bool,
        progressHandler: @escaping (ImportProgress) -> Void
    ) async throws -> ImportResult {
        var result = ImportResult(
            conversationsImported: 0,
            messagesImported: 0,
            conversationsSkipped: 0,
            errors: []
        )

        // Phase 1: Parse JSON
        progressHandler(ImportProgress(
            totalConversations: 0,
            importedConversations: 0,
            currentTitle: "",
            phase: .parsing
        ))

        let chatGPTConversations: [ChatGPTConversation]
        do {
            chatGPTConversations = try parseConversationsJSON(url)
            logger.info("Parsed \(chatGPTConversations.count) conversations from JSON")
        } catch {
            logger.error("Failed to parse JSON: \(error.localizedDescription)")
            throw ImportError.parsingFailed(error.localizedDescription)
        }

        // Phase 2: Import conversations
        let totalCount = chatGPTConversations.count
        var importedMessages: [Message] = []

        for (index, chatGPTConvo) in chatGPTConversations.enumerated() {
            progressHandler(ImportProgress(
                totalConversations: totalCount,
                importedConversations: index,
                currentTitle: chatGPTConvo.title,
                phase: .importing
            ))

            do {
                let (conversation, messages) = try createConversation(from: chatGPTConvo, modelContext: modelContext)

                if messages.isEmpty {
                    result.conversationsSkipped += 1
                    logger.debug("Skipped empty conversation: \(chatGPTConvo.title)")
                } else {
                    modelContext.insert(conversation)
                    result.conversationsImported += 1
                    result.messagesImported += messages.count
                    importedMessages.append(contentsOf: messages)
                    logger.debug("Imported: \(chatGPTConvo.title) with \(messages.count) messages")
                }
            } catch {
                result.errors.append("Failed to import '\(chatGPTConvo.title)': \(error.localizedDescription)")
                logger.warning("Failed to import conversation: \(error.localizedDescription)")
            }

            // Save in batches to avoid memory pressure
            if index % 100 == 0 && index > 0 {
                try? modelContext.save()
            }
        }

        // Final save
        try modelContext.save()

        progressHandler(ImportProgress(
            totalConversations: totalCount,
            importedConversations: totalCount,
            currentTitle: "",
            phase: .importing
        ))

        // Phase 3: Queue background embedding generation (optional)
        if generateEmbeddings && !importedMessages.isEmpty {
            // Get message IDs to embed in background
            let messageIDs = importedMessages.filter { $0.role == .assistant && !$0.content.isEmpty }.map { $0.id }
            await startBackgroundEmbedding(messageIDs: messageIDs, modelContainer: modelContext.container)
        }

        progressHandler(ImportProgress(
            totalConversations: totalCount,
            importedConversations: totalCount,
            currentTitle: "",
            phase: .complete
        ))

        logger.info("Import complete: \(result.conversationsImported) conversations, \(result.messagesImported) messages")
        return result
    }

    // MARK: - JSON Parsing

    private func parseConversationsJSON(_ url: URL) throws -> [ChatGPTConversation] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode([ChatGPTConversation].self, from: data)
    }

    // MARK: - Tree Traversal

    /// Extract linear message path from tree structure
    /// Follows the first child at each branch (main conversation path)
    private func extractMessagePath(from mapping: [String: ChatGPTNode]) -> [ExtractedChatGPTMessage] {
        var messages: [ExtractedChatGPTMessage] = []

        // Find root node (parent is null or "client-created-root")
        var currentNodeId: String? = mapping.values.first { node in
            node.parent == nil || node.id == "client-created-root"
        }?.id

        // If we found "client-created-root", start from its first child
        if currentNodeId == "client-created-root",
           let rootNode = mapping["client-created-root"],
           let firstChild = rootNode.children.first {
            currentNodeId = firstChild
        }

        // Traverse the tree following first child
        while let nodeId = currentNodeId, let node = mapping[nodeId] {
            // Extract message if valid
            if let message = node.message {
                let isHidden = message.metadata?.isVisuallyHiddenFromConversation ?? false
                let role = message.author.role

                // Skip hidden messages and system/tool messages
                if !isHidden && (role == "user" || role == "assistant") {
                    // Extract text content from parts
                    let textContent = message.content.parts?
                        .compactMap { $0.stringValue }
                        .joined(separator: "\n") ?? ""

                    if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        messages.append(ExtractedChatGPTMessage(
                            id: message.id,
                            role: role,
                            content: textContent,
                            createTime: message.createTime
                        ))
                    }
                }
            }

            // Move to first child (main branch)
            currentNodeId = node.children.first
        }

        return messages
    }

    // MARK: - Conversation Creation

    private func createConversation(
        from chatGPTConvo: ChatGPTConversation,
        modelContext: ModelContext
    ) throws -> (Conversation, [Message]) {
        // Extract messages from tree
        let extractedMessages = extractMessagePath(from: chatGPTConvo.mapping)

        // Convert timestamps
        let createdAt = Date(timeIntervalSince1970: chatGPTConvo.createTime)
        let updatedAt = Date(timeIntervalSince1970: chatGPTConvo.updateTime)

        // Create conversation
        let conversation = Conversation(
            title: chatGPTConvo.title,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        conversation.hasTitleBeenGenerated = true  // Don't regenerate imported titles

        // Create messages
        var messages: [Message] = []
        for extracted in extractedMessages {
            let role: MessageRole = extracted.role == "user" ? .user : .assistant
            let timestamp = extracted.createTime.map { Date(timeIntervalSince1970: $0) } ?? createdAt

            let message = Message(
                role: role,
                content: extracted.content,
                timestamp: timestamp,
                modelUsed: extracted.role == "assistant" ? "ChatGPT (imported)" : nil
            )
            message.conversation = conversation
            messages.append(message)
        }

        conversation.messages = messages
        return (conversation, messages)
    }

    // MARK: - Background Embedding Generation

    /// Start background embedding generation for imported messages
    private func startBackgroundEmbedding(messageIDs: [UUID], modelContainer: ModelContainer) {
        // Cancel any existing background task
        backgroundEmbeddingTask?.cancel()

        isGeneratingEmbeddings = true
        embeddingProgressCount = 0
        embeddingTotalCount = messageIDs.count

        logger.info("Starting background embedding for \(messageIDs.count) messages")

        backgroundEmbeddingTask = Task.detached(priority: .background) {
            await Self.performBackgroundEmbedding(
                messageIDs: messageIDs,
                modelContainer: modelContainer,
                onProgress: { count in
                    Task { @MainActor in
                        ChatGPTImportService.shared.embeddingProgressCount = count
                    }
                },
                onComplete: {
                    Task { @MainActor in
                        ChatGPTImportService.shared.isGeneratingEmbeddings = false
                    }
                }
            )
        }
    }

    /// Perform embedding generation in background (static to avoid actor isolation issues)
    private static func performBackgroundEmbedding(
        messageIDs: [UUID],
        modelContainer: ModelContainer,
        onProgress: @escaping (Int) -> Void,
        onComplete: @escaping () -> Void
    ) async {
        let embeddingService = EmbeddingService.shared

        guard embeddingService.isConfigured else {
            logger.warning("Embedding service not configured, skipping embeddings")
            onComplete()
            return
        }

        // Create a new model context for background work
        let context = ModelContext(modelContainer)
        var progressCount = 0

        // Process in batches
        let batchSize = 10
        for batchIDs in messageIDs.chunked(into: batchSize) {
            // Check for cancellation
            if Task.isCancelled {
                logger.info("Background embedding cancelled")
                break
            }

            for messageID in batchIDs {
                // Check for cancellation
                if Task.isCancelled { break }

                // Fetch message by ID
                let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.id == messageID })
                guard let message = try? context.fetch(descriptor).first else { continue }

                // Skip if already embedded
                if message.hasEmbedding { continue }

                do {
                    let embedding = try await embeddingService.generateEmbedding(for: message.content)
                    message.embeddingVector = embedding
                    message.embeddedAt = Date()
                } catch {
                    logger.warning("Failed to generate embedding: \(error.localizedDescription)")
                }

                progressCount += 1
                onProgress(progressCount)
            }

            // Save batch
            try? context.save()

            // Small pause between batches to avoid overwhelming the API
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        logger.info("Background embedding complete: \(progressCount)/\(messageIDs.count)")
        onComplete()
    }

    /// Cancel any ongoing background embedding
    func cancelBackgroundEmbedding() {
        backgroundEmbeddingTask?.cancel()
        backgroundEmbeddingTask = nil
        isGeneratingEmbeddings = false
    }
}

// MARK: - Errors

enum ImportError: LocalizedError {
    case parsingFailed(String)
    case fileNotFound
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .parsingFailed(let message):
            return "Failed to parse file: \(message)"
        case .fileNotFound:
            return "File not found"
        case .invalidFormat:
            return "Invalid file format. Expected ChatGPT conversations.json"
        }
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
