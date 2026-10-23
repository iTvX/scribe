import Foundation
@testable import ScribeConfig
import Testing

struct UserWordsStagingTests {
    @Test func stagesSnapshotsForTheNextSync() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try Self.write("# first\n", to: root.appending(path: "work/a.userdb.txt"))
        let second = try Self.write("# second\n", to: root.appending(path: "work/other.txt"))
        let sync = root.appending(path: "Scribe/sync", directoryHint: .isDirectory)

        let folder = try stageUserWordsForSync(["rime_ice": first, "wubi86": second], syncDirectory: sync)

        #expect(folder.path(percentEncoded: false) == sync.appending(path: "squirrel-import/").path(percentEncoded: false))
        #expect(try names(in: folder) == ["rime_ice.userdb.txt", "wubi86.userdb.txt"])
        #expect(FileManager.default.contents(atPath: folder.appending(path: "wubi86.userdb.txt").path(percentEncoded: false))
                == Data("# second\n".utf8))

        // Staging again replaces what is there.
        _ = try stageUserWordsForSync(["rime_ice": second], syncDirectory: sync)
        #expect(FileManager.default.contents(atPath: folder.appending(path: "rime_ice.userdb.txt").path(percentEncoded: false))
                == Data("# second\n".utf8))
    }

    @Test func findsTheSyncDirectoryOfAUserDirectory() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scribe = root.appending(path: "Scribe", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scribe, withIntermediateDirectories: true)

        #expect(UserWordsStaging(userDirectory: scribe).syncDirectory.path(percentEncoded: false)
                == scribe.appending(path: "sync/").path(percentEncoded: false))
        #expect(UserWordsStaging.installationID(in: scribe) == nil)

        try Self.write("installation_id: \"scribe-id\"\nsync_dir: \"/Volumes/Cloud/Rime 同步\"\n", to: scribe.appending(path: "installation.yaml"))
        #expect(UserWordsStaging(userDirectory: scribe).syncDirectory.path(percentEncoded: false) == "/Volumes/Cloud/Rime 同步/")
        #expect(UserWordsStaging.installationID(in: scribe) == "scribe-id")
    }

    @Test func waitsUntilScribeBacksUpEachStagedDictionary() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = UserWordsStaging(syncDirectory: root.appending(path: "sync", directoryHint: .isDirectory))
        let posted = Date(timeIntervalSinceNow: -60)
        let staged = staging.folder
        try Self.write("# a\n", to: staged.appending(path: "a.userdb.txt"), modified: posted.addingTimeInterval(-10))
        try Self.write("# b\n", to: staged.appending(path: "b.userdb.txt"), modified: posted.addingTimeInterval(-10))
        let own = staging.syncDirectory.appending(path: "scribe-id", directoryHint: .isDirectory)

        // No backups of Scribe's own yet.
        #expect(staging.pendingNames(installationID: "scribe-id", since: posted) == ["a", "b"])
        #expect(!staging.removeIfMerged(installationID: "scribe-id", since: posted))

        // A backup from before Sync was posted does not count.
        try Self.write("# a\n", to: own.appending(path: "a.userdb.txt"), modified: posted.addingTimeInterval(-5))
        try Self.write("# b\n", to: own.appending(path: "b.userdb.txt"), modified: posted.addingTimeInterval(5))
        #expect(staging.pendingNames(installationID: "scribe-id", since: posted) == ["a"])
        // Another installation's backups do not count either.
        #expect(staging.pendingNames(installationID: "other-id", since: posted) == ["a", "b"])
        #expect(!staging.removeIfMerged(installationID: "scribe-id", since: posted))
        #expect(itemExists(staged))

        try Self.write("# a\n", to: own.appending(path: "a.userdb.txt"), modified: posted.addingTimeInterval(6))
        #expect(staging.pendingNames(installationID: "scribe-id", since: posted).isEmpty)
        #expect(staging.removeIfMerged(installationID: "scribe-id", since: posted))
        #expect(!itemExists(staged))
        #expect(itemExists(own.appending(path: "a.userdb.txt")))
        // Nothing staged is nothing to wait for.
        #expect(staging.removeIfMerged(installationID: "scribe-id", since: posted))
    }

    @Test func leftoverStagingGoesOnceScribeBacksUpAfterIt() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = UserWordsStaging(syncDirectory: root.appending(path: "sync", directoryHint: .isDirectory))
        let stagedAt = Date(timeIntervalSinceNow: -3600)
        try Self.write("# a\n", to: staging.folder.appending(path: "a.userdb.txt"), modified: stagedAt)
        let backup = staging.syncDirectory.appending(path: "scribe-id/a.userdb.txt")

        try Self.write("# a\n", to: backup, modified: stagedAt.addingTimeInterval(-1))
        #expect(!staging.removeIfMerged(installationID: "scribe-id"))

        try Self.write("# a\n", to: backup, modified: stagedAt.addingTimeInterval(1))
        #expect(staging.removeIfMerged(installationID: "scribe-id"))
        #expect(!itemExists(staging.folder))
    }

    private static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "ScribeConfigTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult
    private static func write(_ text: String, to url: URL, modified: Date? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path(percentEncoded: false))
        }
        return url
    }
}
