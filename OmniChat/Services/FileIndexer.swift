import Foundation
import SwiftData

enum FileIndexerError: LocalizedError {
    case noWorkspaceFolder
    case accessDenied
    case invalidBookmark

    var errorDescription: String? {
        switch self {
        case .noWorkspaceFolder:
            return "Workspace has no folder selected."
        case .accessDenied:
            return "Cannot access workspace folder. Please select it again."
        case .invalidBookmark:
            return "Workspace folder bookmark is invalid. Please reselect the folder."
        }
    }
}

/// Service for indexing files in a workspace
final class FileIndexer {
    static let shared = FileIndexer()

    private init() {}

    /// Supported file extensions for indexing
    private let supportedExtensions = [
        "md", "txt", "swift", "py", "js", "ts", "jsx", "tsx",
        "json", "yaml", "yml", "toml", "xml", "html", "css",
        "sh", "bash", "go", "rs", "java", "c", "cpp", "h"
    ]

    /// Lines per chunk when splitting files
    private let linesPerChunk = 50

    /// Maximum file size to index (10MB)
    private let maxFileSize: Int64 = 10 * 1024 * 1024

    /// Indexes all files in a workspace
    /// - Parameters:
    ///   - workspace: The workspace to index
    ///   - modelContext: SwiftData model context for persistence
    ///   - onProgress: Optional closure called with progress updates (current, total)
    /// - Throws: FileIndexerError if indexing fails
    @MainActor
    func indexWorkspace(
        _ workspace: Workspace,
        modelContext: ModelContext,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws {
        // Resolve bookmark
        guard let bookmarkData = workspace.folderBookmark else {
            throw FileIndexerError.noWorkspaceFolder
        }

        let folderURL: URL
        do {
            folderURL = try SecurityScopedBookmarkService.shared.resolveBookmark(bookmarkData)
        } catch {
            throw FileIndexerError.invalidBookmark
        }

        // Set indexing status
        workspace.indexStatus = .indexing

        do {
            try await folderURL.accessSecurityScopedResource {
                try indexFolder(
                    folderURL: folderURL,
                    workspace: workspace,
                    modelContext: modelContext,
                    onProgress: onProgress
                )
            }

            workspace.lastIndexedAt = Date()
            workspace.indexStatus = .idle
        } catch {
            workspace.indexStatus = .error
            throw error
        }
    }

    /// Internal indexing implementation
    private func indexFolder(
        folderURL: URL,
        workspace: Workspace,
        modelContext: ModelContext,
        onProgress: ((Int, Int) -> Void)?
    ) throws {
        // Enumerate files
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw FileIndexerError.accessDenied
        }

        var filesToIndex: [(url: URL, mtime: Date, size: Int64)] = []

        // First pass: collect files to index
        while let fileURL = enumerator.nextObject() as? URL {
            // Skip if not supported extension
            guard supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }

            // Get file attributes
            let resourceValues = try? fileURL.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isDirectoryKey
            ])

            // Skip directories
            if resourceValues?.isDirectory == true { continue }

            guard let mtime = resourceValues?.contentModificationDate,
                  let size = resourceValues?.fileSize as? Int64 else { continue }

            // Skip files that are too large
            if size > maxFileSize { continue }

            // Check if already indexed and unchanged
            let relativePath = fileURL.path.replacingOccurrences(
                of: folderURL.path + "/",
                with: ""
            )

            if let existing = workspace.fileEntries.first(where: { $0.relativePath == relativePath }),
               existing.mtime == mtime {
                continue  // Skip unchanged file
            }

            filesToIndex.append((fileURL, mtime, size))
        }

        // Second pass: index files with progress
        let totalFiles = filesToIndex.count
        for (index, file) in filesToIndex.enumerated() {
            onProgress?(index + 1, totalFiles)

            do {
                let entry = try indexFile(
                    url: file.url,
                    mtime: file.mtime,
                    size: file.size,
                    relativeTo: folderURL,
                    workspace: workspace
                )

                // Remove old entry if exists
                let relativePath = file.url.path.replacingOccurrences(
                    of: folderURL.path + "/",
                    with: ""
                )
                if let oldEntry = workspace.fileEntries.first(where: { $0.relativePath == relativePath }) {
                    modelContext.delete(oldEntry)
                }

                // Insert new entry
                modelContext.insert(entry)
                workspace.fileEntries.append(entry)
            } catch {
                // Log error but continue indexing other files
                print("Failed to index \(file.url.path): \(error)")
            }
        }
    }

    /// Indexes a single file
    private func indexFile(
        url: URL,
        mtime: Date,
        size: Int64,
        relativeTo baseURL: URL,
        workspace: Workspace
    ) throws -> FileIndexEntry {
        // Read content
        let content = try String(contentsOf: url, encoding: .utf8)

        // Split into lines
        let lines = content.components(separatedBy: .newlines)

        // Create chunks
        var chunks: [FileChunk] = []
        for startIndex in stride(from: 0, to: lines.count, by: linesPerChunk) {
            let endIndex = min(startIndex + linesPerChunk, lines.count)
            let chunkLines = lines[startIndex..<endIndex]
            let chunkContent = chunkLines.joined(separator: "\n")

            chunks.append(FileChunk(
                content: chunkContent,
                startLine: startIndex + 1,  // 1-indexed
                endLine: endIndex
            ))
        }

        // Calculate relative path
        let relativePath = url.path.replacingOccurrences(
            of: baseURL.path + "/",
            with: ""
        )

        // Create entry
        return FileIndexEntry(
            relativePath: relativePath,
            mtime: mtime,
            fileSize: size,
            chunks: chunks,
            workspace: workspace
        )
    }
}
