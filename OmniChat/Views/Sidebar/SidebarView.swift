import SwiftUI

struct SidebarView: View {
    let conversations: [Conversation]
    @Binding var selectedConversation: Conversation?
    let onNewChat: () -> Void
    let onDelete: (Conversation) -> Void

    @State private var searchText = ""
    @State private var editingConversationId: UUID?

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List(selection: $selectedConversation) {
            ForEach(filteredConversations) { conversation in
                ConversationRow(
                    conversation: conversation,
                    isEditing: Binding(
                        get: { editingConversationId == conversation.id },
                        set: { newValue in
                            editingConversationId = newValue ? conversation.id : nil
                        }
                    )
                )
                .tag(conversation)
                .contextMenu {
                    Button {
                        editingConversationId = conversation.id
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        onDelete(conversation)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search chats")
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onNewChat) {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

#Preview {
    SidebarView(
        conversations: [
            Conversation(title: "Test Chat 1"),
            Conversation(title: "Another conversation"),
        ],
        selectedConversation: .constant(nil),
        onNewChat: {},
        onDelete: { _ in }
    )
}
