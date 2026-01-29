import Foundation
import SwiftData
import PDFKit

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
        "sh", "bash", "go", "rs", "java", "c", "cpp", "h",
        "pdf"
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

            // Explicitly save the context
            print("💾 Saving \(workspace.fileEntries.count) entries to database...")
            try modelContext.save()
            print("✅ Database save complete!")
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
        print("🔍 Starting indexing for: \(folderURL.path)")

        // Enumerate files
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            print("❌ Failed to create enumerator")
            throw FileIndexerError.accessDenied
        }

        var filesToIndex: [(url: URL, mtime: Date, size: Int64)] = []
        var filesScanned = 0
        var filesSkippedExtension = 0
        var filesSkippedSize = 0
        var filesSkippedUnchanged = 0
        var filesSkippedError = 0

        // First pass: collect files to index
        while let fileURL = enumerator.nextObject() as? URL {
            filesScanned += 1

            // Skip if not supported extension
            guard supportedExtensions.contains(fileURL.pathExtension.lowercased()) else {
                filesSkippedExtension += 1
                continue
            }

            // Get file attributes using FileManager
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            } catch {
                print("⚠️ FileManager.attributesOfItem failed for \(fileURL.lastPathComponent): \(error)")
                filesSkippedError += 1
                continue
            }

            // Skip directories
            if let fileType = attributes[.type] as? FileAttributeType, fileType == .typeDirectory {
                continue
            }

            // Get modification date and size from attributes
            guard let mtime = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? Int64 else {
                print("⚠️ Could not get mtime/size from attributes for: \(fileURL.lastPathComponent)")
                filesSkippedError += 1
                continue
            }

            // Skip files that are too large
            if size > maxFileSize {
                print("⚠️ Skipping large file (\(size) bytes): \(fileURL.lastPathComponent)")
                filesSkippedSize += 1
                continue
            }

            // Check if already indexed and unchanged
            let relativePath = fileURL.path.replacingOccurrences(
                of: folderURL.path + "/",
                with: ""
            )

            if let existing = workspace.fileEntries.first(where: { $0.relativePath == relativePath }),
               existing.mtime == mtime {
                filesSkippedUnchanged += 1
                continue  // Skip unchanged file
            }

            print("✅ Will index: \(fileURL.lastPathComponent) (\(size) bytes)")
            filesToIndex.append((fileURL, mtime, size))
        }

        print("📊 Scan complete:")
        print("  - Total scanned: \(filesScanned)")
        print("  - Skipped (extension): \(filesSkippedExtension)")
        print("  - Skipped (error): \(filesSkippedError)")
        print("  - Skipped (too large): \(filesSkippedSize)")
        print("  - Skipped (unchanged): \(filesSkippedUnchanged)")
        print("  - To index: \(filesToIndex.count)")

        // Second pass: index files with progress
        print("🔄 Starting to index \(filesToIndex.count) files...")
        let totalFiles = filesToIndex.count
        var successCount = 0
        var failCount = 0

        for (index, file) in filesToIndex.enumerated() {
            print("📝 Indexing [\(index + 1)/\(totalFiles)]: \(file.url.lastPathComponent)")
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
                    workspace.fileEntries.removeAll { $0.id == oldEntry.id }
                }

                // Set the workspace relationship BEFORE inserting
                entry.workspace = workspace

                // Insert new entry (SwiftData will handle the relationship)
                modelContext.insert(entry)

                print("   ✓ Success: \(entry.chunks.count) chunks, relationship set")
                successCount += 1
            } catch {
                // Log error but continue indexing other files
                print("   ❌ Failed to index \(file.url.lastPathComponent): \(error)")
                failCount += 1
            }
        }

        print("✅ Indexing complete: \(successCount) succeeded, \(failCount) failed")
    }

    /// Indexes a single file
    private func indexFile(
        url: URL,
        mtime: Date,
        size: Int64,
        relativeTo baseURL: URL,
        workspace: Workspace
    ) throws -> FileIndexEntry {
        let isPDF = url.pathExtension.lowercased() == "pdf"
        print("      🔧 Processing file: isPDF=\(isPDF)")

        // Read content
        let content: String
        if isPDF {
            // Extract text from PDF
            print("      📖 Extracting PDF text...")
            content = try extractTextFromPDF(url: url)
        } else {
            // Read as text file
            content = try String(contentsOf: url, encoding: .utf8)
        }

        // Split into lines
        let lines = content.components(separatedBy: .newlines)
        print("      📐 Split into \(lines.count) lines")

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
        print("      🧩 Created \(chunks.count) chunks")

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

    /// Extracts text from a PDF file
    private func extractTextFromPDF(url: URL) throws -> String {
        guard let pdfDocument = PDFDocument(url: url) else {
            print("      ⚠️ Could not load PDF document")
            throw FileIndexerError.accessDenied
        }

        var text = ""
        let pageCount = pdfDocument.pageCount
        print("      📄 PDF has \(pageCount) pages")

        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            if let pageText = page.string {
                // Add page header
                text += "\n--- Page \(pageIndex + 1) ---\n"
                text += pageText
                text += "\n"
            }
        }

        print("      📏 Extracted \(text.count) characters")
        return text
    }
}
