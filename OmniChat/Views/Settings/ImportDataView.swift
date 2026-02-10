import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportDataView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isImporting = false
    @State private var showFilePicker = false
    @State private var progress: ChatGPTImportService.ImportProgress?
    @State private var result: ChatGPTImportService.ImportResult?
    @State private var errorMessage: String?
    @State private var generateEmbeddings = true

    private let importService = ChatGPTImportService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Label("Import ChatGPT Data", systemImage: "square.and.arrow.down")
                    .font(.headline)

                Text("Import your ChatGPT conversation history to enable RAG search across your existing chats.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("How to export from ChatGPT:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 6) {
                    instructionRow(number: 1, text: "Go to ChatGPT Settings → Data controls")
                    instructionRow(number: 2, text: "Click \"Export data\"")
                    instructionRow(number: 3, text: "Download the ZIP file")
                    instructionRow(number: 4, text: "Select the ZIP file or conversations.json below")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("Tip: Import the ZIP file directly to include images from your conversations.")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            Divider()

            // Options
            Toggle(isOn: $generateEmbeddings) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Generate embeddings for RAG")
                    Text("Enables semantic search across imported conversations. Uses OpenAI API.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isImporting)

            // Import button or progress
            if isImporting {
                progressView
            } else if let result = result {
                resultView(result)
            } else {
                Button(action: { showFilePicker = true }) {
                    Label("Select ZIP or conversations.json", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }

            // Error message
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Background embedding indicator
            if importService.isGeneratingEmbeddings {
                backgroundEmbeddingView
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType.json, UTType.zip],
            allowsMultipleSelection: false
        ) { fileResult in
            handleFileSelection(fileResult)
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .frame(width: 16, alignment: .trailing)
            Text(text)
        }
    }

    @ViewBuilder
    private var progressView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text(progress?.phase.rawValue ?? "Processing...")
                    .font(.subheadline)
            }

            if let progress = progress {
                VStack(alignment: .leading, spacing: 4) {
                    if progress.phase == .importing {
                        ProgressView(value: progress.progressFraction)
                        Text("\(progress.importedConversations) / \(progress.totalConversations) conversations")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !progress.currentTitle.isEmpty {
                            Text("Current: \(progress.currentTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else if progress.phase == .embedding && progress.totalMessagesToEmbed > 0 {
                        ProgressView(value: Double(progress.embeddingProgress), total: Double(progress.totalMessagesToEmbed))
                        Text("\(progress.embeddingProgress) / \(progress.totalMessagesToEmbed) embeddings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var backgroundEmbeddingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text("Generating embeddings in background...")
                    .font(.caption)
                Text("\(importService.embeddingProgressCount) / \(importService.embeddingTotalCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(6)
    }

    private func resultView(_ result: ChatGPTImportService.ImportResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Import Complete")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("• \(result.conversationsImported) conversations imported")
                Text("• \(result.messagesImported) messages imported")
                if result.imagesImported > 0 {
                    Text("• \(result.imagesImported) images imported")
                }
                if result.conversationsSkipped > 0 {
                    Text("• \(result.conversationsSkipped) empty conversations skipped")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)

            if !result.errors.isEmpty {
                Divider()
                Text("\(result.errors.count) errors occurred:")
                    .font(.caption)
                    .foregroundStyle(.orange)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(result.errors.prefix(5), id: \.self) { error in
                            Text("• \(error)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if result.errors.count > 5 {
                            Text("... and \(result.errors.count - 5) more")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 60)
            }

            Button("Import More") {
                self.result = nil
                self.errorMessage = nil
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func handleFileSelection(_ fileResult: Result<[URL], Error>) {
        switch fileResult {
        case .success(let urls):
            guard let url = urls.first else { return }
            startImport(from: url)

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func startImport(from url: URL) {
        isImporting = true
        errorMessage = nil
        result = nil

        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()

        // Determine if it's a ZIP file
        let isZipFile = url.pathExtension.lowercased() == "zip"

        Task {
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let importResult: ChatGPTImportService.ImportResult

                if isZipFile {
                    // Import from ZIP (includes images)
                    importResult = try await importService.importFromZip(
                        url,
                        modelContext: modelContext,
                        generateEmbeddings: generateEmbeddings
                    ) { progress in
                        self.progress = progress
                    }
                } else {
                    // Import from JSON only (no images)
                    importResult = try await importService.importFromFile(
                        url,
                        modelContext: modelContext,
                        generateEmbeddings: generateEmbeddings
                    ) { progress in
                        self.progress = progress
                    }
                }

                await MainActor.run {
                    self.result = importResult
                    self.isImporting = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isImporting = false
                }
            }
        }
    }
}

#Preview {
    ImportDataView()
}
