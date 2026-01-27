import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct MessageInputView: View {
    @Binding var text: String
    @Binding var pendingAttachments: [PendingAttachment]
    let isLoading: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool
    @State private var isDropTargeted = false
    @State private var attachmentError: String?

    private let maxLineLimit: Int = 8

    var body: some View {
        VStack(spacing: 8) {
            // Attachment previews
            AttachmentPreviewRow(attachments: $pendingAttachments)

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
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Add image or PDF (⌘⇧A)")
                .keyboardShortcut("a", modifiers: [.command, .shift])

                // Text input
                TextField("Message...", text: $text, axis: .vertical)
                    .lineLimit(1...maxLineLimit)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isDropTargeted ? Color.accentColor : (isFocused ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2)),
                                lineWidth: isDropTargeted ? 2 : 1
                            )
                    )
                    .focused($isFocused)

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
                .keyboardShortcut(.return, modifiers: .command)
                .help(isLoading ? "Stop generating" : "Send message (⌘↩)")
            }
        }
        .onAppear {
            isFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusMessageInput)) { _ in
            isFocused = true
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
        panel.allowedContentTypes = [
            .jpeg, .png, .gif, .webP, .pdf
        ]
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
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            addAttachment(from: url)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    if let data = data {
                        DispatchQueue.main.async {
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

#Preview {
    VStack(spacing: 20) {
        MessageInputView(
            text: .constant(""),
            pendingAttachments: .constant([]),
            isLoading: false,
            onSend: {}
        )

        MessageInputView(
            text: .constant("Hello, this fits nicely."),
            pendingAttachments: .constant([]),
            isLoading: false,
            onSend: {}
        )

        MessageInputView(
            text: .constant("With attachments"),
            pendingAttachments: .constant([
                PendingAttachment(type: .image, mimeType: "image/png", data: Data(), filename: "image.png"),
                PendingAttachment(type: .pdf, mimeType: "application/pdf", data: Data(), filename: "doc.pdf")
            ]),
            isLoading: false,
            onSend: {}
        )
    }
    .padding()
    .frame(width: 400)
    .background(Color.gray.opacity(0.1))
}
