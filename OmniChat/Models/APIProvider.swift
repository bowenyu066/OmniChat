import Foundation

enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case google = "Google"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "ChatGPT"
        case .anthropic: return "Claude"
        case .google: return "Gemini"
        }
    }

    var availableModels: [AIModel] {
        switch self {
        case .openAI:
            return [.gpt4_1, .gpt4_1Mini, .gpt4o, .o4Mini, .o3Mini]
        case .anthropic:
            return [.claudeOpus4_5, .claudeSonnet4_5, .claudeHaiku4_5]
        case .google:
            return [.gemini2_5Pro, .gemini2_5Flash, .gemini2_5FlashLite]
        }
    }
}

enum AIModel: String, CaseIterable, Codable, Identifiable {
    // OpenAI models (2025)
    case gpt4_1 = "gpt-4.1"
    case gpt4_1Mini = "gpt-4.1-mini"
    case gpt4o = "gpt-4o"
    case o4Mini = "o4-mini"
    case o3Mini = "o3-mini"

    // Anthropic models (2025)
    case claudeOpus4_5 = "claude-opus-4-5-20251101"
    case claudeSonnet4_5 = "claude-sonnet-4-5-20250929"
    case claudeHaiku4_5 = "claude-haiku-4-5-20250929"

    // Google models (2025)
    case gemini2_5Pro = "gemini-2.5-pro"
    case gemini2_5Flash = "gemini-2.5-flash"
    case gemini2_5FlashLite = "gemini-2.5-flash-lite"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        // OpenAI
        case .gpt4_1: return "GPT-4.1"
        case .gpt4_1Mini: return "GPT-4.1 Mini"
        case .gpt4o: return "GPT-4o"
        case .o4Mini: return "o4-mini"
        case .o3Mini: return "o3-mini"
        // Anthropic
        case .claudeOpus4_5: return "Claude Opus 4.5"
        case .claudeSonnet4_5: return "Claude Sonnet 4.5"
        case .claudeHaiku4_5: return "Claude Haiku 4.5"
        // Google
        case .gemini2_5Pro: return "Gemini 2.5 Pro"
        case .gemini2_5Flash: return "Gemini 2.5 Flash"
        case .gemini2_5FlashLite: return "Gemini 2.5 Flash-Lite"
        }
    }

    var provider: AIProvider {
        switch self {
        case .gpt4_1, .gpt4_1Mini, .gpt4o, .o4Mini, .o3Mini:
            return .openAI
        case .claudeOpus4_5, .claudeSonnet4_5, .claudeHaiku4_5:
            return .anthropic
        case .gemini2_5Pro, .gemini2_5Flash, .gemini2_5FlashLite:
            return .google
        }
    }
}

struct ProviderConfig: Codable, Identifiable {
    var id: UUID = UUID()
    var provider: AIProvider
    var isEnabled: Bool
    var selectedModel: AIModel

    init(provider: AIProvider, isEnabled: Bool = false, selectedModel: AIModel? = nil) {
        self.provider = provider
        self.isEnabled = isEnabled
        self.selectedModel = selectedModel ?? provider.availableModels.first!
    }
}
