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
    @State private var loadingStartTime: Date?
    @State private var loadingElapsedSeconds: Int = 0
    @State private var loadingTimer: Timer?
    @State private var thinkingDurations: [UUID: TimeInterval] = [:]  // messageId -> seconds
    @AppStorage("include_time_context") private var includeTimeContext = true
    @State private var currentStreamingMessage: Message?
    @State private var showMemoryPanel = true
    @State private var memoryContextConfig = MemoryContextConfig()
    @State private var sortedMessagesCache: [Message] = []
    @State private var activeStreamID: UUID?
    @State private var activeStreamScrollEvents = 0
    @State private var activeStreamUIUpdates = 0
    @State private var expandedContextMessageID: UUID?

    // Streaming content buffer - avoids SwiftData updates during streaming
    // This is updated frequently, while SwiftData is only updated when streaming completes
    @State private var streamingContent: String = ""

    // Throttle scroll updates to reduce re-renders during streaming
    @State private var lastScrollUpdate = Date.distantPast

    var onBranchConversation: ((Conversation) -> Void)?

    private struct SystemPromptBuildResult {
        let prompt: String
        let contextSnapshot: ResponseContextSnapshot
    }

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
                    thinkingDuration: thinkingDurations[message.id],
                    onRetry: message.role == .assistant ? { retryMessage(message) } : nil,
                    onSwitchModel: message.role == .assistant ? { newModel in switchModel(for: message, to: newModel) } : nil,
                    onBranch: message.role == .assistant ? { branchFromMessage(message) } : nil,
                    onSwitchSibling: siblings.count > 1 ? { sibling in switchToSibling(sibling) } : nil,
                    onEdit: message.role == .user ? { newContent in editUserMessage(message, newContent: newContent) } : nil,
                    isContextInspectorVisible: expandedContextMessageID == message.id,
                    onShowContextInspector: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedContextMessageID = message.id
                        }
                    },
                    onCloseContextInspector: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedContextMessageID == message.id {
                                expandedContextMessageID = nil
                            }
                        }
                    }
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
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.9)
            Text(loadingElapsedSeconds > 0 ? "Thinking for \(loadingElapsedSeconds)s..." : "Thinking...")
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.7))
                .monospacedDigit()
                .contentTransition(.numericText())
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
        // Build the visible message chain by following the active path
        // A message is visible if:
        // 1. It has no precedingMessageId (root message), OR
        // 2. Its precedingMessageId is in the visible set
        // AND it's active (for siblings, only show the active one)

        let allMessages = conversation.messages
        var visibleIds = Set<UUID>()
        var result: [Message] = []

        // Sort by timestamp first
        let sorted = allMessages.sorted { $0.timestamp < $1.timestamp }

        for message in sorted {
            // Skip inactive siblings
            guard message.isActive else { continue }

            // Check if this message should be visible
            let shouldShow: Bool
            if message.precedingMessageId == nil {
                // Root message (first user message) - always show
                shouldShow = true
            } else if let precedingId = message.precedingMessageId {
                // Only show if the preceding message is visible
                shouldShow = visibleIds.contains(precedingId)
            } else {
                shouldShow = false
            }

            if shouldShow {
                visibleIds.insert(message.id)
                result.append(message)
            }
        }

        sortedMessagesCache = result
    }

    private func getSystemPrompt(for provider: AIProvider, userPrompt: String = "") async -> SystemPromptBuildResult {
        let startTime = Date()

        var prompt = """
        You are a helpful AI assistant. Keep responses clear and concise.
        """

        var contextMemoryItems: [ResponseContextMemoryItem] = []
        var contextRAGItems: [ResponseContextRAGItem] = []
        var contextWorkspaceItems: [ResponseContextWorkspaceItem] = []

        // Inject current date/time if enabled
        if includeTimeContext {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .short
            let timeString = formatter.string(from: Date())
            prompt += "\n\nCurrent date and time: \(timeString)"
        }

        // Layer 1: Include memories based on config (highest priority)
        let memoryStartTime = Date()
        let includedMemories = getIncludedMemories()
        if !includedMemories.isEmpty {
            prompt += "\n\n## User Memory\nThe following information has been provided by the user as context. Use this knowledge when relevant:\n"

            for memory in includedMemories {
                prompt += "\n### \(memory.type.rawValue): \(memory.title)\n\(memory.body)\n"
                contextMemoryItems.append(
                    ResponseContextMemoryItem(
                        id: memory.id,
                        type: memory.type.rawValue,
                        title: memory.title
                    )
                )
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

                    contextRAGItems = ragResults.map { result in
                        ResponseContextRAGItem(
                            conversationTitle: result.conversationTitle,
                            summary: result.summary,
                            similarity: result.similarity
                        )
                    }
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
                    contextWorkspaceItems.append(
                        ResponseContextWorkspaceItem(
                            citation: snippet.citation,
                            reason: snippet.reason
                        )
                    )
                }

                prompt += "\nWhen referencing these files, always use the format `file.swift:line` for clarity.\n"
            }
        }
        let workspaceMs = Int(Date().timeIntervalSince(workspaceStartTime) * 1000)

        let totalMs = Int(Date().timeIntervalSince(startTime) * 1000)
        perfLog("PERF_SYSTEM_PROMPT total_ms=\(totalMs) memory_ms=\(memoryMs) rag_ms=\(ragMs) workspace_ms=\(workspaceMs) memories=\(includedMemories.count) rag_results=\(ragResultCount) snippets=\(workspaceSnippetCount) prompt_chars=\(prompt.count)")

        let snapshot = ResponseContextSnapshot(
            generatedAt: Date(),
            includesTimeContext: includeTimeContext,
            memoryItems: contextMemoryItems,
            ragItems: contextRAGItems,
            workspaceItems: contextWorkspaceItems
        )

        return SystemPromptBuildResult(prompt: prompt, contextSnapshot: snapshot)
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

    /// Edit a user message - creates a sibling branch with new content and regenerates
    private func editUserMessage(_ message: Message, newContent: String) {
        guard message.role == .user else { return }

        // Set up sibling group if not already set
        let groupId = message.siblingGroupId ?? message.id
        if message.siblingGroupId == nil {
            message.siblingGroupId = groupId
            message.siblingIndex = 0
        }

        // Find highest sibling index
        let siblings = conversation.messages.filter { $0.siblingGroupId == groupId }
        let maxIndex = siblings.map { $0.siblingIndex }.max() ?? 0

        // Mark original as inactive
        message.isActive = false

        // Create new user message sibling
        let newUserMessage = Message(
            role: .user,
            content: newContent,
            timestamp: message.timestamp
        )
        newUserMessage.siblingGroupId = groupId
        newUserMessage.siblingIndex = maxIndex + 1
        newUserMessage.isActive = true
        newUserMessage.precedingMessageId = message.precedingMessageId

        // Copy attachments if any
        for attachment in message.attachments {
            let newAttachment = Attachment(
                type: attachment.type,
                mimeType: attachment.mimeType,
                data: attachment.data,
                filename: attachment.filename
            )
            modelContext.insert(newAttachment)
            newUserMessage.attachments.append(newAttachment)
        }

        modelContext.insert(newUserMessage)
        newUserMessage.conversation = conversation
        conversation.messages.append(newUserMessage)

        // Refresh display
        refreshSortedMessages()

        // Now generate a response for the edited message
        generateResponseForEditedMessage(userMessage: newUserMessage)
    }

    /// Generate a response for an edited user message
    private func generateResponseForEditedMessage(userMessage: Message) {
        errorMessage = nil
        startLoading()

        let service = apiServiceFactory.service(for: selectedModel)
        guard service.isConfigured else {
            stopLoading()
            errorMessage = "Please add your \(selectedModel.provider.displayName) API key in Settings (⌘,)"
            return
        }

        // Create assistant message
        let assistantMessage = Message(
            role: .assistant,
            content: "",
            modelUsed: selectedModel.rawValue
        )
        assistantMessage.precedingMessageId = userMessage.id

        modelContext.insert(assistantMessage)
        assistantMessage.conversation = conversation
        conversation.messages.append(assistantMessage)
        currentStreamingMessage = assistantMessage
        refreshSortedMessages()

        let modelToUse = selectedModel
        let visibleContext = sortedMessagesCache

        Task {
            var chatMessages = visibleContext
                .filter { $0.id != assistantMessage.id }
                .map { ChatMessage(from: $0) }

            if !chatMessages.contains(where: { $0.role == "system" }) {
                let promptBuild = await getSystemPrompt(for: modelToUse.provider, userPrompt: userMessage.content)
                assistantMessage.contextSnapshot = promptBuild.contextSnapshot
                chatMessages.insert(ChatMessage(role: .system, content: promptBuild.prompt), at: 0)
            }

            let stream = service.streamMessage(messages: chatMessages, model: modelToUse)
            var contentBuffer = ""
            var firstTokenAt: Date?

            do {
                for try await chunk in stream {
                    if firstTokenAt == nil {
                        firstTokenAt = Date()
                        let thinkingSeconds = loadingStartTime.map { Date().timeIntervalSince($0) } ?? 0
                        await MainActor.run {
                            stopLoading()
                            thinkingDurations[assistantMessage.id] = thinkingSeconds
                        }
                    }
                    contentBuffer += chunk
                    await MainActor.run {
                        streamingContent = contentBuffer
                    }
                }

                await MainActor.run {
                    assistantMessage.content = contentBuffer
                    streamingContent = ""
                    currentStreamingMessage = nil
                    refreshSortedMessages()
                    conversation.updatedAt = Date()
                }
            } catch {
                await MainActor.run {
                    if assistantMessage.content.isEmpty {
                        assistantMessage.content = "⚠️ Error: \(error.localizedDescription)"
                    }
                    errorMessage = error.localizedDescription
                    stopLoading()
                    currentStreamingMessage = nil
                    refreshSortedMessages()
                }
            }
        }
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
        // Sibling follows the same message as the original
        newMessage.precedingMessageId = originalMessage.precedingMessageId

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

    /// Build the visible message chain leading up to (but not including) a target message
    /// This respects the branch structure by following precedingMessageId links
    private func buildVisibleContextUpTo(_ targetMessage: Message) -> [Message] {
        // We need to find all messages that lead to the target message's precedingMessageId
        guard let targetPrecedingId = targetMessage.precedingMessageId else {
            // Target has no preceding message - return empty context
            return []
        }

        // Build backwards from the preceding message
        var result: [Message] = []
        var currentId: UUID? = targetPrecedingId

        while let id = currentId {
            guard let message = conversation.messages.first(where: { $0.id == id }) else {
                break
            }
            result.insert(message, at: 0)
            currentId = message.precedingMessageId
        }

        return result
    }

    private func regenerateResponse(for assistantMessage: Message) {
        startLoading()
        currentStreamingMessage = assistantMessage
        streamingContent = ""  // Reset streaming buffer

        // Prepare service
        let modelToUse = AIModel(rawValue: assistantMessage.modelUsed ?? selectedModel.rawValue) ?? selectedModel
        let service = apiServiceFactory.service(for: modelToUse)

        guard service.isConfigured else {
            stopLoading()
            errorMessage = "Please add your \(modelToUse.provider.displayName) API key in Settings (⌘,)"
            return
        }

        // Build the visible message chain up to (but not including) this assistant message
        // This ensures we use the correct branch context
        let visibleContext = buildVisibleContextUpTo(assistantMessage)

        var chatMessages = visibleContext.map { ChatMessage(from: $0) }

        // Find the user message that triggered this response (should be the last in context)
        let userMessage = visibleContext.last(where: { $0.role == .user })
        let userPrompt = userMessage?.content ?? ""

        Task {
            // Inject system prompt at the beginning if not present (async for RAG)
            if !chatMessages.contains(where: { $0.role == "system" }) {
                let promptBuild = await getSystemPrompt(for: modelToUse.provider, userPrompt: userPrompt)
                assistantMessage.contextSnapshot = promptBuild.contextSnapshot
                chatMessages.insert(ChatMessage(role: .system, content: promptBuild.prompt), at: 0)
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
                    stopLoading()
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
                    stopLoading()
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
            copiedMessage.contextSnapshotData = originalMessage.contextSnapshotData

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

        // Find the last visible message to set as precedingMessageId
        let lastVisibleMessage = sortedMessagesCache.last

        // Create user message first (without attachments)
        let userMessage = Message(role: .user, content: inputText)

        // Set the preceding message (the last assistant message in the visible chain)
        userMessage.precedingMessageId = lastVisibleMessage?.id

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
        startLoading()

        // Prepare service
        let service = apiServiceFactory.service(for: selectedModel)
        guard service.isConfigured else {
            stopLoading()
            errorMessage = "Please add your \(selectedModel.provider.displayName) API key in Settings (⌘,)"
            return
        }

        // Create assistant message for streaming
        let assistantMessage = Message(
            role: .assistant,
            content: "",
            modelUsed: selectedModel.rawValue
        )

        // Set the preceding message (the user message this is responding to)
        assistantMessage.precedingMessageId = userMessage.id

        // Insert into context first
        modelContext.insert(assistantMessage)

        // Explicitly set the conversation relationship
        assistantMessage.conversation = conversation

        conversation.messages.append(assistantMessage)
        currentStreamingMessage = assistantMessage

        // Refresh to include the new messages
        refreshSortedMessages()

        // Capture model for async use
        let modelToUse = selectedModel

        // Capture the visible context before starting async work
        // This is the sortedMessagesCache which already respects branch visibility
        let visibleContext = sortedMessagesCache

        Task {
            let taskStartedAt = Date()

            // Prepare messages for API using the visible context (respects branches)
            // The visibleContext already includes the new user message since we refreshed
            var chatMessages = visibleContext
                .filter { $0.id != assistantMessage.id } // Exclude the empty assistant message
                .map { ChatMessage(from: $0) }

            let messagesBuiltAt = Date()
            let messagesBuildMs = Int(messagesBuiltAt.timeIntervalSince(taskStartedAt) * 1000)

            // Inject system prompt at the beginning if not present (async for RAG)
            if !chatMessages.contains(where: { $0.role == "system" }) {
                let promptBuild = await getSystemPrompt(for: modelToUse.provider, userPrompt: userContent)
                assistantMessage.contextSnapshot = promptBuild.contextSnapshot
                chatMessages.insert(ChatMessage(role: .system, content: promptBuild.prompt), at: 0)
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
                        // Stop the loading spinner and record thinking duration
                        let thinkingSeconds = loadingStartTime.map { Date().timeIntervalSince($0) } ?? 0
                        await MainActor.run {
                            stopLoading()
                            thinkingDurations[assistantMessage.id] = thinkingSeconds
                        }
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
                    stopLoading()
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

                    // Keep the message but set error content so retry buttons are visible
                    if assistantMessage.content.isEmpty {
                        assistantMessage.content = "⚠️ Error: \(error.localizedDescription)"
                    }

                    errorMessage = error.localizedDescription
                    stopLoading()
                    currentStreamingMessage = nil
                    refreshSortedMessages()
                }
            }
        }
    }

    // MARK: - Loading Timer Management

    private func startLoading() {
        isLoading = true
        loadingStartTime = Date()
        loadingElapsedSeconds = 0

        // Start timer to update elapsed seconds
        loadingTimer?.invalidate()
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let startTime = loadingStartTime {
                loadingElapsedSeconds = Int(Date().timeIntervalSince(startTime))
            }
        }
    }

    private func stopLoading() {
        isLoading = false
        loadingTimer?.invalidate()
        loadingTimer = nil
        loadingStartTime = nil
        loadingElapsedSeconds = 0
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

            // Reasoning effort (only for GPT-5 family, excluding mini/nano)
            if selectedModel.supportsReasoningEffort {
                OpenAIReasoningEffortPicker(model: selectedModel)
            }

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

// MARK: - OpenAI Reasoning Effort Picker

private struct OpenAIReasoningEffortPicker: View {
    let model: AIModel
    @AppStorage("openai_reasoning_effort") private var selectedEffortRaw = OpenAIReasoningEffort.auto.rawValue

    private var selectedEffort: OpenAIReasoningEffort {
        OpenAIReasoningEffort(rawValue: selectedEffortRaw) ?? .auto
    }

    private var availableEfforts: [OpenAIReasoningEffort] {
        if model.supportsXHighReasoningEffort {
            return [.auto, .none, .low, .medium, .high, .xhigh]
        }
        return [.auto, .none, .low, .medium, .high]
    }

    private var shortLabel: String {
        switch selectedEffort {
        case .auto: return "Auto"
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "xHigh"
        }
    }

    var body: some View {
        Menu {
            ForEach(availableEfforts) { effort in
                Button {
                    selectedEffortRaw = effort.rawValue
                } label: {
                    HStack {
                        Text(effort.displayName)
                        Spacer()
                        if effort == selectedEffort {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(shortLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .help("Reasoning effort for GPT-5 models")
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
