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

    @Relationship(deleteRule: .cascade, inverse: \Attachment.message)
    var attachments: [Attachment] = []

    // RAG: Embedding and summary fields for semantic search
    var embeddingData: Data?
    var summary: String?
    var embeddedAt: Date?

    // Branching support: siblings are alternate responses at the same position
    var siblingGroupId: UUID?    // Groups sibling messages together (nil = no siblings)
    var siblingIndex: Int = 0    // Position within sibling group (0, 1, 2...)
    var isActive: Bool = true    // Is this the currently displayed sibling?

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(), modelUsed: String? = nil, attachments: [Attachment] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.modelUsed = modelUsed
        self.attachments = attachments
    }

    var hasAttachments: Bool {
        !attachments.isEmpty
    }

    /// Computed property to get/set embedding vector as [Double]
    var embeddingVector: [Double]? {
        get {
            guard let data = embeddingData else { return nil }
            // Decode Data to [Double] - stored as raw bytes
            let count = data.count / MemoryLayout<Double>.stride
            guard count > 0 else { return nil }
            return data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Double.self).prefix(count))
            }
        }
        set {
            guard let vector = newValue else {
                embeddingData = nil
                return
            }
            // Encode [Double] to Data as raw bytes
            embeddingData = vector.withUnsafeBufferPointer { buffer in
                Data(buffer: buffer)
            }
        }
    }

    /// Check if this message has been embedded for RAG
    var hasEmbedding: Bool {
        embeddingData != nil && embeddedAt != nil
    }

    /// Check if this message has any siblings (alternate responses)
    var hasSiblings: Bool {
        siblingGroupId != nil
    }
}
