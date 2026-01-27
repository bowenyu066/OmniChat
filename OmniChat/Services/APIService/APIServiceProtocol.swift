import Foundation

/// Represents content types in a multimodal message
enum ChatMessageContent {
    case text(String)
    case image(data: Data, mimeType: String)
    case pdf(data: Data)
}

/// Represents a message in the conversation format expected by AI APIs
struct ChatMessage {
    let role: String
    let contents: [ChatMessageContent]

    /// Text-only convenience initializer
    init(role: MessageRole, content: String) {
        self.role = role.rawValue
        self.contents = [.text(content)]
    }

    /// Multimodal initializer
    init(role: MessageRole, contents: [ChatMessageContent]) {
        self.role = role.rawValue
        self.contents = contents
    }

    /// Initialize from Message model with attachments
    init(from message: Message) {
        self.role = message.role.rawValue

        var contents: [ChatMessageContent] = []

        // Add attachments first
        for attachment in message.attachments {
            switch attachment.type {
            case .image:
                contents.append(.image(data: attachment.data, mimeType: attachment.mimeType))
            case .pdf:
                contents.append(.pdf(data: attachment.data))
            }
        }

        // Add text content
        if !message.content.isEmpty {
            contents.append(.text(message.content))
        }

        self.contents = contents
    }

    /// Convenience property for text-only messages
    var textContent: String? {
        for content in contents {
            if case .text(let text) = content {
                return text
            }
        }
        return nil
    }

    /// Check if message has any attachments
    var hasAttachments: Bool {
        contents.contains { content in
            switch content {
            case .text:
                return false
            case .image, .pdf:
                return true
            }
        }
    }
}

/// Errors that can occur during API operations
enum APIServiceError: LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse
    case rateLimited
    case serverError(statusCode: Int, message: String?)
    case decodingError(Error)
    case streamingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid or missing API key. Please check your settings."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .rateLimited:
            return "Rate limited. Please wait a moment and try again."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message ?? "Unknown error")"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .streamingError(let message):
            return "Streaming error: \(message)"
        }
    }
}

/// Protocol that all AI service providers must implement
protocol APIServiceProtocol {
    /// The provider this service represents
    var provider: AIProvider { get }

    /// Check if the service is configured with a valid API key
    var isConfigured: Bool { get }

    /// Send a message and receive a complete response
    func sendMessage(
        messages: [ChatMessage],
        model: AIModel
    ) async throws -> String

    /// Send a message and receive a streaming response
    func streamMessage(
        messages: [ChatMessage],
        model: AIModel
    ) -> AsyncThrowingStream<String, Error>
}

/// Factory for creating API services
class APIServiceFactory {
    private let keychainService: KeychainService

    init(keychainService: KeychainService = .shared) {
        self.keychainService = keychainService
    }

    func service(for provider: AIProvider) -> APIServiceProtocol {
        switch provider {
        case .openAI:
            return OpenAIService(keychainService: keychainService)
        case .anthropic:
            return AnthropicService(keychainService: keychainService)
        case .google:
            return GoogleAIService(keychainService: keychainService)
        }
    }

    func service(for model: AIModel) -> APIServiceProtocol {
        return service(for: model.provider)
    }
}
