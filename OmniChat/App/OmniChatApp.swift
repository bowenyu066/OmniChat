import SwiftUI
import SwiftData
import AppKit

@main
struct OmniChatApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Conversation.self,
            Message.self,
            Attachment.self,
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
            SettingsView()
        }
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
}
