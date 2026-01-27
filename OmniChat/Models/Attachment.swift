import Foundation
import SwiftData

enum AttachmentType: String, Codable {
    case image
    case pdf
}

@Model
final class Attachment {
    var id: UUID
    var type: AttachmentType
    var mimeType: String
    var data: Data
    var filename: String?
    var createdAt: Date

    var message: Message?

    init(
        id: UUID = UUID(),
        type: AttachmentType,
        mimeType: String,
        data: Data,
        filename: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.mimeType = mimeType
        self.data = data
        self.filename = filename
        self.createdAt = createdAt
    }
}

/// Helper struct for pending attachments before they're saved
struct PendingAttachment: Identifiable {
    let id = UUID()
    let type: AttachmentType
    let mimeType: String
    let data: Data
    let filename: String?

    /// Maximum file size: 20MB
    static let maxFileSize = 20 * 1024 * 1024

    /// Supported image MIME types
    static let supportedImageTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"]

    /// Supported PDF MIME type
    static let supportedPDFTypes = ["application/pdf"]

    /// All supported MIME types
    static var supportedTypes: [String] {
        supportedImageTypes + supportedPDFTypes
    }

    /// Create from file URL
    static func from(url: URL) throws -> PendingAttachment {
        let data = try Data(contentsOf: url)

        guard data.count <= maxFileSize else {
            throw AttachmentError.fileTooLarge
        }

        let mimeType = mimeType(for: url)

        guard supportedTypes.contains(mimeType) else {
            throw AttachmentError.unsupportedType
        }

        let type: AttachmentType = supportedImageTypes.contains(mimeType) ? .image : .pdf

        return PendingAttachment(
            type: type,
            mimeType: mimeType,
            data: data,
            filename: url.lastPathComponent
        )
    }

    /// Create from clipboard image data
    static func from(imageData: Data, mimeType: String = "image/png") throws -> PendingAttachment {
        guard imageData.count <= maxFileSize else {
            throw AttachmentError.fileTooLarge
        }

        return PendingAttachment(
            type: .image,
            mimeType: mimeType,
            data: imageData,
            filename: nil
        )
    }

    /// Convert to Attachment model for persistence
    func toAttachment() -> Attachment {
        Attachment(
            type: type,
            mimeType: mimeType,
            data: data,
            filename: filename
        )
    }

    private static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "pdf":
            return "application/pdf"
        default:
            return "application/octet-stream"
        }
    }
}

enum AttachmentError: LocalizedError {
    case fileTooLarge
    case unsupportedType
    case readError

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "File is too large. Maximum size is 20MB."
        case .unsupportedType:
            return "Unsupported file type. Please use JPEG, PNG, GIF, WebP, or PDF."
        case .readError:
            return "Could not read the file."
        }
    }
}
