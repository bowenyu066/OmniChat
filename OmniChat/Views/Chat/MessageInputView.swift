import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool
    @State private var textEditorHeight: CGFloat = 40

    private let minHeight: CGFloat = 40
    private let maxHeight: CGFloat = 200
    private let placeholder = "Message..."

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            // Text input area
            ZStack(alignment: .topLeading) {
                // Placeholder
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }

                // Hidden text for height calculation
                Text(text.isEmpty ? placeholder : text)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .opacity(0)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(
                            key: TextHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    })

                // Actual text editor
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .focused($isFocused)
            }
            .frame(height: min(max(textEditorHeight, minHeight), maxHeight))
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .onPreferenceChange(TextHeightPreferenceKey.self) { height in
                textEditorHeight = height
            }
            .onAppear {
                isFocused = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusMessageInput)) { _ in
                isFocused = true
            }

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

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }
}

private struct TextHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 40
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    VStack {
        MessageInputView(
            text: .constant(""),
            isLoading: false,
            onSend: {}
        )

        MessageInputView(
            text: .constant("Hello, this is a test message that should expand the text area as it grows longer and wraps to multiple lines."),
            isLoading: false,
            onSend: {}
        )

        MessageInputView(
            text: .constant("Loading..."),
            isLoading: true,
            onSend: {}
        )
    }
    .padding()
    .frame(width: 500)
}
