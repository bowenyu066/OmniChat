import SwiftUI

struct ModelSelectorView: View {
    @Binding var selectedModel: AIModel

    var body: some View {
        HStack {
            Spacer()

            Menu {
                ForEach(AIProvider.allCases) { provider in
                    Section {
                        ForEach(provider.availableModels) { model in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedModel = model
                                }
                            } label: {
                                HStack {
                                    Text(model.displayName)
                                    Spacer()
                                    if model == selectedModel {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    } header: {
                        Label(provider.displayName, systemImage: provider.iconName)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    // Provider indicator dot
                    Circle()
                        .fill(selectedModel.provider.color)
                        .frame(width: 8, height: 8)

                    Text(selectedModel.displayName)
                        .fontWeight(.medium)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .help("Select AI model")

            Spacer()
        }
    }
}

extension AIProvider {
    var iconName: String {
        switch self {
        case .openAI: return "sparkles"
        case .anthropic: return "brain.head.profile"
        case .google: return "globe"
        }
    }

    var color: Color {
        switch self {
        case .openAI: return .green
        case .anthropic: return .orange
        case .google: return .blue
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ModelSelectorView(selectedModel: .constant(.gpt4_1))
        ModelSelectorView(selectedModel: .constant(.claudeOpus4_5))
        ModelSelectorView(selectedModel: .constant(.gemini2_5Pro))
    }
    .padding()
    .frame(width: 400)
}
