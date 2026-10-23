import AppKit
import ScribeConfig

/// Where Settings reads and writes, and whether that is the Scribe the user
/// types with.
///
/// `-ScribeUserDirectory <path>` and `-ScribeSharedDirectory <path>` override
/// the two directories for testing. With the user directory overridden,
/// Settings never looks for, or notifies, the installed Scribe; a shared
/// override only replaces the shared data.
struct SettingsDirectories {
    static let scribeBundleIdentifier = "io.github.itvx.inputmethod.Scribe"

    /// Scribe's user data directory.
    var user: URL
    /// Scribe's shared data, or nil when the Scribe app cannot be found.
    var shared: URL?
    /// The user directory is the installed Scribe's.
    var isLive: Bool

    @MainActor
    init(defaults: UserDefaults = .standard, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        func directory(_ key: String) -> URL? {
            defaults.string(forKey: key).map { URL(filePath: $0, directoryHint: .isDirectory) }
        }
        let location = SettingsLocation(home: home, userOverride: directory("ScribeUserDirectory"),
                                         sharedOverride: directory("ScribeSharedDirectory"),
                                         installedSharedData: Self.installedSharedData)
        user = location.userDirectory
        shared = location.sharedDirectory
        isLive = location.isLive
    }

    /// Whether the installed Scribe is running. Always false unless live.
    @MainActor
    var isScribeRunning: Bool {
        isLive && !NSRunningApplication.runningApplications(withBundleIdentifier: Self.scribeBundleIdentifier).isEmpty
    }

    /// Scribe.app/Contents/SharedSupport, as the input method finds it.
    @MainActor
    private static func installedSharedData() -> URL? {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: scribeBundleIdentifier) else { return nil }
        return Bundle(url: app)?.sharedSupportURL ?? app.appending(path: "Contents/SharedSupport", directoryHint: .isDirectory)
    }
}
