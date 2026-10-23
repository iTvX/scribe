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
    }

    @Test func listsDictionariesWithoutSnapshots() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        try fake.useDefaultSyncDirectory()
        try FileManager.default.removeItem(at: fake.url("sync"))

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        #expect(report.userDictionaries == UserDictionaryImport(dictionaries: ["rime_ice", "wubi86"], snapshots: []))
    }

    @Test func ignoresLeftoverTemporaryDictionary() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        // librime's restore works in .temp.userdb and removes it afterwards;
        // an interrupted restore can leave it behind.
        try fake.write("MANIFEST-000002\n", to: ".temp.userdb/CURRENT")

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        #expect(report.userDictionaries.dictionaries == ["rime_ice", "wubi86"])
        #expect(report.skipped.contains(SkippedItem(path: ".temp.userdb", reason: .userDictionary)))
    }
}
