import Foundation

/// Copies snapshots to `<syncDirectory>/squirrel-import/` so a running Scribe merges them on its next sync.
public func stageUserWordsForSync(_ snapshots: [String: URL], syncDirectory: URL) throws -> URL {
    try UserWordsStaging(syncDirectory: syncDirectory).stage(snapshots)
}

/// Snapshots waiting in `<sync dir>/squirrel-import/` for Scribe's next sync.
///
/// librime's sync merges `<sync dir>/*/<name>.userdb.txt` into each user
/// dictionary that exists, then backs the dictionary up to
/// `<sync dir>/<installation ID>/<name>.userdb.txt`. A backup newer than a
/// staged snapshot means it has been merged. The sync directory is often
/// shared between machines, so the staging folder goes once that happened.
public struct UserWordsStaging: Equatable, Sendable {
    /// Also the installation ID of the export that writes the snapshots.
    public static let folderName = "squirrel-import"

    public var syncDirectory: URL

    public var folder: URL {
        syncDirectory.appending(path: Self.folderName, directoryHint: .isDirectory)
    }

    public init(syncDirectory: URL) {
        self.syncDirectory = syncDirectory
    }

    /// The staging of the Scribe user directory `userDirectory`, in the
    /// `sync_dir` its installation.yaml names or in `<userDirectory>/sync`.
    public init(userDirectory: URL) {
        let installation = Self.installationFile(in: userDirectory)
        if let custom = installation?.syncDirectory, custom.hasPrefix("/") {
            syncDirectory = URL(filePath: custom, directoryHint: .isDirectory)
        } else {
            syncDirectory = userDirectory.appending(path: "sync", directoryHint: .isDirectory)
        }
    }

    /// The installation ID in `userDirectory`'s installation.yaml.
    public static func installationID(in userDirectory: URL) -> String? {
        installationFile(in: userDirectory)?.installationID
    }

    /// Copies each snapshot in as `<name>.userdb.txt`, replacing an earlier one. Returns the folder.
    @discardableResult
    public func stage(_ snapshots: [String: URL]) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, snapshot) in snapshots {
            let staged = folder.appending(path: "\(name).userdb.txt", directoryHint: .notDirectory)
            if fileManager.fileExists(atPath: staged.path(percentEncoded: false)) {
                try fileManager.removeItem(at: staged)
            }
            try fileManager.copyItem(at: snapshot, to: staged)
        }
        return folder
    }

    /// Names staged but not merged yet: those without a backup of Scribe's
    /// own newer than `since`, or than the staged snapshot when `since` is nil.
    public func pendingNames(installationID: String, since: Date? = nil) -> [String] {
        let fileManager = FileManager.default
        let staged = (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        let own = syncDirectory.appending(path: installationID, directoryHint: .isDirectory)
        return staged.filter { $0.hasSuffix(".userdb.txt") }.sorted().filter { file in
            guard let merged = Self.modificationDate(of: own.appending(path: file)),
                  let threshold = since ?? Self.modificationDate(of: folder.appending(path: file))
            else { return true }
            return merged <= threshold
        }.map { String($0.dropLast(".userdb.txt".count)) }
    }

    /// Removes the staging folder once nothing in it is pending. Returns
    /// whether the folder is gone.
    @discardableResult
    public func removeIfMerged(installationID: String, since: Date? = nil) -> Bool {
        let path = folder.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return true }
        guard pendingNames(installationID: installationID, since: since).isEmpty else { return false }
        return (try? FileManager.default.removeItem(at: folder)) != nil
    }

    private static func installationFile(in userDirectory: URL) -> InstallationFile? {
        (try? String(contentsOf: userDirectory.appending(path: "installation.yaml"), encoding: .utf8))
            .map(InstallationFile.init(parsing:))
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate] as? Date
    }
}
