import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
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
                onDelete: deleteConversation
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 350)
        } detail: {
            if let conversation = selectedConversation {
                ChatView(
                    conversation: conversation,
                    selectedModel: $selectedModel
                )
            } else {
                WelcomeView(onNewChat: createNewConversation)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
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
    }

    private func createNewConversation() {
        let conversation = Conversation()
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

// Additional notification for focusing the message input
extension Notification.Name {
    static let focusMessageInput = Notification.Name("focusMessageInput")
}

#Preview {
    MainView()
        .modelContainer(for: [Conversation.self, Message.self], inMemory: true)
}
