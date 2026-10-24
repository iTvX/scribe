import Foundation

/// Where Scribe Settings reads and writes, and whether that is the Scribe
/// the user types with.
public struct SettingsLocation: Equatable, Sendable {
    public var userDirectory: URL
    /// Scribe's shared data, or nil when it is unknown.
    public var sharedDirectory: URL?
    /// The user directory is the installed Scribe's.
    public var isLive: Bool

    /// A shared override only replaces the shared directory. With a user
    /// override, the installed Scribe is never looked for: without a shared
    /// override too, the shared directory is unknown. `installedSharedData`
    /// finds the installed Scribe's shared data.
    public init(home: URL, userOverride: URL?, sharedOverride: URL?, installedSharedData: () -> URL?) {
        userDirectory = userOverride ?? UserDirectories(home: home).scribe
        isLive = userOverride == nil
        if let sharedOverride {
            sharedDirectory = sharedOverride
        } else {
            sharedDirectory = isLive ? installedSharedData() : nil
        }
    }

    /// The shared data of the Scribe.app that a Settings app bundle is
    /// embedded in, as `Scribe.app/Contents/Helpers/ScribeSettings.app`, or
    /// nil when it is not inside one.
    public static func enclosingScribeSharedData(of settingsBundle: URL) -> URL? {
        let helpers = settingsBundle.standardizedFileURL.deletingLastPathComponent()
        let contents = helpers.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard helpers.lastPathComponent == "Helpers", contents.lastPathComponent == "Contents", app.pathExtension == "app"
        else { return nil }
        return contents.appending(path: "SharedSupport", directoryHint: .isDirectory)
    }
}
