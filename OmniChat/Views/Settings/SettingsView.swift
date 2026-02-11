import SwiftUI
import LocalAuthentication
import Combine

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager

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

            ImportDataView()
                .tabItem {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
        }
        .frame(width: 550, height: 450)
        .onDisappear {
            // Clear settings auth when leaving settings
            authManager.clearSettingsAuth()
        }
    }
}

struct APIKeysSettingsView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var openAIKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var googleKey: String = ""

    @State private var isAuthenticated = false
    @State private var isAuthenticating = false
    @State private var authError: String?

    @State private var saveStatus: [AIProvider: SaveStatus] = [:]

    private let keychainService = KeychainService.shared

    enum SaveStatus: Equatable {
        case idle
        case saving
        case saved
        case error(String)
    }

    var body: some View {
        Group {
            if isAuthenticated {
                authenticatedView
            } else {
                unauthenticatedView
            }
        }
        .onAppear {
            checkAuthentication()
        }
    }

    private var unauthenticatedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Authentication Required")
                .font(.title2)
                .fontWeight(.medium)

            Text("Please authenticate to view and manage your API keys.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let error = authError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button(action: authenticate) {
                if isAuthenticating {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Label("Authenticate", systemImage: "touchid")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var authenticatedView: some View {
        Form {
            Section {
                AutoSaveAPIKeyRow(
                    provider: .openAI,
                    placeholder: "sk-...",
                    apiKey: $openAIKey,
                    saveStatus: saveStatus[.openAI] ?? .idle,
                    onSave: { saveKey(.openAI, value: $0) }
                )

                AutoSaveAPIKeyRow(
                    provider: .anthropic,
                    placeholder: "sk-ant-...",
                    apiKey: $anthropicKey,
                    saveStatus: saveStatus[.anthropic] ?? .idle,
                    onSave: { saveKey(.anthropic, value: $0) }
                )

                AutoSaveAPIKeyRow(
                    provider: .google,
                    placeholder: "AIza...",
                    apiKey: $googleKey,
                    saveStatus: saveStatus[.google] ?? .idle,
                    onSave: { saveKey(.google, value: $0) }
                )
            } header: {
                Text("Enter your API keys to enable each provider")
            } footer: {
                Text("Keys are stored securely in your macOS Keychain. Changes are auto-saved.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadKeys()
        }
    }

    private func checkAuthentication() {
        if authManager.isSettingsAuthenticated {
            isAuthenticated = true
        }
    }

    private func authenticate() {
        isAuthenticating = true
        authError = nil

        Task {
            let success = await authManager.authenticateForSettings()
            await MainActor.run {
                isAuthenticating = false
                isAuthenticated = success
                if !success {
                    authError = "Authentication failed. Please try again."
                }
            }
        }
    }

    private func loadKeys() {
        openAIKey = keychainService.getAPIKey(for: .openAI) ?? ""
        anthropicKey = keychainService.getAPIKey(for: .anthropic) ?? ""
        googleKey = keychainService.getAPIKey(for: .google) ?? ""
    }

    private func saveKey(_ provider: AIProvider, value: String) {
        saveStatus[provider] = .saving

        Task {
            do {
                if value.isEmpty {
                    // Delete the key if empty
                    if let key = KeychainService.Key(provider: provider) {
                        try keychainService.delete(key: key)
                    }
                } else {
                    try keychainService.saveAPIKey(value, for: provider)
                }

                await MainActor.run {
                    saveStatus[provider] = .saved
                }

                // Reset to idle after 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    if saveStatus[provider] == .saved {
                        saveStatus[provider] = .idle
                    }
                }
            } catch {
                await MainActor.run {
                    saveStatus[provider] = .error(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Auto-Save API Key Row

struct AutoSaveAPIKeyRow: View {
    let provider: AIProvider
    let placeholder: String
    @Binding var apiKey: String
    let saveStatus: APIKeysSettingsView.SaveStatus
    let onSave: (String) -> Void

    @State private var isSecure = true
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        HStack {
            // Provider label
            Text(provider.displayName)
                .frame(width: 80, alignment: .leading)

            // Key input field
            Group {
                if isSecure {
                    SecureField(placeholder, text: $apiKey)
                } else {
                    TextField(placeholder, text: $apiKey)
                }
            }
            .textFieldStyle(.roundedBorder)
            .onChange(of: apiKey) { _, newValue in
                debounceAndSave(newValue)
            }

            // Toggle visibility
            Button(action: { isSecure.toggle() }) {
                Image(systemName: isSecure ? "eye.slash" : "eye")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(isSecure ? "Show key" : "Hide key")

            // Save status indicator
            saveStatusView
                .frame(width: 70)
        }
    }

    @ViewBuilder
    private var saveStatusView: some View {
        switch saveStatus {
        case .idle:
            EmptyView()
        case .saving:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Saving...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .saved:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Saved")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            .transition(.opacity)
        case .error(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                Text("Error")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .help(message)
        }
    }

    private func debounceAndSave(_ value: String) {
        // Cancel previous debounce task
        debounceTask?.cancel()

        // Create new debounce task (500ms delay)
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                onSave(value)
            }
        }
    }
}

struct GeneralSettingsView: View {
    @AppStorage("default_model") private var defaultModel = "gpt-4o"
    @AppStorage("bubble_color_red") private var bubbleRed: Double = 0.29
    @AppStorage("bubble_color_green") private var bubbleGreen: Double = 0.62
    @AppStorage("bubble_color_blue") private var bubbleBlue: Double = 1.0

    private var bubbleColor: Color {
        Color(red: bubbleRed, green: bubbleGreen, blue: bubbleBlue)
    }

    private var bubbleColorBinding: Binding<Color> {
        Binding(
            get: { bubbleColor },
            set: { newColor in
                if let components = NSColor(newColor).usingColorSpace(.deviceRGB) {
                    bubbleRed = components.redComponent
                    bubbleGreen = components.greenComponent
                    bubbleBlue = components.blueComponent
                }
            }
        )
    }
    @ObservedObject private var updateService = UpdateCheckService.shared
    @State private var autoCheckEnabled: Bool = UserDefaults.standard.autoCheckForUpdates
    @State private var checkFrequency: String = UserDefaults.standard.updateCheckFrequency

    var body: some View {
        Form {
            Section("Model") {
                Picker("Default Model", selection: $defaultModel) {
                    ForEach(AIModel.allCases) { model in
                        Text(model.displayName).tag(model.rawValue)
                    }
                }
            }

            Section("Appearance") {
                ColorPicker("Message bubble color", selection: bubbleColorBinding, supportsOpacity: false)
                Text("Changes the color of your outgoing message bubbles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $autoCheckEnabled)
                    .onChange(of: autoCheckEnabled) { _, newValue in
                        UserDefaults.standard.autoCheckForUpdates = newValue
                    }

                Picker("Check frequency", selection: $checkFrequency) {
                    Text("On startup").tag("onStartup")
                    Text("Daily").tag("daily")
                    Text("Weekly").tag("weekly")
                }
                .pickerStyle(.radioGroup)
                .disabled(!autoCheckEnabled)
                .onChange(of: checkFrequency) { _, newValue in
                    UserDefaults.standard.updateCheckFrequency = newValue
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let lastCheck = updateService.lastCheckDate {
                            Text("Last checked: \(formattedDate(lastCheck))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Never checked")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let update = updateService.availableUpdate {
                            Text("Version \(update.version) is available")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    Spacer()

                    Button {
                        Task {
                            await updateService.checkForUpdates(silent: false)
                        }
                    } label: {
                        if updateService.isChecking {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Text("Check Now")
                        }
                    }
                    .disabled(updateService.isChecking)
                }

                if let update = updateService.availableUpdate {
                    HStack {
                        Text("Version \(update.version) available")
                            .foregroundColor(.green)
                        Spacer()
                        Button("Download") {
                            NSWorkspace.shared.open(update.downloadURL)
                        }
                    }
                }
            }

            #if DEBUG
            Section("Debug / Testing") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Update Banner Testing")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack {
                        Button("Show Mock Update") {
                            updateService.showMockUpdate()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Clear Update") {
                            updateService.clearUpdate()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("Use these buttons to test the update banner without needing a real GitHub release.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            #endif
        }
        .formStyle(.grouped)
        .padding()
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
}
