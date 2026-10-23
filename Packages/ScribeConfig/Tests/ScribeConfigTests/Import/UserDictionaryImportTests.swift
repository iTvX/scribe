import Foundation
@testable import ScribeConfig
import Testing

struct UserDictionaryImportTests {
    @Test func findsSnapshotsInDefaultSyncDirectory() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        try fake.useDefaultSyncDirectory()
        let folder = "sync/\(FakeRimeDirectory.squirrelInstallationID)"
        try fake.write("# snapshot\n", to: "\(folder)/wubi86.userdb.txt")
        try fake.write("not a snapshot\n", to: "\(folder)/notes.txt")
        try fake.write("# another installation\n", to: "sync/another-installation/luna_pinyin.userdb.txt")

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        #expect(report.userDictionaries.dictionaries == ["rime_ice", "wubi86"])
        #expect(report.userDictionaries.snapshots.map { $0.path(percentEncoded: false) } == [
            fake.url("\(folder)/rime_ice.userdb.txt").path(percentEncoded: false),
            fake.url("\(folder)/wubi86.userdb.txt").path(percentEncoded: false),
        ])
        #expect(!report.notices.contains(.userDictionariesNotSynced(["rime_ice", "wubi86"])))
    }

    @Test func findsSnapshotsInCustomSyncDirectory() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        let cloud = fake.root.appending(path: "Cloud Sync", directoryHint: .isDirectory)
        let snapshot = cloud.appending(path: "\(FakeRimeDirectory.squirrelInstallationID)/rime_ice.userdb.txt")
        try FileManager.default.createDirectory(at: snapshot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# snapshot\n".utf8).write(to: snapshot)
        try fake.setInstallationFile("""
            installation_id: "\(FakeRimeDirectory.squirrelInstallationID)"
            sync_dir: "\(cloud.path(percentEncoded: false))"

            """)

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        #expect(report.syncDirectory == cloud.path(percentEncoded: false))
        #expect(report.userDictionaries.snapshots.map { $0.path(percentEncoded: false) } == [snapshot.path(percentEncoded: false)])
        #expect(report.notices.allSatisfy { if case .userDictionariesNotSynced = $0 { false } else { true } })
    }

    @Test func reportsDictionariesWithoutSnapshots() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        try fake.useDefaultSyncDirectory()
        try FileManager.default.removeItem(at: fake.url("sync"))

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        #expect(report.userDictionaries.snapshots.isEmpty)
        #expect(report.notices.last == .userDictionariesNotSynced(["rime_ice", "wubi86"]))
    }

    @Test func noDictionariesNoNotice() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        for path in ["rime_ice.userdb", "wubi86.userdb.kct"] {
            try FileManager.default.removeItem(at: fake.url(path))
        }

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        #expect(report.userDictionaries.dictionaries.isEmpty)
        #expect(report.notices.allSatisfy { if case .userDictionariesNotSynced = $0 { false } else { true } })
    }

    @Test func restoresSnapshotsInOrderAndCollectsFailures() async {
        let folder = URL(filePath: "/snapshots", directoryHint: .isDirectory)
        let snapshots = ["a", "b", "c", "d"].map { folder.appending(path: "\($0).userdb.txt") }
        let dictionaries = UserDictionaryImport(dictionaries: ["a", "b", "c", "d"], snapshots: snapshots)
        let restorer = RecordingRestorer(failures: [
            "b.userdb.txt": DescribedFailure(),
            "d.userdb.txt": PlainFailure.broken,
        ])

        let failures = await dictionaries.restore(using: restorer)

        #expect(await restorer.restored == snapshots)
        #expect(failures.map(\.snapshot) == [snapshots[1], snapshots[3]])
        #expect(failures.map(\.message) == ["快照损坏", "broken"])
    }
}

private actor RecordingRestorer: UserDictionaryRestoring {
    let failures: [String: any Error]
    private(set) var restored: [URL] = []

    init(failures: [String: any Error]) {
        self.failures = failures
    }

    func restoreUserDictionary(from snapshot: URL) async throws {
        restored.append(snapshot)
        if let failure = failures[snapshot.lastPathComponent] {
            throw failure
        }
    }
}

private struct DescribedFailure: LocalizedError {
    var errorDescription: String? { "快照损坏" }
}

private enum PlainFailure: Error {
    case broken
}
