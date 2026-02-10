import Foundation

// MARK: - Update Models

/// Information about an available app update
struct AppUpdateInfo: Equatable {
    let version: String
    let releaseDate: Date
    let downloadURL: URL
    let releaseNotesURL: URL
    let body: String
}

/// GitHub Release API response structure
struct GitHubRelease: Codable {
    let tag_name: String
    let name: String
    let body: String
    let html_url: String
    let published_at: String
    let assets: [GitHubAsset]
}

struct GitHubAsset: Codable {
    let name: String
    let browser_download_url: String
}

// MARK: - Semantic Version Parser

/// Semantic version parser with prerelease support
struct SemanticVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: String?

    /// Parse a version string like "v0.3.1-beta" or "0.3.1"
    init(parsing versionString: String) {
        // Remove "v" prefix if present
        var cleanVersion = versionString.hasPrefix("v") ? String(versionString.dropFirst()) : versionString

        // Extract prerelease tag if present (e.g., "0.3.1-beta" -> "0.3.1" + "beta")
        var prereleaseTag: String?
        if let dashIndex = cleanVersion.firstIndex(of: "-") {
            prereleaseTag = String(cleanVersion[cleanVersion.index(after: dashIndex)...])
            cleanVersion = String(cleanVersion[..<dashIndex])
        }

        // Parse major.minor.patch
        let components = cleanVersion.split(separator: ".").compactMap { Int($0) }

        self.major = components.count > 0 ? components[0] : 0
        self.minor = components.count > 1 ? components[1] : 0
        self.patch = components.count > 2 ? components[2] : 0
        self.prerelease = prereleaseTag
    }

    /// Compare versions: stable > prerelease, then compare major.minor.patch
    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        // Compare major.minor.patch first
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }

        // Same major.minor.patch - compare prerelease
        // Stable (no prerelease) > Prerelease
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false  // Equal versions
        case (nil, _):
            return false  // lhs is stable, rhs is prerelease -> lhs > rhs
        case (_, nil):
            return true   // lhs is prerelease, rhs is stable -> lhs < rhs
        case (let lPre?, let rPre?):
            return lPre < rPre  // Compare prerelease tags lexicographically
        }
    }

    var description: String {
        if let pre = prerelease {
            return "\(major).\(minor).\(patch)-\(pre)"
        }
        return "\(major).\(minor).\(patch)"
    }
}

// MARK: - Update Check Error

enum UpdateCheckError: LocalizedError {
    case networkError(Error)
    case invalidResponse
    case parseError
    case rateLimitExceeded

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from GitHub API"
        case .parseError:
            return "Failed to parse release information"
        case .rateLimitExceeded:
            return "GitHub API rate limit exceeded. Try again later."
        }
    }
}

// MARK: - UserDefaults Extensions

extension UserDefaults {
    private enum Keys {
        static let autoCheckForUpdates = "autoCheckForUpdates"
        static let updateCheckFrequency = "updateCheckFrequency"
        static let lastUpdateCheckDate = "lastUpdateCheckDate"
        static let dismissedUpdateVersion = "dismissedUpdateVersion"
    }

    var autoCheckForUpdates: Bool {
        get {
            // Default to true if not set
            if object(forKey: Keys.autoCheckForUpdates) == nil {
                return true
            }
            return bool(forKey: Keys.autoCheckForUpdates)
        }
        set { set(newValue, forKey: Keys.autoCheckForUpdates) }
    }

    var updateCheckFrequency: String {
        get { string(forKey: Keys.updateCheckFrequency) ?? "onStartup" }
        set { set(newValue, forKey: Keys.updateCheckFrequency) }
    }

    var lastUpdateCheckDate: Date? {
        get { object(forKey: Keys.lastUpdateCheckDate) as? Date }
        set { set(newValue, forKey: Keys.lastUpdateCheckDate) }
    }

    var dismissedUpdateVersion: String? {
        get { string(forKey: Keys.dismissedUpdateVersion) }
        set { set(newValue, forKey: Keys.dismissedUpdateVersion) }
    }
}

// MARK: - Update Check Service

@MainActor
final class UpdateCheckService: ObservableObject {
    static let shared = UpdateCheckService()

