import SwiftUI
import SwiftData
import AVFoundation

struct MessageView: View {
    @Environment(\.modelContext) private var modelContext

    let message: Message
    var isStreaming: Bool = false
    var streamingContent: String? = nil  // Override content during streaming (avoids SwiftData triggers)
    var siblings: [Message] = []  // All sibling messages (including this one)
    var thinkingDuration: TimeInterval? = nil  // How long model "thought" before first token
    var onRetry: (() -> Void)?
    var onSwitchModel: ((AIModel) -> Void)?
    var onBranch: (() -> Void)?
    var onSwitchSibling: ((Message) -> Void)?
    var onEdit: ((String) -> Void)?  // For editing user messages
    var isContextInspectorVisible: Bool = false
    var onShowContextInspector: (() -> Void)? = nil
    var onCloseContextInspector: (() -> Void)? = nil

    @AppStorage("bubble_color_red") private var bubbleRed: Double = 0.29
    @AppStorage("bubble_color_green") private var bubbleGreen: Double = 0.62
    @AppStorage("bubble_color_blue") private var bubbleBlue: Double = 1.0

    @State private var isEditing = false
    @State private var editedContent = ""

    /// Content to display - uses streaming buffer if available, otherwise message content
    private var displayContent: String {
        streamingContent ?? message.content
    }

    @State private var showingSaveToMemory = false
    @State private var isSpeaking = false
    @State private var showModelPicker = false

    private var isUser: Bool {
        message.role == .user
    }

    private var contextSnapshot: ResponseContextSnapshot? {
        message.contextSnapshot
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            // Header: timestamp for user, model name/timing for assistant, and sibling nav when branching exists
            HStack(spacing: 6) {
                if !isUser {
                    Text(modelDisplayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    // Thinking duration badge
                    if let duration = thinkingDuration, !isStreaming {
                        Text("· thought for \(formattedDuration(duration))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Assistant sibling nav stays before timestamp
                if !isUser && siblings.count > 1 {
                    SiblingNavigator(
                        currentMessage: message,
                        siblings: siblings,
                        onSwitch: onSwitchSibling
                    )
                }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // User sibling nav appears beside timestamp after edit-branching
                if isUser && siblings.count > 1 {
                    SiblingNavigator(
                        currentMessage: message,
                        siblings: siblings,
                        onSwitch: onSwitchSibling
                    )
                }
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
                    if isEditing {
                        // Edit mode
                        VStack(alignment: .trailing, spacing: 8) {
                            TextEditor(text: $editedContent)
                                .font(.body)
                                .frame(minHeight: 60, maxHeight: 200)
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.accentColor, lineWidth: 2)
                                )

                            HStack(spacing: 8) {
                                Button("Cancel") {
                                    isEditing = false
                                }
                                .buttonStyle(.bordered)

                                Button("Save") {
                                    let trimmed = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty && trimmed != message.content {
                                        onEdit?(trimmed)
                                    }
                                    isEditing = false
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .frame(maxWidth: 500)
                    } else {
                        // Normal display mode
                        Text(message.content)
                            .font(.body)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(userMessageBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .foregroundStyle(.white)

                        // Action buttons for user messages
                        HStack(spacing: 4) {
                            // Copy button
                            ActionButton(icon: "doc.on.doc", tooltip: "Copy") {
                                copyToClipboard()
                            }

                            // Edit button
                            if onEdit != nil {
                                ActionButton(icon: "pencil", tooltip: "Edit message") {
                                    editedContent = message.content
                                    isEditing = true
                                }
                            }
                        }
                    }
                }
            } else {
                // Assistant messages: use lightweight text while streaming to reduce CPU.
                if isStreaming {
                    Text(displayContent)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    MarkdownView(content: displayContent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                // Action buttons for assistant messages
                if !displayContent.isEmpty && !isStreaming {
                    MessageActionBar(
                        onCopy: copyToClipboard,
                        onAudio: toggleSpeech,
                        onRetry: onRetry,
                        onSwitchModel: { showModelPicker = true },
                        onBranch: onBranch,
                        onSaveToMemory: { showingSaveToMemory = true },
                        onShowContext: contextSnapshot?.hasAnyContext == true ? onShowContextInspector : nil,
                        isSpeaking: isSpeaking
                    )

                    if isContextInspectorVisible, let contextSnapshot {
                        ResponseContextInspectorView(
                            snapshot: contextSnapshot,
                            onClose: onCloseContextInspector
                        )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
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
        pasteboard.setString(displayContent, forType: .string)
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
        let base = Color(red: bubbleRed, green: bubbleGreen, blue: bubbleBlue)
        return LinearGradient(
            colors: [base, base.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var modelDisplayName: String {
        guard let modelUsed = message.modelUsed else { return "Assistant" }
        return AIModel(rawValue: modelUsed)?.displayName ?? modelUsed
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else {
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return secs > 0 ? "\(mins)min \(secs)s" : "\(mins)min"
        }
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
    let onShowContext: (() -> Void)?
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

            if let onShowContext = onShowContext {
                ActionButton(icon: "line.3.horizontal.decrease.circle", tooltip: "Show context used") {
                    onShowContext()
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

private struct ResponseContextInspectorView: View {
    let snapshot: ResponseContextSnapshot
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Context Used")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
                Text(snapshot.generatedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if snapshot.includesTimeContext {
                contextBadge("Current time injected")
            }

            if !snapshot.memoryItems.isEmpty {
                contextSection(title: "Memories", count: snapshot.memoryItems.count) {
                    ForEach(snapshot.memoryItems, id: \.id) { item in
                        Text("• [\(item.type)] \(item.title)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if !snapshot.ragItems.isEmpty {
                contextSection(title: "Past chats", count: snapshot.ragItems.count) {
                    ForEach(Array(snapshot.ragItems.enumerated()), id: \.offset) { _, item in
                        Text("• \(item.conversationTitle)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if !snapshot.workspaceItems.isEmpty {
                contextSection(title: "Workspace snippets", count: snapshot.workspaceItems.count) {
                    ForEach(Array(snapshot.workspaceItems.enumerated()), id: \.offset) { _, item in
                        Text("• \(item.citation)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func contextSection<Content: View>(title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) (\(count))")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary.opacity(0.8))
            content()
        }
    }

    private func contextBadge(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.14))
            .clipShape(Capsule())
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

// MARK: - Sibling Navigator

struct SiblingNavigator: View {
    let currentMessage: Message
    let siblings: [Message]
    var onSwitch: ((Message) -> Void)?

    private var currentIndex: Int {
        siblings.firstIndex(where: { $0.id == currentMessage.id }) ?? 0
    }

    private var canGoBack: Bool {
        currentIndex > 0
    }

    private var canGoForward: Bool {
        currentIndex < siblings.count - 1
    }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: goToPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(canGoBack ? .secondary : .secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)

            Text("\(currentIndex + 1)/\(siblings.count)")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: goToNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(canGoForward ? .secondary : .secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
    }

    private func goToPrevious() {
        guard canGoBack else { return }
        onSwitch?(siblings[currentIndex - 1])
    }

    private func goToNext() {
        guard canGoForward else { return }
        onSwitch?(siblings[currentIndex + 1])
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
