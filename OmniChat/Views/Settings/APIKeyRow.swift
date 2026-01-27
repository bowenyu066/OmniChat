import SwiftUI

struct APIKeyRow: View {
    let provider: String
    let placeholder: String
    @Binding var apiKey: String
    var onSave: (() -> Void)? = nil

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(provider)
                .frame(width: 100, alignment: .leading)

            Group {
                if isRevealed {
                    TextField(placeholder, text: $apiKey)
                } else {
                    SecureField(placeholder, text: $apiKey)
                }
            }
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit {
                onSave?()
            }
            .onChange(of: isFocused) { _, newValue in
                if !newValue {
                    onSave?()
                }
            }

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(isRevealed ? "Hide API key" : "Show API key")

            // Status indicator
            if apiKey.isEmpty {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
                    .help("No API key configured")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("API key configured")
            }
        }
    }
}

#Preview {
    Form {
        APIKeyRow(provider: "OpenAI", placeholder: "sk-...", apiKey: .constant(""))
        APIKeyRow(provider: "Anthropic", placeholder: "sk-ant-...", apiKey: .constant("test-key"))
    }
    .padding()
}
