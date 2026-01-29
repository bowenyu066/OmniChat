import SwiftUI

struct SidebarView: View {
    let conversations: [Conversation]
    @Binding var selectedConversation: Conversation?
    let onNewChat: () -> Void
    let onDelete: (Conversation) -> Void
    let onOpenMemoryPanel: () -> Void
    let onOpenWorkspacePanel: () -> Void

    @State private var searchText = ""
    @State private var editingConversationId: UUID?

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
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

            Divider()

            // Panels section at the bottom
            VStack(spacing: 0) {
                Button(action: onOpenMemoryPanel) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                        Text("Memory Panel")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Divider()

                Button(action: onOpenWorkspacePanel) {
                    HStack {
                        Image(systemName: "folder.badge.gearshape")
                        Text("Workspace Panel")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
        }
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
        onDelete: { _ in },
        onOpenMemoryPanel: {},
        onOpenWorkspacePanel: {}
    )
}
