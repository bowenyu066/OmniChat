import SwiftUI
import SwiftData

/// Configuration for memory context in a chat
struct MemoryContextConfig: Codable, Equatable {
    var includeAllMemories: Bool = false
    var includeFacts: Bool = false
    var includePreferences: Bool = false
    var includeProjects: Bool = false
    var includeInstructions: Bool = false
    var includeReferences: Bool = false

    // Specific memory IDs to include (for detailed customization)
    var specificMemoryIds: Set<UUID> = []

    // Conversation summaries to include
    var conversationSummaryIds: Set<UUID> = []  // Conversation IDs for which to include summary
    var conversationFullIds: Set<UUID> = []     // Conversation IDs for which to include full history
}

struct ChatMemoryContextView: View {
    @Binding var config: MemoryContextConfig
    @State private var showDetailedCustomization = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Memory")
                    .font(.headline)
                Spacer()
            }

            Text("Manage which memory to grant access to in this chat:")
                .font(.caption)
                .foregroundColor(.secondary)

            // Quick toggles
            VStack(alignment: .leading, spacing: 8) {
                MemoryToggle(
                    title: "All",
                    isOn: $config.includeAllMemories,
                    onChange: { isOn in
                        if isOn {
                            config.includeFacts = true
                            config.includePreferences = true
                            config.includeProjects = true
                            config.includeInstructions = true
                            config.includeReferences = true
                        }
                    }
                )

                MemoryToggle(title: "Facts", isOn: $config.includeFacts)
                MemoryToggle(title: "Preferences", isOn: $config.includePreferences)
                MemoryToggle(title: "Projects", isOn: $config.includeProjects)
                MemoryToggle(title: "Instructions", isOn: $config.includeInstructions)
                MemoryToggle(title: "References", isOn: $config.includeReferences)
            }

            Divider()

            // Detailed customization link
            Button(action: { showDetailedCustomization = true }) {
                HStack {
                    Text("Detailed customization")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding()
        .frame(width: 220)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showDetailedCustomization) {
            DetailedMemoryCustomizationView(config: $config)
        }
    }
}

struct MemoryToggle: View {
    let title: String
    @Binding var isOn: Bool
    var onChange: ((Bool) -> Void)?

    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { newValue in
                    isOn = newValue
                    onChange?(newValue)
                }
            )) {
                Text(title)
                    .font(.subheadline)
            }
            .toggleStyle(.checkbox)
        }
    }
}

// MARK: - Detailed Memory Customization Window

struct DetailedMemoryCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Binding var config: MemoryContextConfig

    @Query(filter: #Predicate<MemoryItem> { !$0.isDeleted }, sort: \MemoryItem.updatedAt, order: .reverse)
    private var allMemories: [MemoryItem]

    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var conversations: [Conversation]

    @State private var selectedConversationAccess: [UUID: ConversationAccessType] = [:]

    enum ConversationAccessType {
        case none
        case full
        case summary
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Conversations section
                    conversationsSection

                    Divider()

                    // Memories section
                    memoriesSection
                }
                .padding()
            }
            .navigationTitle("Detailed Customization")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyChanges()
                        dismiss()
                    }
                }
            }
            .frame(minWidth: 500, minHeight: 600)
        }
        .onAppear {
            loadCurrentConfig()
        }
    }

    private var conversationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select the conversations you'd like to grant access to in this chat:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // All conversations toggle
            HStack {
                Toggle("All", isOn: Binding(
                    get: { conversations.allSatisfy { selectedConversationAccess[$0.id] != nil && selectedConversationAccess[$0.id] != .none } },
                    set: { isOn in
                        for conv in conversations {
                            selectedConversationAccess[conv.id] = isOn ? .summary : .none
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                Spacer()
            }

            // Individual conversations
            ForEach(conversations) { conversation in
                ConversationAccessRow(
                    conversation: conversation,
                    accessType: Binding(
                        get: { selectedConversationAccess[conversation.id] ?? .none },
                        set: { selectedConversationAccess[conversation.id] = $0 }
                    )
                )
            }
        }
    }

    private var memoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select the memories you'd like to grant access to in this chat:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Group by type
            ForEach(MemoryType.allCases, id: \.self) { type in
                let memoriesOfType = allMemories.filter { $0.type == type }
                if !memoriesOfType.isEmpty {
                    MemoryTypeGroup(
                        type: type,
                        memories: memoriesOfType,
                        selectedIds: $config.specificMemoryIds,
                        typeEnabled: bindingForType(type)
                    )
                }
            }
        }
    }

    private func bindingForType(_ type: MemoryType) -> Binding<Bool> {
        switch type {
        case .fact: return $config.includeFacts
        case .preference: return $config.includePreferences
        case .project: return $config.includeProjects
        case .instruction: return $config.includeInstructions
        case .reference: return $config.includeReferences
        }
    }

    private func loadCurrentConfig() {
        // Load conversation access from config
        for convId in config.conversationFullIds {
            selectedConversationAccess[convId] = .full
        }
        for convId in config.conversationSummaryIds {
            if selectedConversationAccess[convId] == nil {
                selectedConversationAccess[convId] = .summary
            }
        }
    }

    private func applyChanges() {
        // Update conversation access
        config.conversationFullIds.removeAll()
        config.conversationSummaryIds.removeAll()

        for (convId, accessType) in selectedConversationAccess {
            switch accessType {
            case .full:
                config.conversationFullIds.insert(convId)
            case .summary:
                config.conversationSummaryIds.insert(convId)
            case .none:
                break
            }
        }
    }
}

struct ConversationAccessRow: View {
    let conversation: Conversation
    @Binding var accessType: DetailedMemoryCustomizationView.ConversationAccessType

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { accessType != .none },
                set: { isOn in
                    accessType = isOn ? .summary : .none
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text(conversation.title)
                .lineLimit(1)
                .foregroundColor(accessType != .none ? .primary : .secondary)

            Spacer()

            if accessType != .none {
                Picker("", selection: $accessType) {
                    Text("Full").tag(DetailedMemoryCustomizationView.ConversationAccessType.full)
                    Text("Summary").tag(DetailedMemoryCustomizationView.ConversationAccessType.summary)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(accessType != .none ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
}

struct MemoryTypeGroup: View {
    let type: MemoryType
    let memories: [MemoryItem]
    @Binding var selectedIds: Set<UUID>
    @Binding var typeEnabled: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Type header
            HStack {
                Toggle("All \(type.rawValue)s", isOn: $typeEnabled)
                    .toggleStyle(.checkbox)

                Spacer()

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            // Individual memories (collapsed by default)
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(memories) { memory in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { selectedIds.contains(memory.id) },
                                set: { isOn in
                                    if isOn {
                                        selectedIds.insert(memory.id)
                                    } else {
                                        selectedIds.remove(memory.id)
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()

                            Text(memory.title)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        .padding(.leading, 20)
                    }
                }
            }
        }
    }
}

#Preview {
    ChatMemoryContextView(config: .constant(MemoryContextConfig()))
}
