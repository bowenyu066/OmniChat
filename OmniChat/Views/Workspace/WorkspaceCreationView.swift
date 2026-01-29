import SwiftUI
import SwiftData

struct WorkspaceCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var description = ""
    @State private var selectedFolderURL: URL?
    @State private var selectedFolderBookmark: Data?
    @State private var showingError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Workspace Details") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }

                Section("Folder") {
                    if let url = selectedFolderURL {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            Text(url.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            Spacer()
                            Button("Change") {
                                selectFolder()
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        Button(action: selectFolder) {
                            HStack {
                                Image(systemName: "folder.badge.plus")
                                Text("Select Folder")
                            }
                        }
                    }
                }

                Section {
                    Text("Files in this folder will be indexed for use in conversations. Read-only access by default.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Workspace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createWorkspace()
                    }
                    .disabled(!isValid)
                }
            }
            .alert("Error", isPresented: .constant(showingError != nil)) {
                Button("OK") { showingError = nil }
            } message: {
                if let error = showingError {
                    Text(error)
                }
            }
        }
        .frame(width: 500, height: 400)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedFolderBookmark != nil
    }

    private func selectFolder() {
        if let result = SecurityScopedBookmarkService.shared.selectFolder() {
            selectedFolderURL = result.url
            selectedFolderBookmark = result.bookmark
        }
    }

    private func createWorkspace() {
        guard let bookmark = selectedFolderBookmark else { return }

        let workspace = Workspace(
            name: name.trimmingCharacters(in: .whitespaces),
            workspaceDescription: description.trimmingCharacters(in: .whitespaces),
            folderBookmark: bookmark
        )

        modelContext.insert(workspace)

        // Start indexing in background
        Task {
            do {
                try await FileIndexer.shared.indexWorkspace(
                    workspace,
                    modelContext: modelContext
                )
            } catch {
                await MainActor.run {
                    showingError = error.localizedDescription
                }
            }
        }

        dismiss()
    }
}

#Preview {
    WorkspaceCreationView()
        .modelContainer(for: [Workspace.self, FileIndexEntry.self])
}
