import Foundation
import SwiftData

@Model
final class MemoryItem {
    var id: UUID = UUID()
    var title: String
    var body: String
    var typeRawValue: String
    var scopeData: Data  // Encoded MemoryScope
    var tags: [String] = []
    var sourceMessageId: UUID?  // Optional link to originating message
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isDeleted: Bool = false  // Soft delete
    var isPinned: Bool = false   // Priority inclusion
    var isDefaultSelected: Bool = false  // Auto-select in new conversations

    // Relationships
    var workspace: Workspace?  // Optional workspace scoping

    // Computed properties for enums
    var type: MemoryType {
        get { MemoryType(rawValue: typeRawValue) ?? .reference }
        set { typeRawValue = newValue.rawValue }
    }

    var scope: MemoryScope {
        get {
            (try? JSONDecoder().decode(MemoryScope.self, from: scopeData)) ?? .global
        }
        set {
            scopeData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        type: MemoryType,
        scope: MemoryScope = .global,
        tags: [String] = [],
        sourceMessageId: UUID? = nil,
        workspace: Workspace? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.typeRawValue = type.rawValue
        self.scopeData = (try? JSONEncoder().encode(scope)) ?? Data()
        self.tags = tags
        self.sourceMessageId = sourceMessageId
        self.workspace = workspace
    }

    /// Returns all tags as a comma-separated string
    var tagsString: String {
        tags.joined(separator: ", ")
    }

    /// Sets tags from a comma-separated string
    func setTags(from string: String) {
        tags = string
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Returns a preview of the body (first 100 characters)
    var bodyPreview: String {
        if body.count <= 100 {
            return body
        }
        return String(body.prefix(100)) + "..."
    }

    /// Human-readable relative time (e.g., "2 days ago")
    var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }
}
