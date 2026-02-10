import Foundation

// MARK: - ChatGPT Export JSON Models

/// Root conversation object from ChatGPT export
struct ChatGPTConversation: Codable {
    let title: String
    let createTime: Double
    let updateTime: Double
    let mapping: [String: ChatGPTNode]

    enum CodingKeys: String, CodingKey {
        case title
        case createTime = "create_time"
        case updateTime = "update_time"
        case mapping
    }
}

/// Node in the conversation tree structure
struct ChatGPTNode: Codable {
    let id: String
    let message: ChatGPTNodeMessage?
    let parent: String?
    let children: [String]
}

/// Message within a node
struct ChatGPTNodeMessage: Codable {
    let id: String
    let author: ChatGPTAuthor
    let createTime: Double?
    let content: ChatGPTContent
    let metadata: ChatGPTMetadata?

    enum CodingKeys: String, CodingKey {
        case id, author, content, metadata
        case createTime = "create_time"
    }
}

/// Author of a message
struct ChatGPTAuthor: Codable {
    let role: String  // "user", "assistant", "system", "tool"
}

/// Content of a message
struct ChatGPTContent: Codable {
    let contentType: String
    let parts: [ChatGPTContentPart]?

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case parts
    }
}

/// Content part - can be string, image, or other types
enum ChatGPTContentPart: Codable {
    case string(String)
    case image(ChatGPTImagePart)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try string first
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }

        // Try image object
        if let imagePart = try? container.decode(ChatGPTImagePart.self) {
            self = .image(imagePart)
            return
        }

        // Unknown type
        self = .other
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .image(let imagePart):
            try container.encode(imagePart)
        case .other:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var imagePart: ChatGPTImagePart? {
        if case .image(let part) = self {
            return part
        }
        return nil
    }
}

/// Image part from ChatGPT export
struct ChatGPTImagePart: Codable {
    let assetPointer: String?
    let contentType: String?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case assetPointer = "asset_pointer"
        case contentType = "content_type"
        case width, height
    }

    /// Extract the file ID from asset_pointer (e.g., "file-service://file-AbCdEf123456" -> "file-AbCdEf123456")
    var fileId: String? {
        guard let pointer = assetPointer else { return nil }
        // asset_pointer format: "file-service://file-XXXX"
        if pointer.hasPrefix("file-service://") {
            return String(pointer.dropFirst("file-service://".count))
        }
        return nil
    }
}

/// Metadata for a message
struct ChatGPTMetadata: Codable {
    let isVisuallyHiddenFromConversation: Bool?

    enum CodingKeys: String, CodingKey {
        case isVisuallyHiddenFromConversation = "is_visually_hidden_from_conversation"
    }
}

// MARK: - Extracted Message (after tree traversal)

/// Simplified message extracted from the tree structure
struct ExtractedChatGPTMessage {
    let id: String
    let role: String
    let content: String
    let createTime: Double?
    var imageFileIds: [String] = []  // File IDs for images to be loaded from ZIP
}

/// Image data extracted from ZIP
struct ExtractedImageData {
    let data: Data
    let mimeType: String
    let filename: String
}
