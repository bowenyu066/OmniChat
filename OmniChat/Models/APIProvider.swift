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
            return [.gpt5_2Pro, .gpt5_2, .gpt5_1, .gpt5, .gpt5Mini, .gpt4_1, .gpt4o]
        case .anthropic:
            return [.claudeOpus4_5, .claudeSonnet4_5, .claudeHaiku4_5]
        case .google:
            return [.gemini3ProPreview, .gemini3FlashPreview]
        }
    }
}

enum OpenAIReasoningEffort: String, CaseIterable, Codable, Identifiable {
    case auto
    case none
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .none: return "None (instant)"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "xHigh (GPT-5.2-pro only)"
        }
    }
}

enum AIModel: String, CaseIterable, Codable, Identifiable {
    // OpenAI models (2026)
    case gpt5_2Pro = "gpt-5.2-pro"
    case gpt5_2 = "gpt-5.2"
    case gpt5_1 = "gpt-5.1"
    case gpt5 = "gpt-5"
    case gpt5Mini = "gpt-5-mini"
    case gpt4_1 = "gpt-4.1"
    case gpt4o = "gpt-4o"

    // Anthropic models (2025)
    case claudeOpus4_5 = "claude-opus-4-5-20251101"
    case claudeSonnet4_5 = "claude-sonnet-4-5-20250929"
    case claudeHaiku4_5 = "claude-haiku-4-5-20251001"

    // Google models (2026)
    case gemini3ProPreview = "gemini-3-pro-preview"
    case gemini3FlashPreview = "gemini-3-flash-preview"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        // OpenAI
        case .gpt5_2Pro: return "GPT-5.2 Pro"
        case .gpt5_2: return "GPT-5.2"
        case .gpt5_1: return "GPT-5.1"
        case .gpt5: return "GPT-5"
        case .gpt5Mini: return "GPT-5 Mini"
        case .gpt4_1: return "GPT-4.1"
        case .gpt4o: return "GPT-4o"
        // Anthropic
        case .claudeOpus4_5: return "Claude Opus 4.5"
        case .claudeSonnet4_5: return "Claude Sonnet 4.5"
        case .claudeHaiku4_5: return "Claude Haiku 4.5"
        // Google
        case .gemini3ProPreview: return "Gemini 3 Pro (Preview)"
        case .gemini3FlashPreview: return "Gemini 3 Flash (Preview)"
        }
    }

    var provider: AIProvider {
        switch self {
        case .gpt5_2Pro, .gpt5_2, .gpt5_1, .gpt5, .gpt5Mini, .gpt4_1, .gpt4o:
            return .openAI
        case .claudeOpus4_5, .claudeSonnet4_5, .claudeHaiku4_5:
            return .anthropic
        case .gemini3ProPreview, .gemini3FlashPreview:
            return .google
        }
    }

    var supportsReasoningEffort: Bool {
        switch self {
        case .gpt5_2Pro, .gpt5_2, .gpt5_1, .gpt5:
            return true
        default:
            return false
        }
    }

    var supportsXHighReasoningEffort: Bool {
        self == .gpt5_2Pro
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
