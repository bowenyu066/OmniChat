import SwiftUI
import SwiftData

struct WorkspaceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var workspace: Workspace

    @State private var isIndexing = false
    @State private var indexProgress: (current: Int, total: Int)?
    @State private var showingError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(workspace.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    if !workspace.workspaceDescription.isEmpty {
                        Text(workspace.workspaceDescription)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Folder info
                GroupBox("Folder") {
                    if let bookmarkData = workspace.folderBookmark {
                        VStack(alignment: .leading, spacing: 12) {
                            if let url = try? SecurityScopedBookmarkService.shared.resolveBookmark(bookmarkData) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(.blue)
                                    Text(url.path)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            } else {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text("Folder access lost. Please reselect.")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                        }
                    } else {
                        Text("No folder selected")
                            .foregroundColor(.secondary)
                    }
                }

                // Index status
                GroupBox("Index Status") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Status
                        HStack {
                            Text("Status:")
                                .fontWeight(.medium)
                            Spacer()
                            statusBadge
                        }

                        // File count
                        HStack {
                            Text("Files indexed:")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(workspace.fileEntries.count)")
                                .foregroundColor(.secondary)
                        }

                        // Last indexed
                        if let lastIndexed = workspace.lastIndexedAt {
                            HStack {
                                Text("Last indexed:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(lastIndexed, style: .relative)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Progress
                        if let progress = indexProgress {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Indexing: \(progress.current) / \(progress.total)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ProgressView(value: Double(progress.current), total: Double(progress.total))
                            }
                        }

                        Divider()

                        // Re-index button
                        Button(action: reindex) {
                            Label("Re-index Workspace", systemImage: "arrow.clockwise")
                        }
                        .disabled(isIndexing)
                    }
                }

                // Settings
                GroupBox("Settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable write access (use with caution)", isOn: $workspace.writeEnabled)
                            .toggleStyle(.switch)

                        if workspace.writeEnabled {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                Text("AI can modify files when write access is enabled")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // File list preview
                if !workspace.fileEntries.isEmpty {
                    GroupBox("Indexed Files") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(workspace.fileEntries.prefix(20), id: \.id) { entry in
                                    HStack {
                                        Image(systemName: fileIcon(for: entry.relativePath))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(entry.relativePath)
                                            .font(.caption)
                                            .font(.system(.caption, design: .monospaced))
                                        Spacer()
                                        Text("\(entry.chunks.count) chunks")
                                            .font(.caption2)
                                            .foregroundColor(.secondary.opacity(0.7))
                                    }
                                }

                                if workspace.fileEntries.count > 20 {
                                    Text("... and \(workspace.fileEntries.count - 20) more")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 4)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .alert("Error", isPresented: .constant(showingError != nil)) {
            Button("OK") { showingError = nil }
        } message: {
            if let error = showingError {
                Text(error)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch workspace.indexStatus {
        case .idle:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Idle")
                    .foregroundColor(.secondary)
            }
        case .indexing:
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Indexing...")
                    .foregroundColor(.secondary)
            }
        case .error:
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Error")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func fileIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "doc.text"
        case "md": return "doc.richtext"
        case "json", "yaml", "yml", "toml": return "curlybraces"
        case "js", "ts", "jsx", "tsx": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }

    private func reindex() {
        isIndexing = true
        indexProgress = nil

        Task {
            do {
                try await FileIndexer.shared.indexWorkspace(
                    workspace,
                    modelContext: modelContext,
                    onProgress: { current, total in
                        Task { @MainActor in
                            indexProgress = (current, total)
                        }
                    }
                )

                await MainActor.run {
                    isIndexing = false
                    indexProgress = nil
                }
            } catch {
                await MainActor.run {
                    isIndexing = false
                    indexProgress = nil
                    showingError = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    let workspace = Workspace(name: "My Project", workspaceDescription: "A sample SwiftUI project")
    return WorkspaceDetailView(workspace: workspace)
        .modelContainer(for: [Workspace.self, FileIndexEntry.self])
}
