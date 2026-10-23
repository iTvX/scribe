import Foundation
@testable import ScribeConfig
import Testing

struct InstallationFileTests {
    // MARK: - Parsing

    @Test func readsTheFixture() throws {
        let text = try String(contentsOf: FakeRimeDirectory.fixture.appending(path: "installation.yaml"), encoding: .utf8)
        let file = InstallationFile(parsing: text)
        #expect(file.installationID == FakeRimeDirectory.squirrelInstallationID)
        #expect(file.syncDirectory == FakeRimeDirectory.fixtureSyncDirectory)
        #expect(file.values["distribution_code_name"] == "Squirrel")
        #expect(file.values["distribution_name"] == "鼠鬚管")
    }

    @Test(arguments: [
        ("sync_dir: /Users/me/Rime Sync", "/Users/me/Rime Sync"),
        ("sync_dir: /Users/me/Rime   # moved to iCloud", "/Users/me/Rime"),
        ("sync_dir: /Users/me/Rime\t# tab before the comment", "/Users/me/Rime"),
        ("sync_dir: /Users/me/C#/Rime", "/Users/me/C#/Rime"),
        ("sync_dir:   spaced  ", "spaced"),
        ("sync_dir: 'single quoted'", "single quoted"),
        ("sync_dir: 'it''s here' # comment", "it's here"),
        ("sync_dir: '/a # not a comment'", "/a # not a comment"),
        ("sync_dir: \"double quoted\"", "double quoted"),
        ("sync_dir: \"/a # not a comment\" # comment", "/a # not a comment"),
        (#"sync_dir: "say \"hi\" \\ \/ end""#, #"say "hi" \ / end"#),
        (#"sync_dir: "tab\there\nnew line""#, "tab\there\nnew line"),
        (#"sync_dir: "鼠鬚管""#, "鼠鬚管"),
        (#"sync_dir: "\x41\U0001F600""#, "A😀"),
        (#"sync_dir: "😀""#, "😀"),
        ("sync_dir: \"/Volumes/Fixture Cloud/Rime 同步\"", "/Volumes/Fixture Cloud/Rime 同步"),
        ("sync_dir:\t\"tab after colon\"", "tab after colon"),
    ])
    func parsesScalars(line: String, value: String) {
        #expect(InstallationFile(parsing: line + "\n").syncDirectory == value)
    }

    @Test(arguments: [
        "sync_dir:",
        "sync_dir: ~",
        "sync_dir: null",
        "sync_dir: # only a comment",
        "sync_dir: [a, b]",
        "sync_dir: {a: b}",
        "sync_dir: |",
        "sync_dir: \"unterminated",
        "sync_dir: 'unterminated",
        "sync_dir: \"bad \\u12 escape\"",
        "# sync_dir: commented out",
        "  sync_dir: nested",
        "sync_dir:no space after the colon",
    ])
    func ignoresNonScalars(line: String) {
        #expect(InstallationFile(parsing: line + "\n").syncDirectory == nil)
    }

    @Test func readsOnlyTopLevelKeys() {
        let text = """
            ---
            # librime writes this file
            installation_id: "abc"\r
            nested:
              sync_dir: /not/top/level
              installation_id: nested
            url: http://example.com:8080/path
            sync_dir: /top/level
            ...

            """
        let file = InstallationFile(parsing: text)
        #expect(file.values == ["installation_id": "abc", "url": "http://example.com:8080/path", "sync_dir": "/top/level"])
    }

    // MARK: - Writing

    @Test func writesInstallationIDAndSyncDirectory() {
        #expect(InstallationFile.contents(installationID: "new-id", syncDirectory: nil) == "installation_id: \"new-id\"\n")
        #expect(InstallationFile.contents(installationID: "new-id", syncDirectory: "/Users/me/Rime 同步")
                == "installation_id: \"new-id\"\nsync_dir: \"/Users/me/Rime 同步\"\n")
    }

    @Test(arguments: [
        "/plain/path",
        "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Rime 同步",
        #"/with "quotes" and \backslashes\"#,
        "/with\ttab and\nnewline",
        "/with\u{1}control",
        "/with # hash",
        "'single'",
    ])
    func writtenValuesReadBack(value: String) {
        let text = InstallationFile.contents(installationID: "id", syncDirectory: value)
        let file = InstallationFile(parsing: text)
        #expect(file.installationID == "id")
        #expect(file.syncDirectory == value)
    }

    // MARK: - Import

    @Test func importWritesNewInstallationFileKeepingSyncDirectory() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination)
            .run(makeInstallationID: { "scribe-installation" })

        #expect(report.installationID == "scribe-installation")
        #expect(report.squirrelInstallationID == FakeRimeDirectory.squirrelInstallationID)
        #expect(report.syncDirectory == FakeRimeDirectory.fixtureSyncDirectory)
        let written = try String(contentsOf: fake.destination.appending(path: "installation.yaml"), encoding: .utf8)
        #expect(written == "installation_id: \"scribe-installation\"\nsync_dir: \"/Volumes/Fixture Cloud/Rime 同步\"\n")
        #expect(report.imported.contains(ImportedItem(path: "installation.yaml", kind: .installation)))
    }

    @Test func importGeneratesLowercaseUUIDByDefault() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        #expect(report.installationID != FakeRimeDirectory.squirrelInstallationID)
        #expect(UUID(uuidString: report.installationID) != nil)
        #expect(report.installationID == report.installationID.lowercased())
        let written = try String(contentsOf: fake.destination.appending(path: "installation.yaml"), encoding: .utf8)
        #expect(InstallationFile(parsing: written).installationID == report.installationID)
    }

    @Test func importOmitsSyncDirectoryWhenSourceHasNone() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        try fake.useDefaultSyncDirectory()

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination)
            .run(makeInstallationID: { "scribe-installation" })

