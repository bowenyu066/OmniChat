import Foundation
import SwiftData

enum IndexStatus: String, Codable {
    case idle = "Idle"
    case indexing = "Indexing"
    case error = "Error"
}

@Model
final class Workspace {
    var id: UUID = UUID()
    var name: String
    var workspaceDescription: String = ""
    var folderBookmark: Data?  // Security-scoped bookmark
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var indexStatusRawValue: String = IndexStatus.idle.rawValue
    var lastIndexedAt: Date?
    var writeEnabled: Bool = false  // Default read-only

    // Computed property for IndexStatus
    var indexStatus: IndexStatus {
        get { IndexStatus(rawValue: indexStatusRawValue) ?? .idle }
        set { indexStatusRawValue = newValue.rawValue }
    }

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \MemoryItem.workspace)
    var memories: [MemoryItem] = []

    // Note: FileIndexEntry relationship will be added in Milestone 2
    // Note: Conversation relationship will be added when we modify Conversation model

    init(
        id: UUID = UUID(),
        name: String,
        workspaceDescription: String = "",
        folderBookmark: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.workspaceDescription = workspaceDescription
        self.folderBookmark = folderBookmark
    }
}
