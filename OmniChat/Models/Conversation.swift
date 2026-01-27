import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(id: UUID = UUID(), title: String = "New Chat", createdAt: Date = Date(), updatedAt: Date = Date(), messages: [Message] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    /// Updates the conversation title based on the first user message
    func updateTitleFromFirstMessage() {
        if let firstUserMessage = messages.first(where: { $0.role == .user }) {
            let content = firstUserMessage.content
            let maxLength = 50
            if content.count > maxLength {
                title = String(content.prefix(maxLength)) + "..."
            } else {
                title = content
            }
        }
    }
}
