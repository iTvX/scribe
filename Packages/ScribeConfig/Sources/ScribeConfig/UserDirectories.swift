import Foundation

/// The Rime user data directories Scribe works with.
public struct UserDirectories: Equatable, Sendable {
    /// Scribe's own user data directory, `~/Library/Scribe`.
    public var scribe: URL
    /// Squirrel's user data directory, `~/Library/Rime`. Scribe imports from it
    /// but never writes to it.
    public var squirrel: URL

    public init(home: URL) {
        let library = home.appending(path: "Library", directoryHint: .isDirectory)
        scribe = library.appending(path: "Scribe", directoryHint: .isDirectory)
        squirrel = library.appending(path: "Rime", directoryHint: .isDirectory)
    }
}
