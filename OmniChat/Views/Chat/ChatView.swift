import SwiftUI
import SwiftData

struct ChatView: View {
    @Bindable var conversation: Conversation
    @Binding var selectedModel: AIModel

    @Environment(\.modelContext) private var modelContext
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
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            // Header with title and model selector
            ChatHeaderView(
                title: conversation.title,
                isTitleGenerating: conversation.isTitleGenerating,
                selectedModel: $selectedModel,
                showMemoryPanel: $showMemoryPanel
            )

            Divider()

            // Messages list
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
                .onChange(of: conversation.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: currentStreamingMessage?.content) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

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

    private func getSystemPrompt(for provider: AIProvider) -> String {
        return """
        You are a helpful AI assistant. Keep responses clear and concise.
        """
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

        // Inject system prompt at the beginning if not present
        if !chatMessages.contains(where: { $0.role == "system" }) {
            let systemPrompt = getSystemPrompt(for: modelToUse.provider)
            chatMessages.insert(ChatMessage(role: .system, content: systemPrompt), at: 0)
        }

        Task {
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

        // Copy messages up to this point
        for i in 0...messageIndex {
            let originalMessage = sortedMessages[i]
            let copiedMessage = Message(
                role: originalMessage.role,
                content: originalMessage.content,
                timestamp: originalMessage.timestamp,
                modelUsed: originalMessage.modelUsed
            )
            // Copy attachments if any
            for attachment in originalMessage.attachments {
                let copiedAttachment = Attachment(
                    type: attachment.type,
                    mimeType: attachment.mimeType,
                    data: attachment.data,
                    filename: attachment.filename
                )
                copiedMessage.attachments.append(copiedAttachment)
            }
            newConversation.messages.append(copiedMessage)
        }

        modelContext.insert(newConversation)

        // Notify parent to select the new conversation
        onBranchConversation?(newConversation)
    }

    // MARK: - Send Message

    private func sendMessage() {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !pendingAttachments.isEmpty
        guard hasText || hasAttachments else { return }

        // Convert pending attachments to Attachment models and build the user message
        let attachments = pendingAttachments.map { $0.toAttachment() }
        let userMessage = Message(role: .user, content: inputText, attachments: attachments)
        conversation.messages.append(userMessage)
        conversation.updatedAt = Date()

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

        // Prepare messages for API
        var chatMessages = conversation.messages
            .sorted(by: { $0.timestamp < $1.timestamp })
            .map { ChatMessage(from: $0) }

        // Inject system prompt at the beginning if not present
        if !chatMessages.contains(where: { $0.role == "system" }) {
            let systemPrompt = getSystemPrompt(for: selectedModel.provider)
            chatMessages.insert(ChatMessage(role: .system, content: systemPrompt), at: 0)
        }

        // Create assistant message for streaming
        let assistantMessage = Message(
            role: .assistant,
            content: "",
            modelUsed: selectedModel.rawValue
        )
        conversation.messages.append(assistantMessage)
        currentStreamingMessage = assistantMessage

        Task {
            do {
                let stream = service.streamMessage(messages: chatMessages, model: selectedModel)
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
}

// MARK: - Chat Header View

struct ChatHeaderView: View {
    let title: String
    let isTitleGenerating: Bool
    @Binding var selectedModel: AIModel
    @Binding var showMemoryPanel: Bool

    var body: some View {
        HStack {
            // Title on the left
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                if isTitleGenerating {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            Spacer()

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
