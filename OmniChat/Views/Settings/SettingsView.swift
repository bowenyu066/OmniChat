import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            APIKeysSettingsView()
                .tabItem {
                    Label("API Keys", systemImage: "key")
                }

            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 550, height: 350)
    }
}

struct APIKeysSettingsView: View {
    @State private var openAIKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var googleKey: String = ""
    @State private var showSaveConfirmation = false

    private let keychainService = KeychainService.shared

    var body: some View {
        Form {
            Section {
                APIKeyRow(
                    provider: "OpenAI",
                    placeholder: "sk-...",
                    apiKey: $openAIKey,
                    onSave: { saveKey(.openAI, value: openAIKey) }
                )

                APIKeyRow(
                    provider: "Anthropic",
                    placeholder: "sk-ant-...",
                    apiKey: $anthropicKey,
                    onSave: { saveKey(.anthropic, value: anthropicKey) }
                )

                APIKeyRow(
                    provider: "Google AI",
                    placeholder: "AIza...",
                    apiKey: $googleKey,
                    onSave: { saveKey(.google, value: googleKey) }
                )
            } header: {
                Text("Enter your API keys to enable each provider")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keys are stored securely in your macOS Keychain.")
                        .foregroundStyle(.secondary)

                    if showSaveConfirmation {
                        Text("Key saved!")
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadKeys()
        }
    }

    private func loadKeys() {
        openAIKey = keychainService.getAPIKey(for: .openAI) ?? ""
        anthropicKey = keychainService.getAPIKey(for: .anthropic) ?? ""
        googleKey = keychainService.getAPIKey(for: .google) ?? ""
    }

    private func saveKey(_ provider: AIProvider, value: String) {
        do {
            try keychainService.saveAPIKey(value, for: provider)
            withAnimation {
                showSaveConfirmation = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showSaveConfirmation = false
                }
            }
        } catch {
            print("Failed to save key: \(error)")
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage("default_model") private var defaultModel = "gpt-4o"

    var body: some View {
        Form {
            Picker("Default Model", selection: $defaultModel) {
                ForEach(AIModel.allCases) { model in
                    Text(model.displayName).tag(model.rawValue)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
}
