import SwiftUI
import SwiftData
import AppKit
import LocalAuthentication

final class AuthManager: ObservableObject {
    private let lastAuthKey = "last_auth_time"

    // 30 days grace period
    private let graceInterval: TimeInterval = 30 * 24 * 60 * 60

    // Session-based auth for settings (valid while settings window is open)
    @Published var isSettingsAuthenticated = false

    private var lastAuthTime: Double {
        get { UserDefaults.standard.double(forKey: lastAuthKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastAuthKey) }
    }

    var needsAppUnlock: Bool {
        let now = Date().timeIntervalSince1970
        return lastAuthTime == 0 || (now - lastAuthTime) > graceInterval
    }

    func markAppAuthenticated() {
        lastAuthTime = Date().timeIntervalSince1970
    }

    /// Authenticate for app startup - only if 30 days have passed
    @MainActor
    func authenticateAppIfNeeded() async -> Bool {
        guard needsAppUnlock else { return true }

        do {
            try await authenticateOnce(reason: "Authenticate to unlock OmniChat")
            markAppAuthenticated()
            return true
        } catch {
            print("App authentication failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Authenticate for Settings access - once per session
    @MainActor
    func authenticateForSettings() async -> Bool {
        if isSettingsAuthenticated { return true }

        do {
            try await authenticateOnce(reason: "Authenticate to access API Keys")
            isSettingsAuthenticated = true
            return true
        } catch {
            print("Settings authentication failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Clear settings session auth (call when leaving settings)
    func clearSettingsAuth() {
        isSettingsAuthenticated = false
    }

    /// Single authentication attempt using Touch ID with password fallback
    private func authenticateOnce(reason: String) async throws {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"

        var authError: NSError?

        // Use deviceOwnerAuthentication which handles biometrics -> password fallback automatically
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            throw authError ?? NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Device does not support authentication"])
        }

        try await context.evaluatePolicyAsync(.deviceOwnerAuthentication, localizedReason: reason)
    }
}

private extension LAContext {
    func evaluatePolicyAsync(_ policy: LAPolicy, localizedReason: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.evaluatePolicy(policy, localizedReason: localizedReason) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(domain: "Auth", code: -2, userInfo: [NSLocalizedDescriptionKey: "Authentication was not successful"]))
                }
            }
        }
    }
}

@main
struct OmniChatApp: App {
    @StateObject private var authManager = AuthManager()

    private static let keychainMigrationKey = "keychain_migrated_v2"

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Conversation.self,
            Message.self,
            Attachment.self,
            MemoryItem.self,
            Workspace.self,
            FileIndexEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(authManager)
                .onAppear {
                    Task {
                        // Authenticate app if needed (30-day grace period)
                        _ = await authManager.authenticateAppIfNeeded()

                        // Migrate existing keychain items to new access settings (one-time)
                        // This re-saves keys without requiring user interaction for future reads
                        await migrateKeychainIfNeeded()

                        // Preload all API keys into cache
                        KeychainService.shared.preloadKeys()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            // Replace the default New Item command
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    NotificationCenter.default.post(name: .newChat, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // Add sidebar toggle
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }

            // Add focus shortcuts in a new menu group
            CommandMenu("Chat") {
                Button("Focus Message Input") {
                    NotificationCenter.default.post(name: .focusInput, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Divider()

                Button("Clear Conversation") {
                    NotificationCenter.default.post(name: .clearConversation, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }

            // Add Memory menu
            CommandMenu("Memory") {
                Button("Toggle Memory Panel") {
                    NotificationCenter.default.post(name: .toggleMemoryPanel, object: nil)
                }
                .keyboardShortcut("m", modifiers: .command)
            }

            // Override paste command to handle images while preserving text paste
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    handlePasteCommand()
                }
                .keyboardShortcut("v", modifiers: .command)

                Divider()

                Button("Select All") {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }
        }

        Settings {
            SettingsView().environmentObject(authManager)
        }

        // Memory Panel Window
        Window("Memory Panel", id: "memory-panel") {
            MemoryPanelView()
        }
        .modelContainer(sharedModelContainer)

        // Workspace Panel Window
        Window("Workspace Panel", id: "workspace-panel") {
            WorkspacePanelView()
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 600, height: 700)
    }

    private func handlePasteCommand() {
        let pasteboard = NSPasteboard.general

        // Check for images first (PNG or TIFF, which covers screenshots)
        if let imageData = pasteboard.data(forType: .png) ??
                          pasteboard.data(forType: .tiff) {
            // Post notification with image data
            NotificationCenter.default.post(
                name: .pasteImage,
                object: nil,
                userInfo: ["imageData": imageData]
            )
            return
        }

        // Check for file URLs (but not if it's also a string - prefer text paste)
        if let types = pasteboard.types,
           types.contains(.fileURL),
           !types.contains(.string),
           let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first {
            NotificationCenter.default.post(
                name: .pasteFileURL,
                object: nil,
                userInfo: ["fileURL": url]
            )
            return
        }

        // Fall back to default text paste using system action
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    }

    /// Migrate existing keychain items to new access settings (one-time operation)
    /// This re-saves keys with kSecAttrAccessibleAfterFirstUnlock so they don't prompt
    private func migrateKeychainIfNeeded() async {
        let hasMigrated = UserDefaults.standard.bool(forKey: Self.keychainMigrationKey)
        guard !hasMigrated else { return }

        // This will trigger keychain prompts for existing keys, then re-save them
        // with the new access settings that don't require prompts
        KeychainService.shared.migrateKeysToNewAccessSettings()

        UserDefaults.standard.set(true, forKey: Self.keychainMigrationKey)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newChat = Notification.Name("newChat")
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let focusInput = Notification.Name("focusInput")
    static let clearConversation = Notification.Name("clearConversation")
    static let focusMessageInput = Notification.Name("focusMessageInput")
    static let pasteImage = Notification.Name("pasteImage")
    static let pasteFileURL = Notification.Name("pasteFileURL")
    static let toggleMemoryPanel = Notification.Name("toggleMemoryPanel")
    static let openMemoryWindow = Notification.Name("openMemoryWindow")
}
