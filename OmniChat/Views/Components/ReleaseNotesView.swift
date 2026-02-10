import SwiftUI

struct ReleaseNotesView: View {
    let update: AppUpdateInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Release Notes")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Version \(update.version)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Release notes content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Release date
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.secondary)
                        Text("Released \(formattedDate)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Markdown-rendered release notes
                    MarkdownView(content: update.body)
                        .textSelection(.enabled)
                }
                .padding()
            }

            Divider()

            // Footer with action buttons
            HStack {
                Spacer()

                Button("View on GitHub") {
                    NSWorkspace.shared.open(update.releaseNotesURL)
                }
                .buttonStyle(.borderless)

                Button("Download") {
                    NSWorkspace.shared.open(update.downloadURL)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: update.releaseDate)
    }
}

#Preview {
    ReleaseNotesView(
        update: AppUpdateInfo(
            version: "v0.3.2-beta",
            releaseDate: Date(),
            downloadURL: URL(string: "https://github.com/bowenyu066/OmniChat/releases")!,
            releaseNotesURL: URL(string: "https://github.com/bowenyu066/OmniChat/releases")!,
            body: """
            ## What's New

            ### Features
            - Auto-update notification system
            - Non-intrusive update banners
            - Release notes viewer

            ### Bug Fixes
            - Fixed memory leak in chat view
            - Improved API error handling

            ### Changes
            - Updated dependencies
            """
        )
    )
}
