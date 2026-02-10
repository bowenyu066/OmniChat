import Foundation
import SwiftData
import os.log
import Compression

private let logger = Logger(subsystem: "com.omnichat.app", category: "ChatGPTImport")

/// Service for importing ChatGPT conversation history into OmniChat
@MainActor
@Observable
final class ChatGPTImportService {
    static let shared = ChatGPTImportService()

    private init() {}

    /// Temporary directory for ZIP extraction
    private var extractedZipDir: URL?

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
        var conversationsUpdated: Int = 0  // Existing conversations that were updated (e.g., images added)
        var messagesImported: Int
        var messagesUpdated: Int = 0  // Existing messages that were updated
        var imagesImported: Int = 0
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

            let importSourceId = makeImportSourceId(for: chatGPTConvo)

            // Check for existing conversation (deduplication)
            if findExistingConversation(importSourceId: importSourceId, modelContext: modelContext) != nil {
                result.conversationsSkipped += 1
                logger.debug("Skipped duplicate: \(chatGPTConvo.title)")
                continue
            }

            do {
                let (conversation, messages) = try createConversation(from: chatGPTConvo, modelContext: modelContext)

                if messages.isEmpty {
                    result.conversationsSkipped += 1
                    logger.debug("Skipped empty conversation: \(chatGPTConvo.title)")
                } else {
                    // Set import source ID for future deduplication
                    conversation.importSourceId = importSourceId
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

    // MARK: - ZIP Import

    /// Import conversations from a ChatGPT export ZIP file (includes images)
    @MainActor
    func importFromZip(
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

        // Phase 1: Extract ZIP
        progressHandler(ImportProgress(
            totalConversations: 0,
            importedConversations: 0,
            currentTitle: "Extracting ZIP...",
            phase: .parsing
        ))

        let extractedDir = try extractZip(url)
        self.extractedZipDir = extractedDir
        defer {
            // Cleanup extracted directory
            try? FileManager.default.removeItem(at: extractedDir)
            self.extractedZipDir = nil
        }

        // Find conversations.json
        let conversationsJsonURL = extractedDir.appendingPathComponent("conversations.json")
        guard FileManager.default.fileExists(atPath: conversationsJsonURL.path) else {
            throw ImportError.invalidFormat
        }

        // Phase 2: Parse JSON
        progressHandler(ImportProgress(
            totalConversations: 0,
            importedConversations: 0,
            currentTitle: "",
            phase: .parsing
        ))

        let chatGPTConversations: [ChatGPTConversation]
        do {
            chatGPTConversations = try parseConversationsJSON(conversationsJsonURL)
            logger.info("Parsed \(chatGPTConversations.count) conversations from ZIP")
        } catch {
            logger.error("Failed to parse JSON: \(error.localizedDescription)")
            throw ImportError.parsingFailed(error.localizedDescription)
        }

        // Build image file index from extracted directory
        let imageIndex = buildImageFileIndex(in: extractedDir)
        logger.info("Found \(imageIndex.count) image files in ZIP")

        // Phase 3: Import conversations
        let totalCount = chatGPTConversations.count
        var importedMessages: [Message] = []

        for (index, chatGPTConvo) in chatGPTConversations.enumerated() {
            progressHandler(ImportProgress(
                totalConversations: totalCount,
                importedConversations: index,
                currentTitle: chatGPTConvo.title,
                phase: .importing
            ))

            let importSourceId = makeImportSourceId(for: chatGPTConvo)

            // Check for existing conversation (deduplication)
            if let existingConvo = findExistingConversation(importSourceId: importSourceId, modelContext: modelContext) {
                // Update existing conversation with images
                let (messagesUpdated, imagesAdded) = updateConversationWithImages(
                    existing: existingConvo,
                    from: chatGPTConvo,
                    imageIndex: imageIndex,
                    modelContext: modelContext
                )

                if imagesAdded > 0 {
                    result.conversationsUpdated += 1
                    result.messagesUpdated += messagesUpdated
                    result.imagesImported += imagesAdded
                    logger.debug("Updated: \(chatGPTConvo.title) - added \(imagesAdded) images to \(messagesUpdated) messages")
                } else {
                    result.conversationsSkipped += 1
                    logger.debug("Skipped duplicate: \(chatGPTConvo.title) (no new images)")
                }
                continue
            }

            // Create new conversation
            do {
                let (conversation, messages) = try createConversationWithImages(
                    from: chatGPTConvo,
                    imageIndex: imageIndex,
                    modelContext: modelContext
                )

                if messages.isEmpty {
                    result.conversationsSkipped += 1
                    logger.debug("Skipped empty conversation: \(chatGPTConvo.title)")
                } else {
                    // Set import source ID for future deduplication
                    conversation.importSourceId = importSourceId
                    modelContext.insert(conversation)
                    result.conversationsImported += 1
                    result.messagesImported += messages.count
                    // Count images from attachments
                    let imageCount = messages.reduce(0) { $0 + $1.attachments.count }
                    result.imagesImported += imageCount
                    importedMessages.append(contentsOf: messages)
                    logger.debug("Imported: \(chatGPTConvo.title) with \(messages.count) messages, \(imageCount) images")
                }
            } catch {
                result.errors.append("Failed to import '\(chatGPTConvo.title)': \(error.localizedDescription)")
                logger.warning("Failed to import conversation: \(error.localizedDescription)")
            }

            // Save in batches to avoid memory pressure
            if index % 50 == 0 && index > 0 {
                try? modelContext.save()
            }
        }

        // Final save
        try modelContext.save()

        // Phase 4: Queue background embedding generation (optional)
        if generateEmbeddings && !importedMessages.isEmpty {
            let messageIDs = importedMessages.filter { $0.role == .assistant && !$0.content.isEmpty }.map { $0.id }
            await startBackgroundEmbedding(messageIDs: messageIDs, modelContainer: modelContext.container)
        }

        progressHandler(ImportProgress(
            totalConversations: totalCount,
            importedConversations: totalCount,
            currentTitle: "",
            phase: .complete
        ))

        logger.info("ZIP Import complete: \(result.conversationsImported) conversations, \(result.messagesImported) messages, \(result.imagesImported) images")
        return result
    }

    // MARK: - ZIP Extraction

    /// Extract ZIP file to temporary directory using unzip command
    private func extractZip(_ zipURL: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatgpt_import_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Use unzip command for extraction
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipURL.path, "-d", tempDir.path]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ImportError.parsingFailed("Failed to extract ZIP: \(errorMessage)")
        }

        return tempDir
    }

