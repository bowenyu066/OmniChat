import SwiftUI

struct ConversationRow: View {
    @Bindable var conversation: Conversation
    @Binding var isEditing: Bool

    @State private var editedTitle: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEditing {
                TextField("Chat title", text: $editedTitle)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .focused($isFocused)
                    .onSubmit {
                        saveTitle()
                    }
                    .onExitCommand {
                        cancelEditing()
                    }
                    .onAppear {
                        editedTitle = conversation.title
                        isFocused = true
                    }
            } else {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: isFocused) { newValue in
            if !newValue && isEditing {
                saveTitle()
            }
        }
    }

    private func saveTitle() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            conversation.title = trimmed
        }
        isEditing = false
    }

    private func cancelEditing() {
        isEditing = false
    }
}

#Preview {
    ConversationRow(
        conversation: Conversation(title: "Sample Conversation"),
        isEditing: .constant(false)
    )
}
