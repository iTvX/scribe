import AppKit
import ScribeConfig

/// Where Settings reads and writes, and whether that is the Scribe the user
/// types with.
///
/// `-ScribeUserDirectory <path>` and `-ScribeSharedDirectory <path>` override
/// the two directories for testing. With either set, Settings never looks
/// for, or notifies, the installed Scribe.
struct SettingsDirectories {
    static let scribeBundleIdentifier = "io.github.itvx.inputmethod.Scribe"

    /// Scribe's user data directory.
    var user: URL
    /// Scribe's shared data, or nil when the Scribe app cannot be found.
    var shared: URL?
    /// No overrides: the directories are the installed Scribe's.
    var isLive: Bool

    @MainActor
    init(defaults: UserDefaults = .standard, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        func directory(_ key: String) -> URL? {
            defaults.string(forKey: key).map { URL(filePath: $0, directoryHint: .isDirectory) }
        }
        let userOverride = directory("ScribeUserDirectory")
        let sharedOverride = directory("ScribeSharedDirectory")
        user = userOverride ?? UserDirectories(home: home).scribe
        isLive = userOverride == nil && sharedOverride == nil
        shared = sharedOverride ?? (isLive ? Self.installedSharedData() : nil)
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
