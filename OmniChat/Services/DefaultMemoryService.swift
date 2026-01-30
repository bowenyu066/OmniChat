import Foundation
import SwiftData

/// Service for creating and managing default memories
final class DefaultMemoryService {
    static let shared = DefaultMemoryService()

    private let userDefaultsKey = "hasCreatedDefaultMemories"

    private init() {}

    /// Creates default memories if they haven't been created yet
    func createDefaultMemoriesIfNeeded(modelContext: ModelContext) {
        // Check if we've already created default memories
        if UserDefaults.standard.bool(forKey: userDefaultsKey) {
            return
        }

        createDefaultMemories(modelContext: modelContext)

        // Mark as created
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
    }

    private func createDefaultMemories(modelContext: ModelContext) {
        // 1. LaTeX Formatting Instructions (System-level, always selected)
        let latexInstructions = MemoryItem(
            title: "LaTeX Formatting Guidelines",
            body: """
            When writing mathematical formulas or equations in your responses:

            - Use $...$ for inline formulas (e.g., "The value is $x = 5$")
            - Use $$...$$ for display (block) formulas on their own line
            - DO NOT use \\(...\\) or \\[...\\] notation
            - Always prefer $ delimiters for compatibility

            Examples:
            ✅ Correct: "Einstein's famous equation is $E = mc^2$"
            ✅ Correct: "The quadratic formula:\n\n$$x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}$$"
            ❌ Wrong: "Einstein's famous equation is \\(E = mc^2\\)"
            ❌ Wrong: "The quadratic formula:\n\n\\[x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}\\]"
            """,
            type: .instruction,
            scope: .global
        )
        latexInstructions.isDefaultSelected = true
        latexInstructions.isPinned = true
        modelContext.insert(latexInstructions)

        // 2. Sample Preference (not selected by default)
        let samplePreference = MemoryItem(
            title: "Communication Style Preference",
            body: "Prefer concise, direct explanations without unnecessary verbosity. Get to the point quickly.",
            type: .preference,
            scope: .global
        )
        samplePreference.isDefaultSelected = false
        modelContext.insert(samplePreference)

        // 3. Sample Fact (not selected by default)
        let sampleFact = MemoryItem(
            title: "About Me",
            body: "I am a software developer working with Swift and SwiftUI on macOS applications.",
            type: .fact,
            scope: .global
        )
        sampleFact.isDefaultSelected = false
        modelContext.insert(sampleFact)

        try? modelContext.save()
    }

    /// Creates a memory context config with default selections
    static func createDefaultMemoryConfig(modelContext: ModelContext) -> MemoryContextConfig {
        var config = MemoryContextConfig()

        // Fetch all memories marked as default
        let descriptor = FetchDescriptor<MemoryItem>(
            predicate: #Predicate { memory in
                memory.isDefaultSelected && !memory.isDeleted
            }
        )

        if let defaultMemories = try? modelContext.fetch(descriptor) {
            for memory in defaultMemories {
                config.specificMemoryIds.insert(memory.id)

                // Also enable the type toggle
                switch memory.type {
                case .fact:
                    config.includeFacts = true
                case .preference:
                    config.includePreferences = true
                case .project:
                    config.includeProjects = true
                case .instruction:
                    config.includeInstructions = true
                case .reference:
                    config.includeReferences = true
                }
            }
        }

        return config
    }
}
