import AppKit
import ScribeConfig
import ScribeCore

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

    /// After a save: posts Reload to the installed Scribe when it is live
    /// and running, and says what happens next.
    @MainActor
    func announce(_ result: PatchSaveResult) -> (message: String, postedReload: Bool) {
        var message: String
        var posted = false
        if !isLive {
            message = "已保存（测试目录，没有通知中书）"
        } else if isScribeRunning {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(ServerNotification.reload), object: nil, userInfo: nil, deliverImmediately: true)
            posted = true
            message = "已保存，中书正在重新部署"
        } else {
            message = "已保存，中书下次启动时生效"
        }
        if !result.supersededKeys.isEmpty {
            message += "。合并了 \(result.supersededKeys.joined(separator: "、")) 这几个补丁项"
        }
        return (message, posted)
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
