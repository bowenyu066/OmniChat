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
        }
        .onChange(of: memoryContextConfig) { _, newConfig in
            // Save memory config to conversation
            conversation.memoryContextConfig = newConfig
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            // Header with title, model selector, and workspace selector
            ChatHeaderView(
                conversation: conversation,
                workspaces: allWorkspaces,
                selectedModel: $selectedModel,
                showMemoryPanel: $showMemoryPanel
            )

            Divider()

            // Messages list with input area as safeAreaInset
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(conversation.messages.sorted(by: { $0.timestamp < $1.timestamp })) { message in
                            MessageView(
                                message: message,
                                onRetry: message.role == .assistant ? { retryMessage(message) } : nil,
                                onSwitchModel: message.role == .assistant ? { newModel in switchModel(for: message, to: newModel) } : nil,
                                onBranch: message.role == .assistant ? { branchFromMessage(message) } : nil
                            )
                            .id(message.id)
                        }

                        if isLoading {
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
                    }
                    .padding(.vertical)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: conversation.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: currentStreamingMessage?.content) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        // Error banner
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

                        Divider()

                        // Input area
                        MessageInputView(
                            text: $inputText,
                            pendingAttachments: $pendingAttachments,
                            isLoading: isLoading,
                            onSend: sendMessage
                        )
                        .padding()
                        .background(.bar)
                    }
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = conversation.messages.sorted(by: { $0.timestamp < $1.timestamp }).last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        } else if isLoading {
            withAnimation {
                proxy.scrollTo("loading", anchor: .bottom)
            }
        }
    }

    private func getSystemPrompt(for provider: AIProvider, userPrompt: String = "") async -> String {
        var prompt = """
        You are a helpful AI assistant. Keep responses clear and concise.
        """

        // Layer 1: Include memories based on config (highest priority)
        let includedMemories = getIncludedMemories()
        if !includedMemories.isEmpty {
            prompt += "\n\n## User Memory\nThe following information has been provided by the user as context. Use this knowledge when relevant:\n"

            for memory in includedMemories {
                prompt += "\n### \(memory.type.rawValue): \(memory.title)\n\(memory.body)\n"
            }
        }

        // Layer 2: RAG - Past Conversations (semantic search across all conversations)
        if !userPrompt.isEmpty {
            do {
                let ragResults = try await RAGService.shared.retrieveRelevantContext(
                    for: userPrompt,
                    excludeConversation: conversation,
                    modelContext: modelContext,
                    limit: 5
                )

                if !ragResults.isEmpty {
                    prompt += "\n\n" + RAGService.formatResultsForPrompt(ragResults)
                    logger.debug("RAG: Added \(ragResults.count) relevant past conversations to context")
                }
            } catch {
                logger.warning("RAG retrieval failed: \(error.localizedDescription)")
                // Continue without RAG results - graceful degradation
            }
        }

        // Layer 3: Include workspace files if workspace is selected
        if let workspace = conversation.workspace, !userPrompt.isEmpty {
            let fileSnippets = FileRetriever.shared.retrieveSnippets(
                for: userPrompt,
                workspace: workspace,
                limit: 5
            )

            if !fileSnippets.isEmpty {
                prompt += "\n\n## Workspace Files\nThe following code snippets from the workspace may be relevant. Always cite files when referencing them:\n"

                for snippet in fileSnippets {
                    prompt += "\n### \(snippet.citation)\n```\n\(snippet.content)\n```\n"
                }

                prompt += "\nWhen referencing these files, always use the format `file.swift:line` for clarity.\n"
            }
        }

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

        // Find the user message that triggered this response
        let sortedMessages = conversation.messages.sorted(by: { $0.timestamp < $1.timestamp })
        guard let messageIndex = sortedMessages.firstIndex(where: { $0.id == message.id }),
              messageIndex > 0 else { return }

        // Clear the assistant message content and regenerate
        message.content = ""
        regenerateResponse(for: message)
    }

    private func switchModel(for message: Message, to newModel: AIModel) {
        guard message.role == .assistant else { return }

        // Update the model and regenerate
        message.content = ""
        message.modelUsed = newModel.rawValue
        selectedModel = newModel
        regenerateResponse(for: message)
    }

    private func regenerateResponse(for assistantMessage: Message) {
        isLoading = true
        currentStreamingMessage = assistantMessage

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
                let stream = service.streamMessage(messages: Array(chatMessages), model: modelToUse)
                for try await chunk in stream {
                    await MainActor.run {
                        assistantMessage.content += chunk
                    }
                }

                await MainActor.run {
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
            // Prepare messages for API (inside Task to use async getSystemPrompt)
            var chatMessages = conversation.messages
                .sorted(by: { $0.timestamp < $1.timestamp })
                .filter { $0.id != assistantMessage.id } // Exclude the empty assistant message we just created
                .map { ChatMessage(from: $0) }

            // Inject system prompt at the beginning if not present (async for RAG)
            if !chatMessages.contains(where: { $0.role == "system" }) {
                let systemPrompt = await getSystemPrompt(for: modelToUse.provider, userPrompt: userContent)
                chatMessages.insert(ChatMessage(role: .system, content: systemPrompt), at: 0)
            }

            do {
                let stream = service.streamMessage(messages: chatMessages, model: modelToUse)
                for try await chunk in stream {
                    await MainActor.run {
                        assistantMessage.content += chunk
                    }
                }

                await MainActor.run {
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
