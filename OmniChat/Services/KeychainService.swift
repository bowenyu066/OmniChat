import Foundation
import Security

/// Service for securely storing and retrieving API keys using macOS Keychain
final class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "com.omnichat.app"

    private init() {}

    /// Keys for different API providers
    enum Key: String {
        case openAI = "openai_api_key"
        case anthropic = "anthropic_api_key"
        case google = "google_api_key"

        init?(provider: AIProvider) {
            switch provider {
            case .openAI: self = .openAI
            case .anthropic: self = .anthropic
            case .google: self = .google
            }
        }
    }

    /// Save an API key to the Keychain
    func save(key: Key, value: String) throws {
        let data = Data(value.utf8)

        // Delete any existing item first
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieve an API key from the Keychain
    func get(key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    /// Delete an API key from the Keychain
    func delete(key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Check if an API key exists
    func exists(key: Key) -> Bool {
        return get(key: key) != nil
    }

    /// Get API key for a specific provider
    func getAPIKey(for provider: AIProvider) -> String? {
        guard let key = Key(provider: provider) else { return nil }
        return get(key: key)
    }

    /// Save API key for a specific provider
    func saveAPIKey(_ apiKey: String, for provider: AIProvider) throws {
        guard let key = Key(provider: provider) else { return }
        try save(key: key, value: apiKey)
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain: \(status)"
        }
    }
}
