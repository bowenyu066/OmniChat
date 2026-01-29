import SwiftUI
import SwiftData

struct WorkspacePanelView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workspace.updatedAt, order: .reverse)
    private var workspaces: [Workspace]

    @State private var showingCreation = false
    @State private var selectedWorkspace: Workspace?

    var body: some View {
        NavigationSplitView {
            // Workspace list
            List(selection: $selectedWorkspace) {
                ForEach(workspaces) { workspace in
                    WorkspaceRow(workspace: workspace)
                        .tag(workspace)
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
            if let workspace = selectedWorkspace {
                WorkspaceDetailView(workspace: workspace)
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
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct WorkspaceRow: View {
    @Bindable var workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workspace.name)
                .font(.headline)

            HStack(spacing: 8) {
                // Status indicator
                statusIndicator

                // File count
                Text("\(workspace.fileEntries.count) files")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let lastIndexed = workspace.lastIndexedAt {
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(lastIndexed, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch workspace.indexStatus {
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
