import SwiftUI
import SwiftData
import AVFoundation

struct MessageView: View {
    @Environment(\.modelContext) private var modelContext

    let message: Message
    var onRetry: (() -> Void)?
    var onSwitchModel: ((AIModel) -> Void)?
    var onBranch: (() -> Void)?

    @State private var showingSaveToMemory = false
    @State private var isSpeaking = false
    @State private var showModelPicker = false

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            // Header: timestamp for user, model name + timestamp for assistant
            HStack(spacing: 6) {
                if !isUser {
                    Text(modelDisplayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Attachments (if any)
            if message.hasAttachments {
                VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                    ForEach(message.attachments, id: \.id) { attachment in
                        AttachmentDisplayView(attachment: attachment)
                    }
                }
            }

            // Message content
            if isUser {
                // User messages: plain text with bubble (only if there's text)
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(userMessageBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .foregroundStyle(.white)

                    // Copy button for user messages
                    Button(action: copyToClipboard) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                }
            } else {
                // Assistant messages: markdown rendering
                MarkdownView(content: message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                // Action buttons for assistant messages
                if !message.content.isEmpty {
                    MessageActionBar(
                        onCopy: copyToClipboard,
                        onAudio: toggleSpeech,
                        onRetry: onRetry,
                        onSwitchModel: { showModelPicker = true },
                        onBranch: onBranch,
                        onSaveToMemory: { showingSaveToMemory = true },
                        isSpeaking: isSpeaking
                    )
                }
            }
        }
        .frame(maxWidth: isUser ? 500 : .infinity, alignment: isUser ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.horizontal, 20)
        .contextMenu {
            if !isUser && !message.content.isEmpty {
                Button(action: { showingSaveToMemory = true }) {
                    Label("Save to Memory", systemImage: "brain.head.profile")
                }
            }

            Button(action: copyToClipboard) {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        .sheet(isPresented: $showingSaveToMemory) {
            let firstLine = message.content.components(separatedBy: .newlines).first ?? "Memory"
            let title = firstLine.prefix(50).trimmingCharacters(in: .whitespaces)
            MemoryEditorView(
                initialTitle: String(title),
                initialBody: message.content,
                sourceMessageId: message.id
            )
        }
        .popover(isPresented: $showModelPicker) {
            ModelPickerPopover(onSelect: { model in
                showModelPicker = false
                onSwitchModel?(model)
            })
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.content, forType: .string)
    }

    private func toggleSpeech() {
        if isSpeaking {
            SpeechService.shared.stop()
            isSpeaking = false
        } else {
            isSpeaking = true
            SpeechService.shared.speak(message.content) {
                isSpeaking = false
            }
        }
    }

    private var userMessageBackground: some ShapeStyle {
        LinearGradient(
            colors: [Color.blue, Color.blue.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var modelDisplayName: String {
        guard let modelUsed = message.modelUsed else { return "Assistant" }
        return AIModel(rawValue: modelUsed)?.displayName ?? modelUsed
    }
}

// MARK: - Message Action Bar

struct MessageActionBar: View {
    let onCopy: () -> Void
    let onAudio: () -> Void
    let onRetry: (() -> Void)?
    let onSwitchModel: () -> Void
    let onBranch: (() -> Void)?
    let onSaveToMemory: () -> Void
    let isSpeaking: Bool

    var body: some View {
        HStack(spacing: 4) {
            ActionButton(icon: "doc.on.doc", tooltip: "Copy") {
                onCopy()
            }

            ActionButton(icon: isSpeaking ? "speaker.slash" : "speaker.wave.2", tooltip: isSpeaking ? "Stop" : "Read aloud") {
                onAudio()
            }

            if let onRetry = onRetry {
                ActionButton(icon: "arrow.clockwise", tooltip: "Retry with current model") {
                    onRetry()
                }
            }

            ActionButton(icon: "arrow.triangle.swap", tooltip: "Switch model") {
                onSwitchModel()
            }

            if let onBranch = onBranch {
                ActionButton(icon: "arrow.branch", tooltip: "Branch to new chat") {
                    onBranch()
                }
            }

            Spacer()

            ActionButton(icon: "brain.head.profile", tooltip: "Save to memory") {
                onSaveToMemory()
            }
        }
        .padding(.top, 4)
    }
}

struct ActionButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(isHovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip)
    }
}

// MARK: - Model Picker Popover

struct ModelPickerPopover: View {
    let onSelect: (AIModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Switch to model:")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)

            ForEach(AIModel.allCases, id: \.self) { model in
                Button(action: { onSelect(model) }) {
                    HStack {
                        Text(model.displayName)
                        Spacer()
                        Text(model.provider.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 200)
    }
}

// MARK: - Speech Service

class SpeechService {
    static let shared = SpeechService()

    private let synthesizer = NSSpeechSynthesizer()
    private var completion: (() -> Void)?

    private init() {}

    func speak(_ text: String, completion: @escaping () -> Void) {
        self.completion = completion
        synthesizer.delegate = SpeechDelegate(onFinish: {
            DispatchQueue.main.async {
                self.completion?()
                self.completion = nil
            }
        })
        synthesizer.startSpeaking(text)
    }

    func stop() {
        synthesizer.stopSpeaking()
        completion?()
        completion = nil
    }
}

private class SpeechDelegate: NSObject, NSSpeechSynthesizerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        onFinish()
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            MessageView(message: Message(role: .user, content: "Can you show me a Python function?"))
            MessageView(
                message: Message(role: .assistant, content: """
                Sure! Here's a simple Python function:

                ```python
                def greet(name):
                    return f"Hello, {name}!"

                # Usage
                print(greet("World"))
                ```

                This function takes a `name` parameter and returns a greeting string.
                """, modelUsed: "gpt-4.1"),
                onRetry: { print("Retry") },
                onSwitchModel: { model in print("Switch to \(model)") },
                onBranch: { print("Branch") }
            )
        }
        .padding()
    }
    .frame(width: 700, height: 500)
}
