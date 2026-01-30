import SwiftUI
import SwiftData

struct MemoryPanelView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<MemoryItem> { !$0.isDeleted }, sort: \MemoryItem.updatedAt, order: .reverse)
    private var allMemories: [MemoryItem]

    @State private var searchText = ""
    @State private var selectedType: MemoryType?
    @State private var showOnlyPinned = false
    @State private var scopeFilter: MemoryFilterBar.ScopeFilter = .all
    @State private var showingEditor = false
    @State private var editingMemory: MemoryItem?

    // Bulk delete state
    @State private var isEditMode = false
    @State private var selectedMemoryIDs: Set<UUID> = []

    var filteredMemories: [MemoryItem] {
        allMemories.filter { memory in
            // Search filter
            let matchesSearch = searchText.isEmpty ||
                memory.title.localizedCaseInsensitiveContains(searchText) ||
                memory.body.localizedCaseInsensitiveContains(searchText) ||
                memory.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }

            // Type filter
            let matchesType = selectedType == nil || memory.type == selectedType

            // Pinned filter
            let matchesPinned = !showOnlyPinned || memory.isPinned

            // Scope filter
            let matchesScope: Bool
            switch scopeFilter {
            case .all:
                matchesScope = true
            case .global:
                matchesScope = memory.scope.isGlobal
            case .workspace:
                matchesScope = !memory.scope.isGlobal
            }

            return matchesSearch && matchesType && matchesPinned && matchesScope
        }
        .sorted { memory1, memory2 in
            // First, prioritize pinned items
            if memory1.isPinned != memory2.isPinned {
                return memory1.isPinned
            }
            // Then sort by updatedAt (most recent first)
            return memory1.updatedAt > memory2.updatedAt
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Memory Panel")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if isEditMode {
                    Button(action: deleteSelected) {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedMemoryIDs.isEmpty)

                    Button("Done") {
                        isEditMode = false
                        selectedMemoryIDs.removeAll()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Edit") {
                        isEditMode = true
                    }
                    .buttonStyle(.borderless)
                    .disabled(filteredMemories.isEmpty)

                    Button(action: createNewMemory) {
                        Label("New Memory", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding()

            Divider()

            // Filter bar
            MemoryFilterBar(
                searchText: $searchText,
                selectedType: $selectedType,
                showOnlyPinned: $showOnlyPinned,
                scopeFilter: $scopeFilter
            )
            .padding()

            Divider()

            // Select All checkbox (only in edit mode)
            if isEditMode && !filteredMemories.isEmpty {
                HStack {
                    Toggle(isOn: Binding(
                        get: { selectedMemoryIDs.count == filteredMemories.count },
                        set: { newValue in
                            if newValue {
                                selectedMemoryIDs = Set(filteredMemories.map { $0.id })
                            } else {
                                selectedMemoryIDs.removeAll()
                            }
                        }
                    )) {
                        Text("Select All")
                            .font(.subheadline)
                    }
                    .toggleStyle(.checkbox)

                    Spacer()

                    Text("\(selectedMemoryIDs.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()
            }

            // Memory list
            if filteredMemories.isEmpty {
                EmptyMemoryView(hasMemories: !allMemories.isEmpty, onCreate: createNewMemory)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredMemories) { memory in
                            HStack(spacing: 8) {
                                if isEditMode {
                                    Toggle(isOn: Binding(
                                        get: { selectedMemoryIDs.contains(memory.id) },
                                        set: { newValue in
                                            if newValue {
                                                selectedMemoryIDs.insert(memory.id)
                                            } else {
                                                selectedMemoryIDs.remove(memory.id)
                                            }
                                        }
                                    )) {
                                        EmptyView()
                                    }
                                    .toggleStyle(.checkbox)
                                }

                                MemoryRow(memory: memory, isEditMode: isEditMode) {
                                    editMemory(memory)
                                }

                                if !isEditMode {
                                    // Context menu only shown when not in edit mode
                                    EmptyView()
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isEditMode {
                                    if selectedMemoryIDs.contains(memory.id) {
                                        selectedMemoryIDs.remove(memory.id)
                                    } else {
                                        selectedMemoryIDs.insert(memory.id)
                                    }
                                }
                            }
                            .contextMenu {
                                if !isEditMode {
                                    Button(action: { editMemory(memory) }) {
                                        Label("Edit", systemImage: "pencil")
                                    }

                                    Button(action: { togglePin(memory) }) {
                                        Label(
                                            memory.isPinned ? "Unpin" : "Pin",
                                            systemImage: memory.isPinned ? "pin.slash" : "pin"
                                        )
                                    }

                                    Divider()

                                    Button(action: { deleteMemory(memory) }) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 300, idealWidth: 400)
        .sheet(isPresented: $showingEditor) {
            MemoryEditorView(memory: editingMemory)
        }
    }

    private func createNewMemory() {
        editingMemory = nil
        showingEditor = true
    }

    private func editMemory(_ memory: MemoryItem) {
        editingMemory = memory
        showingEditor = true
    }

    private func togglePin(_ memory: MemoryItem) {
        memory.isPinned.toggle()
        memory.updatedAt = Date()
    }

    private func deleteMemory(_ memory: MemoryItem) {
        memory.isDeleted = true
        memory.updatedAt = Date()
    }

    private func deleteSelected() {
        for id in selectedMemoryIDs {
            if let memory = allMemories.first(where: { $0.id == id }) {
                memory.isDeleted = true
                memory.updatedAt = Date()
            }
        }
        selectedMemoryIDs.removeAll()
        isEditMode = false
    }
}

struct EmptyMemoryView: View {
    let hasMemories: Bool
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasMemories ? "magnifyingglass" : "brain.head.profile")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(hasMemories ? "No matching memories" : "No memories yet")
                .font(.title3)
                .fontWeight(.medium)

            Text(hasMemories ?
                "Try adjusting your filters or search" :
                "Create your first memory to get started"
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

            if !hasMemories {
                Button(action: onCreate) {
                    Label("Create Memory", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    MemoryPanelView()
        .modelContainer(for: [MemoryItem.self], inMemory: true)
}