    private let githubRepoURL = "https://api.github.com/repos/bowenyu066/OmniChat/releases/latest"

    @Published var availableUpdate: AppUpdateInfo?
    @Published var isChecking: Bool = false
    @Published var lastCheckDate: Date?

    private init() {
        self.lastCheckDate = UserDefaults.standard.lastUpdateCheckDate
    }

    /// Check for updates (silent: true = no error alerts shown)
    func checkForUpdates(silent: Bool = false) async {
        guard !isChecking else { return }

        isChecking = true
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            let updateInfo = try parseReleaseInfo(release)

            // Update last check date
            lastCheckDate = Date()
            UserDefaults.standard.lastUpdateCheckDate = lastCheckDate

            // Check if this version was dismissed
            if let dismissedVersion = UserDefaults.standard.dismissedUpdateVersion,
               dismissedVersion == updateInfo.version {
                // User dismissed this version - don't show
                availableUpdate = nil
                return
            }

            // Compare with current version
            guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
                availableUpdate = nil
                return
            }

            let current = SemanticVersion(parsing: currentVersion)
            let latest = SemanticVersion(parsing: updateInfo.version)

            if latest > current {
                availableUpdate = updateInfo
            } else {
                availableUpdate = nil
            }

        } catch {
            if !silent {
                print("Update check failed: \(error.localizedDescription)")
            }
            availableUpdate = nil
        }
    }

    /// Dismiss the current update notification
    func dismissUpdate() {
        guard let update = availableUpdate else { return }
        UserDefaults.standard.dismissedUpdateVersion = update.version
        availableUpdate = nil
    }

    /// Temporarily hide update banner (will reappear on next launch)
    func hideUpdate() {
        availableUpdate = nil
    }

    // MARK: - Testing/Debug Methods

    #if DEBUG
    /// Force show a mock update banner for testing (Debug builds only)
    func showMockUpdate() {
        let mockUpdate = AppUpdateInfo(
            version: "v0.4.0-beta",
            releaseDate: Date(),
            downloadURL: URL(string: "https://github.com/bowenyu066/OmniChat/releases/latest")!,
            releaseNotesURL: URL(string: "https://github.com/bowenyu066/OmniChat/releases/latest")!,
            body: """
            ## What's New in v0.4.0-beta

            ### Features
            - ✨ Auto-update notification system
            - 🎨 Improved UI/UX
            - 📝 Better markdown rendering

            ### Bug Fixes
            - Fixed memory leak in chat view
            - Improved API error handling
            - Better LaTeX rendering performance

            ### Changes
            - Updated dependencies
            - Code refactoring for better maintainability

            This is a **test update** to demonstrate the update notification system!
            """
        )
        availableUpdate = mockUpdate
    }

    /// Clear any mock or real updates (Debug builds only)
    func clearUpdate() {
        availableUpdate = nil
    }
    #endif

    // MARK: - Private Methods

    private func fetchLatestRelease() async throws -> GitHubRelease {
        guard let url = URL(string: githubRepoURL) else {
            throw UpdateCheckError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        // Check for rate limiting
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 403,
           let rateLimitRemaining = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
           rateLimitRemaining == "0" {
            throw UpdateCheckError.rateLimitExceeded
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateCheckError.invalidResponse
        }

        do {
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            return release
        } catch {
            throw UpdateCheckError.parseError
        }
    }

    private func parseReleaseInfo(_ release: GitHubRelease) throws -> AppUpdateInfo {
        // Parse release date
        let dateFormatter = ISO8601DateFormatter()
        guard let releaseDate = dateFormatter.date(from: release.published_at) else {
            throw UpdateCheckError.parseError
        }

        // Find DMG asset (or use html_url as fallback)
        let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }
        let downloadURL = dmgAsset.map { URL(string: $0.browser_download_url) } ?? URL(string: release.html_url)

        guard let downloadURL = downloadURL else {
            throw UpdateCheckError.parseError
        }

        guard let releaseNotesURL = URL(string: release.html_url) else {
            throw UpdateCheckError.parseError
        }

        return AppUpdateInfo(
            version: release.tag_name,
            releaseDate: releaseDate,
            downloadURL: downloadURL,
            releaseNotesURL: releaseNotesURL,
            body: release.body
        )
    }
}
