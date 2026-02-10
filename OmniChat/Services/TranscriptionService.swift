import Foundation

/// Service for transcribing audio using OpenAI's gpt-4o-transcribe model
@MainActor
final class TranscriptionService {
    static let shared = TranscriptionService()

    private let keychainService: KeychainService
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"

    init(keychainService: KeychainService = .shared) {
        self.keychainService = keychainService
    }

    /// Check if OpenAI API key is configured
    var isConfigured: Bool {
        guard let key = keychainService.getAPIKey(for: .openAI) else { return false }
        return !key.isEmpty
    }

    private var apiKey: String? {
        keychainService.getAPIKey(for: .openAI)
    }

    /// Transcribe audio data to text
    /// - Parameters:
    ///   - audioData: The audio file data (m4a, mp3, wav, etc.)
    ///   - format: The file format/extension (e.g., "m4a", "mp3")
    /// - Returns: The transcribed text
    func transcribe(audioData: Data, format: String) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }

        guard let url = URL(string: baseURL) else {
            throw TranscriptionError.invalidURL
        }

        // Create multipart/form-data request
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()

        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.\(format)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/\(format)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("gpt-4o-transcribe\r\n".data(using: .utf8)!)

        // Add response_format field (plain text is simpler to handle)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("text\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            // Response is plain text
            guard let text = String(data: data, encoding: .utf8) else {
                throw TranscriptionError.invalidResponse
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)

        case 401:
            throw TranscriptionError.invalidAPIKey

        case 429:
            throw TranscriptionError.rateLimited

        default:
            // Try to parse error message
            if let errorJson = try? JSONDecoder().decode(OpenAITranscriptionError.self, from: data) {
                throw TranscriptionError.serverError(message: errorJson.error.message)
            }
            throw TranscriptionError.serverError(message: "HTTP \(httpResponse.statusCode)")
        }
    }
}

// MARK: - Error Types

enum TranscriptionError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case invalidAPIKey
    case rateLimited
    case serverError(message: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API key is not configured. Please add it in Settings."
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidAPIKey:
            return "Invalid OpenAI API key"
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

// MARK: - Response Models

private struct OpenAITranscriptionError: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String
    }
}