    /// Build an index of all image files in the extracted directory
    /// Maps file IDs (like "file-AbCdEf123456") to their file URLs
    private func buildImageFileIndex(in directory: URL) -> [String: URL] {
        var index: [String: URL] = [:]

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return index
        }

        let imageExtensions = Set(["png", "jpg", "jpeg", "gif", "webp"])

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }

            // The filename might be the file ID directly, or contain it
            let filename = fileURL.deletingPathExtension().lastPathComponent

            // Try different patterns for file ID extraction
            // Pattern 1: filename is the file ID (e.g., "file-AbCdEf123456.png")
            if filename.hasPrefix("file-") {
                index[filename] = fileURL
            }

            // Pattern 2: Just use the full filename as key
            index[fileURL.lastPathComponent] = fileURL
        }

        return index
    }

    // MARK: - JSON Parsing

    private func parseConversationsJSON(_ url: URL) throws -> [ChatGPTConversation] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode([ChatGPTConversation].self, from: data)
    }

    // MARK: - Deduplication Helpers

    /// Generate a unique import source ID for a ChatGPT conversation
    private func makeImportSourceId(for chatGPTConvo: ChatGPTConversation) -> String {
        return "chatgpt:\(chatGPTConvo.createTime)"
    }

    /// Find an existing conversation by import source ID
    private func findExistingConversation(
        importSourceId: String,
        modelContext: ModelContext
    ) -> Conversation? {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.importSourceId == importSourceId }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Find an existing message within a conversation by import message ID
    private func findExistingMessage(
        importMessageId: String,
        in conversation: Conversation
    ) -> Message? {
        return conversation.messages.first { $0.importMessageId == importMessageId }
    }

    /// Update an existing conversation with images from a re-import
    /// Returns (messagesUpdated, imagesAdded)
    private func updateConversationWithImages(
        existing: Conversation,
        from chatGPTConvo: ChatGPTConversation,
        imageIndex: [String: URL],
        modelContext: ModelContext
    ) -> (Int, Int) {
        let extractedMessages = extractMessagePath(from: chatGPTConvo.mapping)

        var messagesUpdated = 0
        var imagesAdded = 0

        for extracted in extractedMessages {
            // Find matching message by import ID
            guard let existingMessage = findExistingMessage(importMessageId: extracted.id, in: existing) else {
                continue
            }

            // Skip if no new images to add
            guard !extracted.imageFileIds.isEmpty else { continue }

            // Check which images are already attached
            let existingFilenames = Set(existingMessage.attachments.map { $0.filename ?? "" })

            var addedAny = false
            for fileId in extracted.imageFileIds {
                // Load the image
                if let attachment = loadImageAttachment(fileId: fileId, from: imageIndex, modelContext: modelContext) {
                    // Skip if already attached (by filename match)
                    if existingFilenames.contains(attachment.filename ?? "") {
                        continue
                    }
                    existingMessage.attachments.append(attachment)
                    imagesAdded += 1
                    addedAny = true
                }
            }

            if addedAny {
                messagesUpdated += 1
            }
        }

        // Update the conversation's updatedAt if we added images
        if imagesAdded > 0 {
            existing.updatedAt = Date()
        }

        return (messagesUpdated, imagesAdded)
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
                    // Extract text content and image file IDs from parts
                    var textParts: [String] = []
                    var imageFileIds: [String] = []

                    if let parts = message.content.parts {
                        for part in parts {
                            if let text = part.stringValue {
                                textParts.append(text)
                            } else if let imagePart = part.imagePart, let fileId = imagePart.fileId {
                                imageFileIds.append(fileId)
                            }
                        }
                    }

                    let textContent = textParts.joined(separator: "\n")

                    // Include message if it has text OR images
                    if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageFileIds.isEmpty {
                        var extracted = ExtractedChatGPTMessage(
                            id: message.id,
                            role: role,
                            content: textContent,
                            createTime: message.createTime
                        )
                        extracted.imageFileIds = imageFileIds
                        messages.append(extracted)
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
            message.importMessageId = extracted.id  // Store original ID for deduplication
            message.conversation = conversation
            messages.append(message)
        }

        conversation.messages = messages
        return (conversation, messages)
    }

    /// Create conversation with image support from ChatGPT export
    private func createConversationWithImages(
        from chatGPTConvo: ChatGPTConversation,
        imageIndex: [String: URL],
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
            message.importMessageId = extracted.id  // Store original ID for deduplication

            // Load and attach images
            for fileId in extracted.imageFileIds {
                if let attachment = loadImageAttachment(fileId: fileId, from: imageIndex, modelContext: modelContext) {
                    message.attachments.append(attachment)
                }
            }

            message.conversation = conversation
            messages.append(message)
        }

        conversation.messages = messages
        return (conversation, messages)
    }

    /// Load an image file from the index and create an Attachment
    private func loadImageAttachment(fileId: String, from imageIndex: [String: URL], modelContext: ModelContext) -> Attachment? {
        // Try to find the file in the index
        var fileURL: URL?

        // Try exact match first
        if let url = imageIndex[fileId] {
            fileURL = url
        } else {
            // Try with common extensions
            for ext in ["png", "jpg", "jpeg", "webp", "gif"] {
                if let url = imageIndex["\(fileId).\(ext)"] {
                    fileURL = url
                    break
                }
            }
        }

        guard let url = fileURL else {
            logger.debug("Image file not found for ID: \(fileId)")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let mimeType = mimeTypeForExtension(url.pathExtension)

            let attachment = Attachment(
                type: .image,
                mimeType: mimeType,
                data: data,
                filename: url.lastPathComponent
            )
            modelContext.insert(attachment)

            logger.debug("Loaded image: \(url.lastPathComponent) (\(data.count) bytes)")
            return attachment
        } catch {
            logger.warning("Failed to load image \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// Get MIME type for file extension
    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
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
