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
}
