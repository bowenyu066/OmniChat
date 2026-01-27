import SwiftUI
import SwiftData

@main
struct OmniChatApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Conversation.self,
            Message.self,
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
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newChat = Notification.Name("newChat")
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let focusInput = Notification.Name("focusInput")
    static let clearConversation = Notification.Name("clearConversation")
}
