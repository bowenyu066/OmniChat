import SwiftUI
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.omnichat.app", category: "ChatView")

struct ChatView: View {
    @Bindable var conversation: Conversation
    @Binding var selectedModel: AIModel

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<MemoryItem> { !$0.isDeleted }, sort: \MemoryItem.updatedAt, order: .reverse)
    private var allMemories: [MemoryItem]
    @Query(sort: \Workspace.name)
    private var allWorkspaces: [Workspace]

    @State private var inputText = ""
    @State private var pendingAttachments: [PendingAttachment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentStreamingMessage: Message?
    @State private var showMemoryPanel = true
    @State private var memoryContextConfig = MemoryContextConfig()
    @State private var sortedMessagesCache: [Message] = []
    @State private var activeStreamID: UUID?
    @State private var activeStreamScrollEvents = 0
    @State private var activeStreamUIUpdates = 0

    // Streaming content buffer - avoids SwiftData updates during streaming
    // This is updated frequently, while SwiftData is only updated when streaming completes
    @State private var streamingContent: String = ""

    // Throttle scroll updates to reduce re-renders during streaming
    @State private var lastScrollUpdate = Date.distantPast

    var onBranchConversation: ((Conversation) -> Void)?

    private let apiServiceFactory = APIServiceFactory()

    var body: some View {
        HSplitView {
            // Main chat area
            chatContent

            // Memory context panel (right side)
            if showMemoryPanel {
                ChatMemoryContextView(config: $memoryContextConfig)
            }
        }
        .onAppear {
            // Load memory config from conversation
            memoryContextConfig = conversation.memoryContextConfig
            refreshSortedMessages()
        }
        .onChange(of: memoryContextConfig) { _, newConfig in
            // Save memory config to conversation
            conversation.memoryContextConfig = newConfig
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider()
            messagesScrollView
        }
    }

    private var chatHeader: some View {
        ChatHeaderView(
            conversation: conversation,
            workspaces: allWorkspaces,
            selectedModel: $selectedModel,
            showMemoryPanel: $showMemoryPanel
        )
    }

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                messagesList
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: conversation.messages.count) { _, _ in
                refreshSortedMessages()
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: streamingContent) { _, _ in
                handleStreamingContentChange(proxy: proxy)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomInputArea
            }
        }
    }

    private var messagesList: some View {
        LazyVStack(spacing: 16) {
            ForEach(sortedMessagesCache) { message in
                let isThisStreaming = currentStreamingMessage?.id == message.id
                let siblings = getSiblings(for: message)
                MessageView(
                    message: message,
                    isStreaming: isThisStreaming,
                    streamingContent: isThisStreaming ? streamingContent : nil,
                    siblings: siblings,
                    onRetry: message.role == .assistant ? { retryMessage(message) } : nil,
                    onSwitchModel: message.role == .assistant ? { newModel in switchModel(for: message, to: newModel) } : nil,
                    onBranch: message.role == .assistant ? { branchFromMessage(message) } : nil,
                    onSwitchSibling: message.role == .assistant && siblings.count > 1 ? { sibling in switchToSibling(sibling) } : nil
                )
                .id(message.id)
            }

            if isLoading {
                loadingIndicator
            }
        }
        .padding(.vertical)
    }

    private var loadingIndicator: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Thinking...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .id("loading")
    }

    private var bottomInputArea: some View {
        VStack(spacing: 0) {
            errorBanner
            Divider()
            inputView
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(error)
                    .font(.caption)
                Spacer()
                Button("Dismiss") {
                    errorMessage = nil
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
        }
    }

    private var inputView: some View {
        MessageInputView(
            text: $inputText,
            pendingAttachments: $pendingAttachments,
            isLoading: isLoading,
            onSend: sendMessage
        )
        .padding()
        .background(.bar)
    }

    private func handleStreamingContentChange(proxy: ScrollViewProxy) {
        // Throttle scroll updates to max 10 per second during streaming
        // This prevents excessive re-renders when text chunks arrive rapidly
        let now = Date()
        if now.timeIntervalSince(lastScrollUpdate) >= 0.1 {
            lastScrollUpdate = now
            if activeStreamID != nil {
                activeStreamScrollEvents += 1
            }
            scrollToBottom(proxy: proxy, animated: false)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if let lastMessage = sortedMessagesCache.last {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        } else if isLoading {
            if animated {
                withAnimation {
                    proxy.scrollTo("loading", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("loading", anchor: .bottom)
            }
        }
    }

    private func refreshSortedMessages() {
        // Filter to only show active messages (hides inactive sibling branches)
        sortedMessagesCache = conversation.messages
            .filter { $0.isActive }
            .sorted(by: { $0.timestamp < $1.timestamp })
    }

    private func getSystemPrompt(for provider: AIProvider, userPrompt: String = "") async -> String {
        let startTime = Date()

        var prompt = """
        You are a helpful AI assistant. Keep responses clear and concise.
        """

        // Layer 1: Include memories based on config (highest priority)
        let memoryStartTime = Date()
        let includedMemories = getIncludedMemories()
        if !includedMemories.isEmpty {
            prompt += "\n\n## User Memory\nThe following information has been provided by the user as context. Use this knowledge when relevant:\n"

            for memory in includedMemories {
                prompt += "\n### \(memory.type.rawValue): \(memory.title)\n\(memory.body)\n"
            }
        }
        let memoryMs = Int(Date().timeIntervalSince(memoryStartTime) * 1000)

        // Layer 2: RAG - Past Conversations (semantic search across all conversations)
        let ragStartTime = Date()
        var ragResultCount = 0
        if !userPrompt.isEmpty {
            do {
                let ragResults = try await RAGService.shared.retrieveRelevantContext(
                    for: userPrompt,
                    excludeConversation: conversation,
                    modelContext: modelContext,
                    limit: 5
                )

                ragResultCount = ragResults.count
                if !ragResults.isEmpty {
                    prompt += "\n\n" + RAGService.formatResultsForPrompt(ragResults)
                    logger.debug("RAG: Added \(ragResults.count) relevant past conversations to context")
                }
            } catch {
                logger.warning("RAG retrieval failed: \(error.localizedDescription)")
                // Continue without RAG results - graceful degradation
            }
        }
        let ragMs = Int(Date().timeIntervalSince(ragStartTime) * 1000)

        // Layer 3: Include workspace files if workspace is selected
        let workspaceStartTime = Date()
        var workspaceSnippetCount = 0
        if let workspace = conversation.workspace, !userPrompt.isEmpty {
            let fileSnippets = FileRetriever.shared.retrieveSnippets(
                for: userPrompt,
                workspace: workspace,
                limit: 5
            )

            workspaceSnippetCount = fileSnippets.count
            if !fileSnippets.isEmpty {
                prompt += "\n\n## Workspace Files\nThe following code snippets from the workspace may be relevant. Always cite files when referencing them:\n"

                for snippet in fileSnippets {
                    prompt += "\n### \(snippet.citation)\n```\n\(snippet.content)\n```\n"
                }

                prompt += "\nWhen referencing these files, always use the format `file.swift:line` for clarity.\n"
            }
        }
        let workspaceMs = Int(Date().timeIntervalSince(workspaceStartTime) * 1000)

        let totalMs = Int(Date().timeIntervalSince(startTime) * 1000)
        perfLog("PERF_SYSTEM_PROMPT total_ms=\(totalMs) memory_ms=\(memoryMs) rag_ms=\(ragMs) workspace_ms=\(workspaceMs) memories=\(includedMemories.count) rag_results=\(ragResultCount) snippets=\(workspaceSnippetCount) prompt_chars=\(prompt.count)")

        return prompt
    }

    /// Returns memories that should be included based on the current config
    private func getIncludedMemories() -> [MemoryItem] {
        var included: [MemoryItem] = []

        for memory in allMemories {
            // Always include pinned memories
            if memory.isPinned {
                included.append(memory)
                continue
            }

            // Check if specifically selected
            if memoryContextConfig.specificMemoryIds.contains(memory.id) {
                included.append(memory)
                continue
            }

            // Check type-based inclusion
            let shouldIncludeByType: Bool
            if memoryContextConfig.includeAllMemories {
                shouldIncludeByType = true
            } else {
                switch memory.type {
                case .fact:
                    shouldIncludeByType = memoryContextConfig.includeFacts
                case .preference:
                    shouldIncludeByType = memoryContextConfig.includePreferences
                case .project:
                    shouldIncludeByType = memoryContextConfig.includeProjects
                case .instruction:
                    shouldIncludeByType = memoryContextConfig.includeInstructions
                case .reference:
                    shouldIncludeByType = memoryContextConfig.includeReferences
                }
            }

            if shouldIncludeByType {
                included.append(memory)
            }
        }

        return included
    }

    // MARK: - Message Actions

    private func retryMessage(_ message: Message) {
        guard message.role == .assistant else { return }

        // Create a sibling message instead of overwriting
        let modelToUse = AIModel(rawValue: message.modelUsed ?? selectedModel.rawValue) ?? selectedModel
        createSiblingAndRegenerate(for: message, withModel: modelToUse)
    }

    private func switchModel(for message: Message, to newModel: AIModel) {
        guard message.role == .assistant else { return }

        // Update the selected model
        selectedModel = newModel

        // Create a sibling message with the new model
        createSiblingAndRegenerate(for: message, withModel: newModel)
    }

    /// Creates a new sibling message and regenerates the response
    private func createSiblingAndRegenerate(for originalMessage: Message, withModel model: AIModel) {
        // Set up sibling group if not already set
        let groupId = originalMessage.siblingGroupId ?? originalMessage.id

        // If this is the first sibling creation, update the original message
        if originalMessage.siblingGroupId == nil {
            originalMessage.siblingGroupId = groupId
            originalMessage.siblingIndex = 0
        }

        // Find the highest sibling index in this group
        let siblings = conversation.messages.filter { $0.siblingGroupId == groupId }
        let maxIndex = siblings.map { $0.siblingIndex }.max() ?? 0

        // Mark the original message as inactive
        originalMessage.isActive = false

        // Create a new sibling message
        let newMessage = Message(
            role: .assistant,
            content: "",
            timestamp: originalMessage.timestamp, // Keep same timestamp for ordering
            modelUsed: model.rawValue
        )
        newMessage.siblingGroupId = groupId
        newMessage.siblingIndex = maxIndex + 1
        newMessage.isActive = true

        // Insert into context and conversation
        modelContext.insert(newMessage)
        newMessage.conversation = conversation
        conversation.messages.append(newMessage)

        // Refresh the display
        refreshSortedMessages()

        // Regenerate the response
        regenerateResponse(for: newMessage)
    }

    /// Get all siblings for a message (including itself)
    func getSiblings(for message: Message) -> [Message] {
        guard let groupId = message.siblingGroupId else {
            return [message]
        }
        return conversation.messages
            .filter { $0.siblingGroupId == groupId }
            .sorted { $0.siblingIndex < $1.siblingIndex }
    }

    /// Switch to a different sibling message
    func switchToSibling(_ targetMessage: Message) {
        guard let groupId = targetMessage.siblingGroupId else { return }

        // Deactivate all siblings in the group
        for sibling in conversation.messages where sibling.siblingGroupId == groupId {
            sibling.isActive = false
        }

        // Activate the target message
        targetMessage.isActive = true

        // Refresh the display
        refreshSortedMessages()
    }

    private func regenerateResponse(for assistantMessage: Message) {
        isLoading = true
        currentStreamingMessage = assistantMessage
        streamingContent = ""  // Reset streaming buffer

        // Prepare service
        let modelToUse = AIModel(rawValue: assistantMessage.modelUsed ?? selectedModel.rawValue) ?? selectedModel
        let service = apiServiceFactory.service(for: modelToUse)

        guard service.isConfigured else {
            isLoading = false
            errorMessage = "Please add your \(modelToUse.provider.displayName) API key in Settings (⌘,)"
            return
        }

        // Prepare messages up to (but not including) this assistant message
        let sortedMessages = conversation.messages.sorted(by: { $0.timestamp < $1.timestamp })
        guard let assistantIndex = sortedMessages.firstIndex(where: { $0.id == assistantMessage.id }) else {
            isLoading = false
            return
        }

        var chatMessages = sortedMessages[0..<assistantIndex]
            .map { ChatMessage(from: $0) }

        // Find the user message that triggered this response
        let userMessage = sortedMessages[0..<assistantIndex]
            .reversed()
            .first(where: { $0.role == .user })
        let userPrompt = userMessage?.content ?? ""

        Task {
            // Inject system prompt at the beginning if not present (async for RAG)
            if !chatMessages.contains(where: { $0.role == "system" }) {
                let systemPrompt = await getSystemPrompt(for: modelToUse.provider, userPrompt: userPrompt)
                chatMessages.insert(ChatMessage(role: .system, content: systemPrompt), at: 0)
            }

            do {
                var contentBuffer = ""
                var lastUIUpdateTime = Date()

                let stream = service.streamMessage(messages: Array(chatMessages), model: modelToUse)
                for try await chunk in stream {
                    contentBuffer += chunk
                    let now = Date()
                    if now.timeIntervalSince(lastUIUpdateTime) >= 0.05 {
                        lastUIUpdateTime = now
                        let bufferSnapshot = contentBuffer
                        await MainActor.run {
                            streamingContent = bufferSnapshot
                        }
                    }
                }

                let finalContent = contentBuffer
                await MainActor.run {
                    assistantMessage.content = finalContent
                    streamingContent = ""
                    conversation.updatedAt = Date()
                    isLoading = false
                    currentStreamingMessage = nil
                }

                // Background: Generate embeddings and summary for this exchange
                if let userMessage = userMessage {
                    await generateEmbeddingsAndSummary(
                        userMessage: userMessage,
                        assistantMessage: assistantMessage
                    )
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                    currentStreamingMessage = nil
                }
            }
        }
    }

    private func branchFromMessage(_ message: Message) {
        // Create a new conversation with messages up to and including this one
        let sortedMessages = conversation.messages.sorted(by: { $0.timestamp < $1.timestamp })
        guard let messageIndex = sortedMessages.firstIndex(where: { $0.id == message.id }) else { return }

        let newConversation = Conversation(title: "\(conversation.title) (branch)")

        // Insert conversation first
        modelContext.insert(newConversation)

        // Copy messages up to this point
        for i in 0...messageIndex {
            let originalMessage = sortedMessages[i]
            let copiedMessage = Message(
                role: originalMessage.role,
                content: originalMessage.content,
                timestamp: originalMessage.timestamp,
                modelUsed: originalMessage.modelUsed
            )

            // Insert message first
            modelContext.insert(copiedMessage)

            // Explicitly set the conversation relationship
            copiedMessage.conversation = newConversation

            // Copy attachments if any
            for attachment in originalMessage.attachments {
                let copiedAttachment = Attachment(
                    type: attachment.type,
                    mimeType: attachment.mimeType,
                    data: attachment.data,
                    filename: attachment.filename
                )
                modelContext.insert(copiedAttachment)
                copiedMessage.attachments.append(copiedAttachment)
            }

            newConversation.messages.append(copiedMessage)
        }

        // Notify parent to select the new conversation
        onBranchConversation?(newConversation)
    }

    // MARK: - Send Message

    private func sendMessage() {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !pendingAttachments.isEmpty
        guard hasText || hasAttachments else { return }

        // Create user message first (without attachments)
        let userMessage = Message(role: .user, content: inputText)

        // Insert message into context first so it becomes a managed object
        modelContext.insert(userMessage)

        // Explicitly set the conversation relationship
        userMessage.conversation = conversation

        // Then create and add attachments
        for pendingAttachment in pendingAttachments {
            let attachment = pendingAttachment.toAttachment()
            modelContext.insert(attachment)
            userMessage.attachments.append(attachment)
        }

        // Now append to conversation
        conversation.messages.append(userMessage)
        conversation.updatedAt = Date()

        // Capture user content for async use
        let userContent = inputText

        // Reset input state
        inputText = ""
        pendingAttachments = []
        errorMessage = nil
        isLoading = true

        // Prepare service
        let service = apiServiceFactory.service(for: selectedModel)
        guard service.isConfigured else {
            isLoading = false
            errorMessage = "Please add your \(selectedModel.provider.displayName) API key in Settings (⌘,)"
            return
        }

        // Create assistant message for streaming
        let assistantMessage = Message(
            role: .assistant,
            content: "",
            modelUsed: selectedModel.rawValue
        )

        // Insert into context first
        modelContext.insert(assistantMessage)

        // Explicitly set the conversation relationship
        assistantMessage.conversation = conversation

        conversation.messages.append(assistantMessage)
        currentStreamingMessage = assistantMessage

        // Capture model for async use
        let modelToUse = selectedModel

        Task {
            let taskStartedAt = Date()

            // Prepare messages for API (inside Task to use async getSystemPrompt)
            var chatMessages = conversation.messages
                .sorted(by: { $0.timestamp < $1.timestamp })
                .filter { $0.id != assistantMessage.id } // Exclude the empty assistant message we just created
                .map { ChatMessage(from: $0) }

            let messagesBuiltAt = Date()
            let messagesBuildMs = Int(messagesBuiltAt.timeIntervalSince(taskStartedAt) * 1000)

            // Inject system prompt at the beginning if not present (async for RAG)
            if !chatMessages.contains(where: { $0.role == "system" }) {
                let systemPrompt = await getSystemPrompt(for: modelToUse.provider, userPrompt: userContent)
                chatMessages.insert(ChatMessage(role: .system, content: systemPrompt), at: 0)
            }

            let systemPromptBuiltAt = Date()
            let systemPromptMs = Int(systemPromptBuiltAt.timeIntervalSince(messagesBuiltAt) * 1000)

            // Calculate total payload size
            let totalChars = chatMessages.reduce(0) { $0 + ($1.textContent?.count ?? 0) }
            let systemPromptChars = chatMessages.first(where: { $0.role == "system" })?.textContent?.count ?? 0

            do {
                let streamID = assistantMessage.id
                let streamStartedAt = Date()
                var firstTokenAt: Date?
                var chunkCount = 0
                var chunkBytes = 0

                await MainActor.run {
                    activeStreamID = streamID
                    activeStreamScrollEvents = 0
                    activeStreamUIUpdates = 0
                    streamingContent = ""  // Reset streaming buffer
                    perfLog("PERF_PREP messages_build_ms=\(messagesBuildMs) system_prompt_ms=\(systemPromptMs) system_prompt_chars=\(systemPromptChars) total_payload_chars=\(totalChars) message_count=\(chatMessages.count)")
                    perfLog("PERF_STREAM_START id=\(streamID.uuidString) model=\(modelToUse.rawValue) prompt_chars=\(userContent.count)")
                }

                let stream = service.streamMessage(messages: chatMessages, model: modelToUse)
                var lastChunkTime = Date()
                var slowChunks = 0
                var maxChunkMs = 0
                var contentBuffer = ""  // Local buffer for chunks - NO SwiftData updates during streaming!
                var lastUIUpdateTime = Date()

                for try await chunk in stream {
                    let chunkReceivedAt = Date()
                    let chunkIntervalMs = Int(chunkReceivedAt.timeIntervalSince(lastChunkTime) * 1000)
                    maxChunkMs = max(maxChunkMs, chunkIntervalMs)

                    if chunkIntervalMs > 500 {
                        slowChunks += 1
                        perfLog("PERF_SLOW_CHUNK chunk=\(chunkCount) interval_ms=\(chunkIntervalMs) bytes=\(chunk.utf8.count)")
                    }

                    lastChunkTime = chunkReceivedAt

                    if firstTokenAt == nil {
                        firstTokenAt = Date()
                    }
                    chunkCount += 1
                    chunkBytes += chunk.utf8.count
                    contentBuffer += chunk

                    // Throttle UI updates to every 50ms instead of per-chunk
                    // This dramatically reduces MainActor hops and SwiftUI re-renders
                    let timeSinceLastUpdate = chunkReceivedAt.timeIntervalSince(lastUIUpdateTime)
                    if timeSinceLastUpdate >= 0.05 {
                        lastUIUpdateTime = chunkReceivedAt
                        let bufferSnapshot = contentBuffer
                        await MainActor.run {
                            streamingContent = bufferSnapshot  // Update @State, NOT SwiftData
                            if activeStreamID == streamID {
                                activeStreamUIUpdates += 1
                            }
                        }
                    }
                }

                // Final update with complete content
                let finalContent = contentBuffer
                await MainActor.run {
                    let totalMs = Int(Date().timeIntervalSince(streamStartedAt) * 1000)
                    let firstTokenMs = firstTokenAt.map { Int($0.timeIntervalSince(streamStartedAt) * 1000) } ?? -1
                    let uiUpdates = activeStreamID == streamID ? activeStreamUIUpdates : 0
                    let scrollEvents = activeStreamID == streamID ? activeStreamScrollEvents : 0
                    perfLog(
                        "PERF_STREAM_END id=\(streamID.uuidString) total_ms=\(totalMs) first_token_ms=\(firstTokenMs) " +
                        "chunks=\(chunkCount) chunk_bytes=\(chunkBytes) final_chars=\(finalContent.count) " +
                        "ui_updates=\(uiUpdates) scroll_events=\(scrollEvents) slow_chunks=\(slowChunks) max_chunk_ms=\(maxChunkMs)"
                    )

                    // NOW update SwiftData - only once at the end!
                    assistantMessage.content = finalContent
                    streamingContent = ""

                    if activeStreamID == streamID {
                        activeStreamID = nil
                        activeStreamScrollEvents = 0
                        activeStreamUIUpdates = 0
                    }

                    conversation.updatedAt = Date()
                    isLoading = false
                    currentStreamingMessage = nil
                    // Trigger title generation from full context (user + assistant)
                    conversation.generateTitleFromContextAsync()
                }

                // Background: Generate embeddings and summary for this exchange
                await generateEmbeddingsAndSummary(
                    userMessage: userMessage,
                    assistantMessage: assistantMessage
                )
            } catch {
                await MainActor.run {
                    if let streamID = activeStreamID {
                        perfLog("PERF_STREAM_ERROR id=\(streamID.uuidString) error=\(error.localizedDescription)")
                    }

                    activeStreamID = nil
                    activeStreamScrollEvents = 0
                    activeStreamUIUpdates = 0

                    // Remove the empty assistant message on error
                    if assistantMessage.content.isEmpty,
                       let index = conversation.messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                        conversation.messages.remove(at: index)
                    }

                    errorMessage = error.localizedDescription
                    isLoading = false
                    currentStreamingMessage = nil
                }
            }
        }
    }

    private var isPerfLoggingEnabled: Bool {
        #if DEBUG
        true
        #else
        ProcessInfo.processInfo.environment["OMNICHAT_PERF_LOGS"] == "1" ||
        UserDefaults.standard.bool(forKey: "omnichat_perf_logs")
        #endif
    }

    private func perfLog(_ message: String) {
        guard isPerfLoggingEnabled else { return }
        print(message)
    }

    // MARK: - RAG Background Processing

    /// Generate embeddings and summary for a user-assistant message exchange in the background
    private func generateEmbeddingsAndSummary(userMessage: Message, assistantMessage: Message) async {
        // Skip if OpenAI API key is not configured
        guard EmbeddingService.shared.isConfigured else {
            logger.debug("RAG: Skipping embedding generation - OpenAI API key not configured")
            return
        }

        // Skip if assistant message is empty (failed response)
        guard !assistantMessage.content.isEmpty else {
            return
        }

        logger.debug("RAG: Starting background embedding and summary generation")

        // Capture message content and state BEFORE going to background
        // (SwiftData objects must not be accessed from detached tasks)
        let userContent = userMessage.content
        let assistantContent = assistantMessage.content
        let userNeedsEmbedding = !userContent.isEmpty && userMessage.embeddingVector == nil
        let assistantNeedsEmbedding = assistantMessage.embeddingVector == nil
        let needsSummary = userMessage.summary == nil || assistantMessage.summary == nil

        // Run API calls in background task
        Task(priority: .background) {
            // 1. Generate embedding for user message
            if userNeedsEmbedding {
                do {
                    let embedding = try await EmbeddingService.shared.generateEmbedding(for: userContent)
                    await MainActor.run {
                        userMessage.embeddingVector = embedding
                        userMessage.embeddedAt = Date()
                    }
                    logger.debug("RAG: Generated embedding for user message")
                } catch {
                    logger.warning("RAG: Failed to generate user message embedding: \(error.localizedDescription)")
                }
            }

            // 2. Generate embedding for assistant message
            if assistantNeedsEmbedding {
                do {
                    let embedding = try await EmbeddingService.shared.generateEmbedding(for: assistantContent)
                    await MainActor.run {
                        assistantMessage.embeddingVector = embedding
                        assistantMessage.embeddedAt = Date()
                    }
                    logger.debug("RAG: Generated embedding for assistant message")
                } catch {
                    logger.warning("RAG: Failed to generate assistant message embedding: \(error.localizedDescription)")
                }
            }

            // 3. Generate summary for the exchange (store on both messages)
            if needsSummary {
                do {
                    let summary = try await SummaryService.shared.generateSummary(
                        userMessage: userContent,
                        assistantMessage: assistantContent
                    )
                    await MainActor.run {
                        userMessage.summary = summary
                        assistantMessage.summary = summary
                    }
                    logger.debug("RAG: Generated summary for exchange: \(summary)")
                } catch {
                    logger.warning("RAG: Failed to generate summary: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Chat Header View

struct ChatHeaderView: View {
    @Bindable var conversation: Conversation
    let workspaces: [Workspace]
    @Binding var selectedModel: AIModel
    @Binding var showMemoryPanel: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Title on the left
            HStack(spacing: 8) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)

                if conversation.isTitleGenerating {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            Spacer()

            // Workspace selector
            WorkspacePicker(
                selectedWorkspace: $conversation.workspace,
                workspaces: workspaces
            )

            // Model selector
            ModelSelectorView(selectedModel: $selectedModel)

            // Memory panel toggle
            Button(action: { showMemoryPanel.toggle() }) {
                Image(systemName: showMemoryPanel ? "brain.fill" : "brain")
                    .foregroundColor(showMemoryPanel ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(showMemoryPanel ? "Hide memory panel" : "Show memory panel")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Workspace Picker

struct WorkspacePicker: View {
    @Binding var selectedWorkspace: Workspace?
    let workspaces: [Workspace]

    var body: some View {
        Menu {
            Button("None") {
                selectedWorkspace = nil
            }

            if !workspaces.isEmpty {
                Divider()

                ForEach(workspaces) { workspace in
                    Button(action: {
                        selectedWorkspace = workspace
                    }) {
                        HStack {
                            Text(workspace.name)
                            if selectedWorkspace?.id == workspace.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selectedWorkspace == nil ? "folder" : "folder.fill")
                    .foregroundColor(selectedWorkspace == nil ? .secondary : .accentColor)
                if let workspace = selectedWorkspace {
                    Text(workspace.name)
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    Text("No workspace")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .help("Select workspace for file access")
    }
}
