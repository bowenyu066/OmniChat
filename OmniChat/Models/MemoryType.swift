import Foundation

/// Types of memory that can be stored
enum MemoryType: String, Codable, CaseIterable {
    case fact = "Fact"
    case preference = "Preference"
    case project = "Project"
    case instruction = "Instruction"
    case reference = "Reference"

    /// Icon representation for UI
    var icon: String {
        switch self {
        case .fact: return "info.circle"
        case .preference: return "heart"
        case .project: return "folder"
        case .instruction: return "list.bullet"
        case .reference: return "book"
        }
    }
}

/// Scope of memory - either global or workspace-specific
enum MemoryScope: Codable, Equatable, Hashable {
    case global
    case workspace(UUID)

    var isGlobal: Bool {
        if case .global = self {
            return true
        }
        return false
    }
}
