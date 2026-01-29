import SwiftUI
import SwiftData

/// Detail view that looks up workspace by ID - safe against deletion
struct WorkspaceDetailView: View {
    let workspaceID: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var allWorkspaces: [Workspace]
    @Query private var allFileEntries: [FileIndexEntry]

    @State private var isIndexing = false
    @State private var indexProgress: (current: Int, total: Int)?
    @State private var showingError: String?

    private var workspace: Workspace? {
        allWorkspaces.first { $0.id == workspaceID }
    }

    private var fileEntries: [FileIndexEntry] {
        allFileEntries.filter { $0.workspace?.id == workspaceID }
    }

    var body: some View {
        Group {
            if let ws = workspace {
                workspaceContent(ws)
            } else {
                ContentUnavailableView(
                    "Workspace Not Found",
                    systemImage: "folder.badge.questionmark",
                    description: Text("This workspace may have been deleted.")
                )
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

    @ViewBuilder
    private func workspaceContent(_ ws: Workspace) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(ws.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    if !ws.workspaceDescription.isEmpty {
                        Text(ws.workspaceDescription)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Folder info
                GroupBox("Folder") {
                    if let bookmarkData = ws.folderBookmark {
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
                        HStack {
                            Text("Status:")
                                .fontWeight(.medium)
                            Spacer()
                            statusBadge(for: ws.indexStatus)
                        }

                        HStack {
                            Text("Files indexed:")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(fileEntries.count)")
                                .foregroundColor(.secondary)
                        }

                        if let lastIndexed = ws.lastIndexedAt {
                            HStack {
                                Text("Last indexed:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(lastIndexed, style: .relative)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let progress = indexProgress {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Indexing: \(progress.current) / \(progress.total)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ProgressView(value: Double(progress.current), total: Double(progress.total))
                            }
                        }

                        Divider()

                        Button(action: { reindex(ws) }) {
                            Label("Re-index Workspace", systemImage: "arrow.clockwise")
                        }
                        .disabled(isIndexing)
                    }
                }

                // Settings
                GroupBox("Settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable write access (use with caution)", isOn: Binding(
                            get: { ws.writeEnabled },
                            set: { ws.writeEnabled = $0 }
                        ))
                        .toggleStyle(.switch)

                        if ws.writeEnabled {
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
                if !fileEntries.isEmpty {
                    GroupBox("Indexed Files") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(fileEntries.prefix(20), id: \.id) { entry in
                                    HStack {
                                        Image(systemName: fileIcon(for: entry.relativePath))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(entry.relativePath)
                                            .font(.system(.caption, design: .monospaced))
                                        Spacer()
                                        Text("\(entry.chunks.count) chunks")
                                            .font(.caption2)
                                            .foregroundColor(.secondary.opacity(0.7))
                                    }
                                }

                                if fileEntries.count > 20 {
                                    Text("... and \(fileEntries.count - 20) more")
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
    }

    @ViewBuilder
    private func statusBadge(for status: IndexStatus) -> some View {
        switch status {
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

    private func reindex(_ ws: Workspace) {
        isIndexing = true
        indexProgress = nil

        Task {
            do {
                try await FileIndexer.shared.indexWorkspace(
                    ws,
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
    WorkspaceDetailView(workspaceID: UUID())
        .modelContainer(for: [Workspace.self, FileIndexEntry.self])
}
