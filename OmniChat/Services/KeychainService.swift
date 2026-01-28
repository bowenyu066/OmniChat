import Foundation
import Security

/// Service for securely storing and retrieving API keys using macOS Keychain
final class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "com.omnichat.app"

    /// In-memory cache for API keys (avoids repeated keychain access)
    private var keyCache: [Key: String] = [:]

    /// Track if keys have been preloaded
    private var hasPreloaded = false

    private init() {}

    /// Keys for different API providers
    enum Key: String, CaseIterable {
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

    /// Save an API key to the Keychain (without requiring user interaction for future reads)
    func save(key: Key, value: String) throws {
        let data = Data(value.utf8)

        // Delete any existing item first
        try? delete(key: key)

        // Create query without access control that requires user presence
        // kSecAttrAccessibleAfterFirstUnlock allows reading without prompts after device unlock
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }

        // Update cache
        keyCache[key] = value
    }

    /// Retrieve an API key from the Keychain
    func get(key: Key) -> String? {
        // Return from cache if available
        if let cached = keyCache[key] {
            return cached.isEmpty ? nil : cached
        }

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
            // Cache empty result to avoid repeated keychain queries
            keyCache[key] = ""
            return nil
        }

        // Cache the result
        keyCache[key] = string
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

        // Remove from cache
        keyCache.removeValue(forKey: key)

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

    /// Preload all API keys into cache at app startup
    /// This triggers any keychain prompts upfront, all at once
    func preloadKeys() {
        guard !hasPreloaded else { return }
        hasPreloaded = true

        for key in Key.allCases {
            _ = get(key: key)
        }
    }

    /// Clear the cache (use when you want to force re-read from keychain)
    func clearCache() {
        keyCache.removeAll()
        hasPreloaded = false
    }

    /// Migrate existing keys to new access settings (run once after update)
    func migrateKeysToNewAccessSettings() {
        for key in Key.allCases {
            // Read current value (may trigger prompt)
            if let value = get(key: key), !value.isEmpty {
                // Re-save with new access settings
                try? save(key: key, value: value)
            }
        }
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
