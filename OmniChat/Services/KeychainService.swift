import Foundation
import Security

/// Service for securely storing and retrieving API keys using macOS Keychain
/// Uses a SINGLE consolidated keychain item to avoid multiple password prompts
final class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "com.omnichat.app"
    private let consolidatedAccount = "omnichat_all_api_keys"  // Single keychain item for all keys

    /// In-memory cache for API keys (avoids repeated keychain access)
    private var keyCache: [String: String] = [:]

    /// Track if keys have been loaded
    private var hasLoaded = false
    private var lastAccessIssueMessage: String?

    private init() {}

    /// Keys for different API providers
    enum Key: String, CaseIterable {
        case openAI = "openai"
        case anthropic = "anthropic"
        case google = "google"

        init?(provider: AIProvider) {
            switch provider {
            case .openAI: self = .openAI
            case .anthropic: self = .anthropic
            case .google: self = .google
            }
        }
    }

    // MARK: - Consolidated Storage (Single Keychain Item)

    /// Load ALL API keys from the consolidated keychain item (ONE password prompt)
    private func loadAllKeys() {
        guard !hasLoaded else { return }
        hasLoaded = true

        do {
            if let dictionary = try readConsolidatedKeys() {
                keyCache = dictionary
                lastAccessIssueMessage = nil
            } else {
                // No consolidated keys yet - try migrating from old format
                migrateFromOldFormat()
                lastAccessIssueMessage = nil
            }
        } catch {
            if let keychainError = error as? KeychainError {
                lastAccessIssueMessage = keychainError.errorDescription
            } else {
                lastAccessIssueMessage = error.localizedDescription
            }
        }
    }

    /// Save ALL API keys to the consolidated keychain item
    private func saveAllKeys() throws {
        let data = try JSONEncoder().encode(keyCache)
        try writeConsolidatedKeys(data)
        lastAccessIssueMessage = nil
    }

    private func writeConsolidatedKeys(_ data: Data) throws {
        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: consolidatedAccount
        ]
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError.deleteFailed(deleteStatus)
        }

        // Create new item with all keys
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: consolidatedAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func readConsolidatedKeys() throws -> [String: String]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: consolidatedAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            if Self.isAuthorizationRelated(status) {
                throw KeychainError.authorizationChanged(status)
            }
            throw KeychainError.readFailed(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.readFailed(status)
        }

        guard let dictionary = try? JSONDecoder().decode([String: String].self, from: data) else {
            throw KeychainError.invalidData
        }

        return dictionary
    }

    private static func isAuthorizationRelated(_ status: OSStatus) -> Bool {
        status == errSecAuthFailed ||
        status == errSecInteractionNotAllowed ||
        status == errSecUserCanceled
    }

    // MARK: - Public API

    /// Save an API key (updates consolidated keychain item)
    func save(key: Key, value: String) throws {
        loadAllKeys()
        keyCache[key.rawValue] = value
        try saveAllKeys()
    }

    /// Retrieve an API key from cache (loads all keys on first access)
    func get(key: Key) -> String? {
        loadAllKeys()
        let value = keyCache[key.rawValue]
        return value?.isEmpty == false ? value : nil
    }

    /// Delete an API key
    func delete(key: Key) throws {
        loadAllKeys()
        keyCache.removeValue(forKey: key.rawValue)
        try saveAllKeys()
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
    /// With consolidated storage, this triggers only ONE password prompt
    func preloadKeys() {
        loadAllKeys()
    }

    func keychainAccessIssue() -> String? {
        lastAccessIssueMessage
    }

    /// Clear the cache (use when you want to force re-read from keychain)
    func clearCache() {
        keyCache.removeAll()
        hasLoaded = false
        lastAccessIssueMessage = nil
    }

    // MARK: - Migration from Old Format

    /// Re-save consolidated keychain content under current signing identity.
    @discardableResult
    func rebindConsolidatedKeychainAccess() throws -> Int {
        let snapshot: [String: String]
        do {
            if let consolidated = try readConsolidatedKeys() {
                snapshot = consolidated
            } else {
                // Fall back to old format if consolidated item does not exist.
                snapshot = readOldFormatSnapshot()
            }
        } catch {
            if let keychainError = error as? KeychainError {
                lastAccessIssueMessage = keychainError.errorDescription
            }
            throw error
        }

        guard !snapshot.isEmpty else {
            keyCache = [:]
            hasLoaded = true
            lastAccessIssueMessage = nil
            return 0
        }

        let backupSnapshot = snapshot
        keyCache = snapshot
        hasLoaded = true

        do {
            try saveAllKeys()
            return snapshot.count
        } catch {
            // Keep keys in memory so user can retry without data entry in this session.
            keyCache = backupSnapshot
            hasLoaded = true
            if let keychainError = error as? KeychainError {
                lastAccessIssueMessage = keychainError.errorDescription
            }
            throw error
        }
    }

    /// Migrate from old individual keychain items to new consolidated format
    func migrateKeysToNewAccessSettings() {
        migrateFromOldFormat()
    }

    private func migrateFromOldFormat() {
        // Try to load keys from old individual keychain items
        let oldKeys = ["openai_api_key", "anthropic_api_key", "google_api_key"]
        let newKeys: [Key] = [.openAI, .anthropic, .google]
        var foundAnyKey = false

        for (oldKey, newKey) in zip(oldKeys, newKeys) {
            if let value = getOldFormatKey(account: oldKey), !value.isEmpty {
                keyCache[newKey.rawValue] = value
                foundAnyKey = true

                // Delete old format key after migrating
                deleteOldFormatKey(account: oldKey)
            }
        }

        // Save to new consolidated format if we found any keys
        if foundAnyKey {
            do {
                try saveAllKeys()
            } catch {
                if let keychainError = error as? KeychainError {
                    lastAccessIssueMessage = keychainError.errorDescription
                }
            }
        }
    }

    private func readOldFormatSnapshot() -> [String: String] {
        let oldKeys = ["openai_api_key", "anthropic_api_key", "google_api_key"]
        let newKeys: [Key] = [.openAI, .anthropic, .google]
        var snapshot: [String: String] = [:]

        for (oldKey, newKey) in zip(oldKeys, newKeys) {
            if let value = getOldFormatKey(account: oldKey), !value.isEmpty {
                snapshot[newKey.rawValue] = value
            }
        }
        return snapshot
    }

    /// Read a key from old individual keychain item format
    private func getOldFormatKey(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
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

    /// Delete an old format keychain item
    private func deleteOldFormatKey(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: LocalizedError {
    case readFailed(OSStatus)
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidData
    case authorizationChanged(OSStatus)

    var errorDescription: String? {
        switch self {
        case .readFailed(let status):
            return "Failed to read from Keychain: \(status)"
        case .saveFailed(let status):
            return "Failed to save to Keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain: \(status)"
        case .invalidData:
            return "Stored Keychain data is invalid. Re-enter API keys if this keeps happening."
        case .authorizationChanged(let status):
            return "Detected signing/authorization change for Keychain access (\(status)). Please authorize once, then run Rebind Keychain Access in Settings > API Keys."
        }
    }
}
