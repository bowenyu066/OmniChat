import Foundation
import SwiftData

/// Represents a file chunk for efficient retrieval
struct FileChunk: Codable {
    var content: String
    var startLine: Int
    var endLine: Int
}

/// Represents an indexed file in a workspace
@Model
final class FileIndexEntry {
    var id: UUID = UUID()
    var relativePath: String  // Path relative to workspace root
    var mtime: Date  // Last modified time
    var fileSize: Int64
    var chunksData: Data  // Encoded [FileChunk]

    // Relationship
    var workspace: Workspace?

    /// Computed property for chunks
    var chunks: [FileChunk] {
        get {
            (try? JSONDecoder().decode([FileChunk].self, from: chunksData)) ?? []
        }
        set {
            chunksData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(
        id: UUID = UUID(),
        relativePath: String,
        mtime: Date,
        fileSize: Int64,
        chunks: [FileChunk] = [],
        workspace: Workspace? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.mtime = mtime
        self.fileSize = fileSize
        self.chunksData = (try? JSONEncoder().encode(chunks)) ?? Data()
        self.workspace = workspace
    }
}
