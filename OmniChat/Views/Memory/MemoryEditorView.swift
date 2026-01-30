import SwiftUI
import SwiftData

struct MemoryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var workspaces: [Workspace]

    let memory: MemoryItem?

    @State private var title: String
    @State private var bodyText: String
    @State private var selectedType: MemoryType
    @State private var tagsString: String
    @State private var scope: MemoryScope
    @State private var selectedWorkspace: Workspace?
    @State private var isDefaultSelected: Bool
    @State private var isPinned: Bool

    init(memory: MemoryItem?) {
        self.memory = memory

        // Initialize state from memory or defaults
        _title = State(initialValue: memory?.title ?? "")
        _bodyText = State(initialValue: memory?.body ?? "")
        _selectedType = State(initialValue: memory?.type ?? .reference)
        _tagsString = State(initialValue: memory?.tagsString ?? "")
        _scope = State(initialValue: memory?.scope ?? .global)
        _selectedWorkspace = State(initialValue: memory?.workspace)
        _isDefaultSelected = State(initialValue: memory?.isDefaultSelected ?? false)
        _isPinned = State(initialValue: memory?.isPinned ?? false)
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !bodyText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title, prompt: Text("Memory title"))
                        .textFieldStyle(.plain)

                    Picker("Type", selection: $selectedType) {
                        ForEach(MemoryType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Content") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 150)
                        .font(.body)
                }

                Section("Scope") {
                    Picker("Scope", selection: $scope) {
                        Text("Global").tag(MemoryScope.global)
                        if !workspaces.isEmpty {
                            ForEach(workspaces) { workspace in
                                Text(workspace.name).tag(MemoryScope.workspace(workspace.id))
                            }
                        }
                    }
                    .pickerStyle(.menu)

                    if !scope.isGlobal {
                        Text("This memory will only be available in the selected workspace")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Tags") {
                    TextField("Tags (comma-separated)", text: $tagsString, prompt: Text("work, swift, important"))
                        .textFieldStyle(.plain)

                    if !tagsString.isEmpty {
                        let tags = tagsString.split(separator: ",").map {
                            $0.trimmingCharacters(in: .whitespaces)
                        }.filter { !$0.isEmpty }

                        if !tags.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(tags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.2))
                                        .foregroundColor(.accentColor)
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                }

                Section("Options") {
                    Toggle("Auto-select in new conversations", isOn: $isDefaultSelected)
                    Text("When enabled, this memory will be automatically selected in newly created conversations")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Pin to top", isOn: $isPinned)
                    Text("Pinned memories appear at the top of the list")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(memory == nil ? "New Memory" : "Edit Memory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMemory()
                    }
                    .disabled(!isValid)
                }
            }
            .frame(minWidth: 500, minHeight: 500)
        }
    }

    private func saveMemory() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespaces)

        if let memory = memory {
            // Update existing memory
            memory.title = trimmedTitle
            memory.body = trimmedBody
            memory.type = selectedType
            memory.scope = scope
            memory.setTags(from: tagsString)
            memory.isDefaultSelected = isDefaultSelected
            memory.isPinned = isPinned
            memory.updatedAt = Date()

            // Update workspace relationship
            if case .workspace(let workspaceId) = scope {
                memory.workspace = workspaces.first { $0.id == workspaceId }
            } else {
                memory.workspace = nil
            }
        } else {
            // Create new memory
            let newMemory = MemoryItem(
                title: trimmedTitle,
                body: trimmedBody,
                type: selectedType,
                scope: scope
            )
            newMemory.setTags(from: tagsString)
            newMemory.isDefaultSelected = isDefaultSelected
            newMemory.isPinned = isPinned

            // Set workspace relationship
            if case .workspace(let workspaceId) = scope {
                newMemory.workspace = workspaces.first { $0.id == workspaceId }
            }

            modelContext.insert(newMemory)
        }

        dismiss()
    }
}

#Preview {
    MemoryEditorView(memory: nil)
        .modelContainer(for: [MemoryItem.self, Workspace.self], inMemory: true)
}
