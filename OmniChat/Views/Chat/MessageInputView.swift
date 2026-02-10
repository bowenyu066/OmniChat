import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Message Input View

struct MessageInputView: View {
    @Binding var text: String
    @Binding var pendingAttachments: [PendingAttachment]
    let isLoading: Bool
    let onSend: () -> Void

    @State private var isDropTargeted = false
    @State private var attachmentError: String?
    @State private var textViewHeight: CGFloat = 36

    private let minHeight: CGFloat = 36
    private let maxHeight: CGFloat = 150

    var body: some View {
        VStack(spacing: 8) {
            // Attachment previews
            if !pendingAttachments.isEmpty {
                AttachmentPreviewRow(attachments: $pendingAttachments)
            }

            // Error message
            if let error = attachmentError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        attachmentError = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                .padding(.horizontal, 8)
            }

            // Input row
            HStack(alignment: .bottom, spacing: 12) {
                // Attachment button
                Button(action: openFilePicker) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add image or PDF (⌘⇧A)")
                .keyboardShortcut("a", modifiers: [.command, .shift])

                // Microphone button for voice input
                AudioRecorderButton { transcribedText in
                    // Append transcribed text to input (add space if needed)
                    if text.isEmpty {
                        text = transcribedText
                    } else if text.hasSuffix(" ") || text.hasSuffix("\n") {
                        text += transcribedText
                    } else {
                        text += " " + transcribedText
                    }
                }

                // Custom text input - Now includes internal ScrollView logic
                BareTextView(
                    text: $text,
                    height: $textViewHeight,
                    minHeight: minHeight,
                    maxHeight: maxHeight,
                    placeholder: "Message...",
                    onSubmit: {
                        if canSend {
                            onSend()
                        }
                    }
                )
                .frame(height: textViewHeight)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.2),
                            lineWidth: isDropTargeted ? 2 : 1
                        )
                )

                // Send button
                Button(action: {
                    if canSend {
                        onSend()
                    }
                }) {
                    Image(systemName: isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend || isLoading ? Color.accentColor : Color.secondary.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !isLoading)
                .help(isLoading ? "Stop generating" : "Send message (↩)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusMessageInput)) { _ in
            NotificationCenter.default.post(name: .focusBareTextView, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteImage)) { notification in
            if let imageData = notification.userInfo?["imageData"] as? Data {
                handlePastedImage(imageData)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteFileURL)) { notification in
            if let fileURL = notification.userInfo?["fileURL"] as? URL {
                addAttachment(from: fileURL)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !pendingAttachments.isEmpty
        return (hasText || hasAttachments) && !isLoading
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.jpeg, .png, .gif, .webP, .pdf]
        panel.message = "Select images or PDFs to attach"

        if panel.runModal() == .OK {
            for url in panel.urls {
                addAttachment(from: url)
            }
        }
    }

    private func addAttachment(from url: URL) {
        do {
            let attachment = try PendingAttachment.from(url: url)
            withAnimation(.easeIn(duration: 0.2)) {
                pendingAttachments.append(attachment)
            }
            attachmentError = nil
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            addAttachment(from: url)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data = data {
                        DispatchQueue.main.async {
                            handlePastedImage(data)
                        }
                    }
                }
            }
        }
        return true
    }

    private func handlePastedImage(_ data: Data) {
        do {
            let attachment = try PendingAttachment.from(imageData: data)
            withAnimation(.easeIn(duration: 0.2)) {
                pendingAttachments.append(attachment)
            }
            attachmentError = nil
        } catch {
            attachmentError = error.localizedDescription
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let focusBareTextView = Notification.Name("focusBareTextView")
}

// MARK: - Bare NSTextView (Wrapped in ScrollView)

struct BareTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let placeholder: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> PassthroughContainerView {
        let container = PassthroughContainerView()

        // 1. Create NSScrollView
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        // 2. Create NSTextView
        let textView = PassthroughTextView()
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        
        // 3. Configure Resizing
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 8, height: 8)
        
        textView.placeholderString = placeholder
        textView.onSubmit = onSubmit

        // 4. Hook up ScrollView
        scrollView.documentView = textView
        container.addSubview(scrollView)
        
        // 5. Store References
        // Note: We assign the textView to the container so it can find it,
        // but the actual view hierarchy is Container -> ScrollView -> TextView
        container.textView = textView
        context.coordinator.textView = textView
        context.coordinator.container = container

        // 6. Setup Constraints (ScrollView fills Container)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        // Focus
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        context.coordinator.setupFocusListener()

        return container
    }

    func updateNSView(_ container: PassthroughContainerView, context: Context) {
        guard let textView = container.textView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.updateHeight()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BareTextView
        weak var textView: PassthroughTextView?
        weak var container: PassthroughContainerView?
        private var focusObserver: Any?

        init(_ parent: BareTextView) {
            self.parent = parent
        }

        deinit {
            if let observer = focusObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func setupFocusListener() {
            focusObserver = NotificationCenter.default.addObserver(
                forName: .focusBareTextView,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.textView?.window?.makeFirstResponder(self?.textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateHeight()
        }

        func updateHeight() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            
            // We add a little padding (e.g. 16) to ensure text doesn't feel cramped
            let newHeight = min(max(usedRect.height + 16, parent.minHeight), parent.maxHeight)

            DispatchQueue.main.async {
                self.parent.height = newHeight
            }
        }
    }
}

// MARK: - Container that forwards scroll events to chat scroll view

class PassthroughContainerView: NSView {
    weak var textView: PassthroughTextView?
    private weak var cachedScrollView: NSScrollView?

    override func scrollWheel(with event: NSEvent) {
        if cachedScrollView == nil {
            cachedScrollView = findChatScrollView()
        }
        if let sv = cachedScrollView {
            sv.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }

    private func findChatScrollView() -> NSScrollView? {
        var current: NSView? = superview
        while let view = current {
            if let found = searchForScrollView(in: view) {
                return found
            }
            current = view.superview
        }
        return nil
    }

    private func searchForScrollView(in view: NSView) -> NSScrollView? {
        // Don't search in self
        if view === self || self.isDescendant(of: view) && view !== superview {
            return nil
        }
        if let sv = view as? NSScrollView {
            return sv
        }
        for subview in view.subviews {
            if subview === self || self.isDescendant(of: subview) {
                continue
            }
            if let found = searchForScrollView(in: subview) {
                return found
            }
        }
        return nil
    }
}

// MARK: - NSTextView that conditionally forwards scroll events

class PassthroughTextView: NSTextView {
    var placeholderString: String = ""
    var onSubmit: (() -> Void)?
    weak var coordinator: BareTextView.Coordinator?

    override func scrollWheel(with event: NSEvent) {
        // 1. Calculate content height vs visible height
        let contentHeight = layoutManager?.usedRect(for: textContainer!).height ?? 0
        let visibleHeight = enclosingScrollView?.contentSize.height ?? bounds.height
        
        // 2. Check if content is overflowing (add small buffer for float precision)
        let isContentOverflowing = contentHeight > (visibleHeight + 1)

        if isContentOverflowing {
            // If text is taller than the view, let NSTextView/NSScrollView handle it
            super.scrollWheel(with: event)
        } else {
            // If text fits perfectly, forward scroll to the container (which finds the chat)
            if let scrollView = enclosingScrollView,
               let container = scrollView.superview as? PassthroughContainerView {
                container.scrollWheel(with: event)
            } else {
                nextResponder?.scrollWheel(with: event)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw placeholder if empty
        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: font ?? .systemFont(ofSize: 14)
            ]
            let rect = NSRect(
                x: textContainerInset.width + 4,
                y: textContainerInset.height,
                width: bounds.width - textContainerInset.width * 2,
                height: bounds.height - textContainerInset.height * 2
            )
            placeholderString.draw(in: rect, withAttributes: attrs)
        }
    }

    override func keyDown(with event: NSEvent) {
        // Enter without shift = submit
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }
}
