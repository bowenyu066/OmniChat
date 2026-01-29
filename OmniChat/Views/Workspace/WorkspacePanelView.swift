import SwiftUI
import SwiftData

struct WorkspacePanelView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workspace.updatedAt, order: .reverse)
    private var workspaces: [Workspace]

    @State private var showingCreation = false
    @State private var selectedWorkspaceID: UUID?

    // Delete confirmation state - only primitive values, no object references
    @State private var showDeleteConfirmation = false
    @State private var deleteTargetID: UUID?
    @State private var deleteTargetName: String = ""
    @State private var deleteTargetIsIndexing: Bool = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedWorkspaceID) {
                ForEach(workspaces) { workspace in
                    WorkspaceRowContent(
                        id: workspace.id,
                        name: workspace.name,
                        indexStatus: workspace.indexStatus,
                        lastIndexedAt: workspace.lastIndexedAt,
                        onRequestDelete: { id, name, isIndexing in
                            deleteTargetID = id
                            deleteTargetName = name
                            deleteTargetIsIndexing = isIndexing
                            showDeleteConfirmation = true
                        }
                    )
                    .tag(workspace.id)
                }
            }
            .navigationTitle("Workspaces")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreation = true }) {
                        Label("New Workspace", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let id = selectedWorkspaceID, workspaces.contains(where: { $0.id == id }) {
                WorkspaceDetailView(workspaceID: id)
            } else {
                ContentUnavailableView(
                    "No Workspace Selected",
                    systemImage: "folder",
                    description: Text("Select a workspace from the sidebar or create a new one")
                )
            }
        }
        .sheet(isPresented: $showingCreation) {
            WorkspaceCreationView()
        }
        .confirmationDialog(
            "Delete \"\(deleteTargetName)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                performDelete()
            }
            Button("Cancel", role: .cancel) {
                clearDeleteState()
            }
        } message: {
            if deleteTargetIsIndexing {
                Text("This workspace is currently being indexed. Deleting it will stop the indexing process and remove all indexed data.")
            } else {
                Text("This will permanently delete the workspace and all its indexed data.")
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private func performDelete() {
        guard let id = deleteTargetID else {
            clearDeleteState()
            return
        }

        // Clear selection first if we're deleting the selected workspace
        if selectedWorkspaceID == id {
            selectedWorkspaceID = nil
        }

        // Clear delete state before actual deletion
        clearDeleteState()

        // Find and delete the workspace
        if let workspace = workspaces.first(where: { $0.id == id }) {
            workspace.indexStatus = .idle
            modelContext.delete(workspace)
            try? modelContext.save()
        }
    }

    private func clearDeleteState() {
        deleteTargetID = nil
        deleteTargetName = ""
        deleteTargetIsIndexing = false
    }
}

// MARK: - Row Content (no object references, just values)

private struct WorkspaceRowContent: View {
    let id: UUID
    let name: String
    let indexStatus: IndexStatus
    let lastIndexedAt: Date?
    let onRequestDelete: (UUID, String, Bool) -> Void

    @Query private var allFileEntries: [FileIndexEntry]

    private var fileCount: Int {
        allFileEntries.filter { $0.workspace?.id == id }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)

            HStack(spacing: 8) {
                statusIndicator

                Text("\(fileCount) files")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let lastIndexed = lastIndexedAt {
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(lastIndexed, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(role: .destructive) {
                onRequestDelete(id, name, indexStatus == .indexing)
            } label: {
                Label("Delete Workspace", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch indexStatus {
        case .idle:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .indexing:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.caption)
        }
    }
}

#Preview {
    WorkspacePanelView()
        .modelContainer(for: [Workspace.self, FileIndexEntry.self])
}
