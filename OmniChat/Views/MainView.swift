import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var selectedConversation: Conversation?
    @State private var selectedModel: AIModel = .gpt5_2
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                conversations: conversations,
                selectedConversation: $selectedConversation,
                onNewChat: createNewConversation,
                onDelete: deleteConversation,
                onOpenMemoryPanel: { openWindow(id: "memory-panel") },
                onOpenWorkspacePanel: { openWindow(id: "workspace-panel") }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 350)
        } detail: {
            VStack(spacing: 0) {
                if let conversation = selectedConversation {
                    ChatView(
                        conversation: conversation,
                        selectedModel: $selectedModel,
                        onBranchConversation: { newConversation in
                            selectedConversation = newConversation
                        }
                    )
                } else {
                    WelcomeView(onNewChat: createNewConversation)
                }
            }
            .padding(.top, 0)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            // Create default memories if needed (first launch)
            DefaultMemoryService.shared.createDefaultMemoriesIfNeeded(modelContext: modelContext)

            // Auto-select first conversation if available
            if selectedConversation == nil && !conversations.isEmpty {
                selectedConversation = conversations.first
            }
        }
        // Handle keyboard shortcuts via notifications
        .onReceive(NotificationCenter.default.publisher(for: .newChat)) { _ in
            createNewConversation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation {
                if columnVisibility == .all {
                    columnVisibility = .detailOnly
                } else {
                    columnVisibility = .all
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusInput)) { _ in
            NotificationCenter.default.post(name: .focusMessageInput, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearConversation)) { _ in
            if let conversation = selectedConversation {
                clearConversation(conversation)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMemoryPanel)) { _ in
            openWindow(id: "memory-panel")
        }
    }

    private func createNewConversation() {
        let conversation = Conversation()

        // Apply default memory configuration
        conversation.memoryContextConfig = DefaultMemoryService.createDefaultMemoryConfig(modelContext: modelContext)

        modelContext.insert(conversation)
        selectedConversation = conversation
    }

    private func deleteConversation(_ conversation: Conversation) {
        if selectedConversation == conversation {
            selectedConversation = nil
        }
        modelContext.delete(conversation)
    }

    private func clearConversation(_ conversation: Conversation) {
        // Clear all messages from the conversation
        conversation.messages.removeAll()
        conversation.title = "New Chat"
        conversation.updatedAt = Date()
    }
}

#Preview {
    MainView()
        .modelContainer(for: [Conversation.self, Message.self], inMemory: true)
}