        #expect(report.syncDirectory == nil)
        #expect(report.squirrelInstallationID == FakeRimeDirectory.squirrelInstallationID)
        let written = try String(contentsOf: fake.destination.appending(path: "installation.yaml"), encoding: .utf8)
        #expect(written == "installation_id: \"scribe-installation\"\n")
    }

    @Test func importWritesInstallationFileWhenSourceHasNone() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        try fake.setInstallationFile(nil)

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination)
            .run(makeInstallationID: { "scribe-installation" })

        #expect(report.squirrelInstallationID == nil)
        #expect(report.syncDirectory == nil)
        #expect(report.imported.contains(ImportedItem(path: "installation.yaml", kind: .installation)))
        let written = try String(contentsOf: fake.destination.appending(path: "installation.yaml"), encoding: .utf8)
        #expect(written == "installation_id: \"scribe-installation\"\n")
    }

    @Test func importSkipsCustomSyncDirectoryInsideSource() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        let syncDirectory = fake.url("cloud/rime sync").path(percentEncoded: false)
        try fake.setInstallationFile("installation_id: \"\(FakeRimeDirectory.squirrelInstallationID)\"\nsync_dir: \"\(syncDirectory)\"\n")
        try fake.write("# snapshot\n", to: "cloud/rime sync/\(FakeRimeDirectory.squirrelInstallationID)/rime_ice.userdb.txt")
        try fake.write("keep me\n", to: "cloud/notes.txt")

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        #expect(report.syncDirectory == syncDirectory)
        #expect(report.skipped.contains(SkippedItem(path: "cloud/rime sync", reason: .syncDirectory)))
        #expect(!itemExists(fake.destination.appending(path: "cloud/rime sync")))
        #expect(report.imported.contains(ImportedItem(path: "cloud/notes.txt", kind: .other)))
        #expect(report.userDictionaries.snapshots.map(\.lastPathComponent) == ["rime_ice.userdb.txt"])
    }
}
