import Foundation
import AppKit

enum BookmarkError: LocalizedError {
    case cannotCreateBookmark
    case staleBookmark
    case cannotResolveBookmark
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .cannotCreateBookmark:
            return "Failed to create security-scoped bookmark for the selected folder."
        case .staleBookmark:
            return "The folder bookmark is no longer valid. Please select the folder again."
        case .cannotResolveBookmark:
            return "Cannot access the workspace folder. Please select it again."
        case .accessDenied:
            return "Access to the workspace folder was denied."
        }
    }
}

/// Service for managing security-scoped bookmarks to maintain folder permissions across app restarts
final class SecurityScopedBookmarkService {
    static let shared = SecurityScopedBookmarkService()

    private init() {}

    /// Creates a security-scoped bookmark for a folder URL
    /// - Parameter url: The folder URL to create a bookmark for
    /// - Returns: Bookmark data that can be stored persistently
    /// - Throws: BookmarkError if bookmark creation fails
    func createBookmark(for url: URL) throws -> Data {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return bookmarkData
        } catch {
            throw BookmarkError.cannotCreateBookmark
        }
    }

    /// Resolves a security-scoped bookmark to a URL
    /// - Parameter data: The bookmark data previously created
    /// - Returns: The resolved URL
    /// - Throws: BookmarkError if resolution fails or bookmark is stale
    func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false

        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                throw BookmarkError.staleBookmark
            }

            return url
        } catch {
            if error is BookmarkError {
                throw error
            }
            throw BookmarkError.cannotResolveBookmark
        }
    }

    /// Shows a folder picker dialog and returns the selected URL with a created bookmark
    /// - Returns: Tuple of (URL, bookmark data) if successful, nil if cancelled
    @MainActor
    func selectFolder() -> (url: URL, bookmark: Data)? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder for this workspace"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            let bookmark = try createBookmark(for: url)
            return (url, bookmark)
        } catch {
            // Show error alert
            let alert = NSAlert()
            alert.messageText = "Cannot Create Workspace"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
            return nil
        }
    }
}

/// Helper extension for working with security-scoped resources
extension URL {
    /// Executes a closure with access to this security-scoped resource
    /// - Parameter closure: The closure to execute while accessing the resource
    /// - Returns: The result of the closure
    /// - Throws: Any error thrown by the closure or BookmarkError.accessDenied
    func accessSecurityScopedResource<T>(_ closure: () throws -> T) throws -> T {
        guard startAccessingSecurityScopedResource() else {
            throw BookmarkError.accessDenied
        }
        defer { stopAccessingSecurityScopedResource() }

        return try closure()
    }
}
