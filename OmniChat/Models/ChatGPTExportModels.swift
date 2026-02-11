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
    case other(Any?)  // Store unknown types for debugging

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try string first
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }

        // Try to decode as a dictionary to check for asset_pointer (image indicator)
        // This is more reliable than trying to decode ChatGPTImagePart directly
        if let dict = try? container.decode([String: AnyCodableValue].self) {
            // Check if this looks like an image (has asset_pointer)
            if dict["asset_pointer"] != nil {
                // It's an image - create ChatGPTImagePart from the dictionary
                let assetPointer = dict["asset_pointer"]?.stringValue
                let contentType = dict["content_type"]?.stringValue
                let width = dict["width"]?.intValue
                let height = dict["height"]?.intValue
                let sizeBytes = dict["size_bytes"]?.intValue
                let fovea = dict["fovea"]?.doubleValue

                let imagePart = ChatGPTImagePart(
                    assetPointer: assetPointer,
                    contentType: contentType,
                    width: width,
                    height: height,
                    sizeBytes: sizeBytes,
                    fovea: fovea
                )
                self = .image(imagePart)
                return
            }
        }

        // Unknown type
        self = .other(nil)
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

/// Helper for decoding arbitrary JSON values
enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let value) = self { return value }
        if case .int(let value) = self { return Double(value) }
        return nil
    }
}

/// Image part from ChatGPT export
struct ChatGPTImagePart: Codable {
    let assetPointer: String?
    let contentType: String?
    let width: Int?
    let height: Int?
    let sizeBytes: Int?
    let fovea: Double?  // Some exports have this field

    enum CodingKeys: String, CodingKey {
        case assetPointer = "asset_pointer"
        case contentType = "content_type"
        case width, height
        case sizeBytes = "size_bytes"
        case fovea
    }

    // Direct initializer for creating from dictionary
    init(assetPointer: String?, contentType: String?, width: Int?, height: Int?, sizeBytes: Int? = nil, fovea: Double? = nil) {
        self.assetPointer = assetPointer
        self.contentType = contentType
        self.width = width
        self.height = height
        self.sizeBytes = sizeBytes
        self.fovea = fovea
    }

    // Custom decoder to handle varying JSON structures
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assetPointer = try container.decodeIfPresent(String.self, forKey: .assetPointer)
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        sizeBytes = try container.decodeIfPresent(Int.self, forKey: .sizeBytes)
        fovea = try container.decodeIfPresent(Double.self, forKey: .fovea)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(assetPointer, forKey: .assetPointer)
        try container.encodeIfPresent(contentType, forKey: .contentType)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
        try container.encodeIfPresent(sizeBytes, forKey: .sizeBytes)
        try container.encodeIfPresent(fovea, forKey: .fovea)
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
