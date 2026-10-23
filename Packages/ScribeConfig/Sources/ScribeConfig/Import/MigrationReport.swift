import Foundation

/// What an import copied, left out and found worth pointing out.
public struct MigrationReport: Sendable, Equatable {
    public var source: URL
    public var destination: URL
    /// Where a non-empty destination was moved before the import, or nil.
    public var backup: URL?
    /// Sorted by path.
    public var imported: [ImportedItem]
    /// Sorted by path.
    public var skipped: [SkippedItem]
    /// The installation ID written to Scribe's new `installation.yaml`.
    public var installationID: String
    /// Squirrel's installation ID, which names its folder in the sync directory.
    public var squirrelInstallationID: String?
    /// The custom `sync_dir` carried over, or nil for librime's default.
    public var syncDirectory: String?
    public var userDictionaries: UserDictionaryImport
    /// In path and line order.
    public var notices: [MigrationNotice]
}

/// A file, symbolic link or git repository the import copied.
public struct ImportedItem: Sendable, Equatable {
    /// Relative to the source, "/" separated; ".git" for the repository.
    public var path: String
    public var kind: ImportedFileKind

    public var effect: ImportEffect { kind.effect }
}

/// Something in the source the import did not copy.
public struct SkippedItem: Sendable, Equatable {
    /// Relative to the source, "/" separated.
    public var path: String
    public var reason: SkipReason
}

public enum SkipReason: String, Sendable, CaseIterable {
    /// `build/` at the root; Scribe deploys its own.
    case buildOutput
    /// `*.userdb`, `*.userdb.kct` and `*.userdb.txt` at the root. Their words
    /// are exported from a copy and merged into Scribe's own dictionaries.
    case userDictionary
    /// `sync/` at the root, or a custom `sync_dir` inside the source.
    case syncDirectory
    /// `trash/` at the root, where librime keeps files it replaced.
    case trash
    /// `.DS_Store` anywhere.
    case systemFile
}

/// The user dictionaries found in the source, and the snapshots Squirrel
/// last synced of them.
public struct UserDictionaryImport: Sendable, Equatable {
    /// Names from `<name>.userdb` and `<name>.userdb.kct`, sorted.
    public var dictionaries: [String]
    /// `<sync dir>/<Squirrel installation ID>/*.userdb.txt`, sorted. Used for
    /// dictionaries that cannot be exported, and as they are for names
    /// without a dictionary.
    public var snapshots: [URL]

    public init(dictionaries: [String], snapshots: [URL]) {
        self.dictionaries = dictionaries
        self.snapshots = snapshots
    }
}

/// Something in the imported directory that may not work the way it did in Squirrel.
public enum MigrationNotice: Sendable, Equatable {
    /// A Lua line mentions Squirrel, so it may branch on the frontend.
    /// `line` is 1-based and `text` is the trimmed line.
    case luaChecksFrontend(file: String, line: Int, text: String)
    /// The configuration of another Rime frontend, which Scribe never reads.
    case otherFrontendConfig(file: String)
    /// A symbolic link with an absolute target, or a relative one that leaves the source.
    case symbolicLink(path: String, target: String)
}
