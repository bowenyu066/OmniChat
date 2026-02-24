import SwiftUI
import SwiftData
import AppKit
import LocalAuthentication

final class AuthManager: ObservableObject {
    private enum DefaultsKeys {
        static let lastAuthTime = "last_auth_time"
        static let requireAppUnlockOnLaunch = "require_app_unlock_on_launch"
        static let appUnlockGraceDays = "app_unlock_grace_days"
    }

    // Session-based auth for settings (valid while settings window is open)
    @Published var isSettingsAuthenticated = false

    private var lastAuthTime: Double {
        get { UserDefaults.standard.double(forKey: DefaultsKeys.lastAuthTime) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKeys.lastAuthTime) }
    }

    private var requireAppUnlockOnLaunch: Bool {
        if UserDefaults.standard.object(forKey: DefaultsKeys.requireAppUnlockOnLaunch) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: DefaultsKeys.requireAppUnlockOnLaunch)
    }

    private var graceInterval: TimeInterval {
        let configuredDays = UserDefaults.standard.integer(forKey: DefaultsKeys.appUnlockGraceDays)
        let graceDays = [1, 7, 30].contains(configuredDays) ? configuredDays : 30
        return TimeInterval(graceDays * 24 * 60 * 60)
    }

    var needsAppUnlock: Bool {
        guard requireAppUnlockOnLaunch else { return false }
        let now = Date().timeIntervalSince1970
        return lastAuthTime == 0 || (now - lastAuthTime) > graceInterval
    }

    func markAppAuthenticated() {
        lastAuthTime = Date().timeIntervalSince1970
    }

    /// Authenticate for app startup based on user settings.
    @MainActor
    func authenticateAppIfNeeded() async -> Bool {
        guard requireAppUnlockOnLaunch else { return true }
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
    @StateObject private var updateService = UpdateCheckService.shared

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
                        // Authenticate app if needed (based on startup unlock settings).
                        _ = await authManager.authenticateAppIfNeeded()

                        // Do not touch keychain on startup to avoid repeated password prompts.
                        // Keychain access is now demand-driven (API use / API Keys settings).

                        // Check for updates if enabled
                        await performStartupUpdateCheck()
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

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task {
                        await updateService.checkForUpdates(silent: false)
                    }
                }
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
        .modelContainer(sharedModelContainer)

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

    /// Check for updates on app startup based on user preferences
    private func performStartupUpdateCheck() async {
        let autoCheck = UserDefaults.standard.autoCheckForUpdates
        guard autoCheck else { return }

        let frequency = UserDefaults.standard.updateCheckFrequency
        let lastCheck = UserDefaults.standard.lastUpdateCheckDate

        let shouldCheck: Bool = {
            switch frequency {
            case "onStartup":
                return true
            case "daily":
                return lastCheck == nil || lastCheck!.timeIntervalSinceNow < -86400
            case "weekly":
                return lastCheck == nil || lastCheck!.timeIntervalSinceNow < -604800
            default:
                return true
            }
        }()

        if shouldCheck {
            await updateService.checkForUpdates(silent: true)
        }
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
