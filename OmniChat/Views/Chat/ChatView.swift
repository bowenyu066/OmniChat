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

    private let apiServiceFactory = APIServiceFactory()

    var body: some View {
        VStack(spacing: 0) {
            // Model selector header
            ModelSelectorView(selectedModel: $selectedModel)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)

            Divider()

            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(conversation.messages.sorted(by: { $0.timestamp < $1.timestamp })) { message in
                            MessageView(message: message)
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
        .navigationTitle(conversation.title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if conversation.isTitleGenerating {
                    ProgressView()
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

    private func getSystemPrompt(for provider: AIProvider) -> String {
        return """
        You are a helpful AI assistant. Keep responses clear and concise.
        """
    }

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

