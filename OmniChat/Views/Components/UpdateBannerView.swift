import SwiftUI

struct UpdateBannerView: View {
    let update: AppUpdateInfo
    @StateObject private var updateService = UpdateCheckService.shared
    @State private var showReleaseNotes = false
    @State private var isVisible = true

    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)

                // Message
                VStack(alignment: .leading, spacing: 2) {
                    Text("OmniChat \(update.version) is available")
                        .font(.system(size: 13, weight: .medium))
                    Text("You're currently using version \(currentVersion)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    Button("View Release Notes") {
                        showReleaseNotes = true
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))

                    Button("Download") {
                        NSWorkspace.shared.open(update.downloadURL)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .font(.system(size: 12))

                    Button("Dismiss") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isVisible = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            updateService.hideUpdate()
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))

                    // Close button (permanently dismiss this version)
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isVisible = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            updateService.dismissUpdate()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Don't show this version again")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Rectangle()
                    .fill(Color.blue.opacity(0.08))
                    .overlay(
                        Rectangle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(height: 1),
                        alignment: .bottom
                    )
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .sheet(isPresented: $showReleaseNotes) {
                ReleaseNotesView(update: update)
            }
        }
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
}

#Preview {
    VStack(spacing: 0) {
        UpdateBannerView(
            update: AppUpdateInfo(
                version: "v0.3.2-beta",
                releaseDate: Date(),
                downloadURL: URL(string: "https://github.com/bowenyu066/OmniChat/releases")!,
                releaseNotesURL: URL(string: "https://github.com/bowenyu066/OmniChat/releases")!,
                body: "## What's New\n- Auto-update notifications\n- Bug fixes"
            )
        )

        Rectangle()
            .fill(Color.gray.opacity(0.1))
    }
    .frame(width: 800, height: 400)
}
