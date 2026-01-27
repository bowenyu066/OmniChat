import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

@Model
final class Message {
    var id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date
    var modelUsed: String?

    var conversation: Conversation?

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(), modelUsed: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.modelUsed = modelUsed
    }
}
