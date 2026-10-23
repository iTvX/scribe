import Foundation
import RimeKit
@testable import ScribeConfig
import Testing

/// librime is one engine per process, so everything that runs it happens
/// inside one synchronous main-actor test, which starts and stops it.
@MainActor
struct UserWordsMigratorTests {
    @Test func movesLearnedWordsFromSquirrelToScribe() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "ScribeConfigTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let shared = try Self.learningSharedData(in: root)
        let squirrel = root.appending(path: "Rime", directoryHint: .isDirectory)
        let scribe = root.appending(path: "Scribe", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: squirrel, withIntermediateDirectories: true)
        try Data("installation_id: \"squirrel-e2e\"\n".utf8).write(to: squirrel.appending(path: "installation.yaml"))
        let engine = LibrimeEngine.shared
        #expect(!engine.isRunning)
        defer { engine.stop() }

        // 1. Squirrel learns that 呢 comes first.
        engine.start(RimeConfiguration(sharedDataDirectory: shared, userDataDirectory: squirrel, minimumLogLevel: 2))
        #expect(engine.deploy())
        let learning = try #require(engine.createSession())
        #expect(Self.candidates("ni", engine, learning) == ["你", "泥", "呢", "尼", "逆"])
        for _ in 0..<3 {
            Self.choose("呢", for: "ni", engine, learning)
        }
        #expect(Self.candidates("ni", engine, learning).first == "呢")
        engine.destroySession(learning)
        engine.stop()
        let before = try snapshot(of: squirrel)

        // 2. Import the directory, then export and merge its user words.
        let report = try RimeDirectoryImporter(source: squirrel, destination: scribe).run()
        #expect(report.userDictionaries.dictionaries == ["scribe_test"])
        let migrator = UserWordsMigrator(engine: engine)
        let work = root.appending(path: "work", directoryHint: .isDirectory)
        let exported = migrator.exportSnapshots(report.userDictionaries, from: squirrel, workDirectory: work)
        #expect(exported.failed.isEmpty)
        #expect(exported.snapshots.keys.sorted() == ["scribe_test"])
        #expect(exported.snapshots["scribe_test"]?.deletingLastPathComponent().lastPathComponent == UserWordsStaging.folderName)
        #expect(!engine.isRunning)
        let result = migrator.restore(exported.snapshots, into: scribe)
        #expect(result == UserWordsMigrationResult(merged: ["scribe_test"], failed: [:]))
        #expect(!engine.isRunning)
        #expect(fileManager.fileExists(atPath: scribe.appending(path: "scribe_test.userdb").path(percentEncoded: false)))

        // 3. Scribe ranks 呢 first too.
        engine.start(RimeConfiguration(sharedDataDirectory: shared, userDataDirectory: scribe, minimumLogLevel: 2))
        #expect(engine.deploy())
        let typing = try #require(engine.createSession())
        #expect(Self.candidates("ni", engine, typing).first == "呢")
        engine.destroySession(typing)
        engine.stop()

        // 4. Nothing in Squirrel's directory changed.
        #expect(try snapshot(of: squirrel) == before)
    }

    @Test func reportsDictionariesThatCannotBeExported() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "ScribeConfigTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let squirrel = root.appending(path: "Rime", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: squirrel, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try Data([0x4B, 0x43]).write(to: squirrel.appending(path: "old.userdb.kct"))
        let synced = root.appending(path: "sync/squirrel/synced.userdb.txt")
        let extra = root.appending(path: "sync/squirrel/extra.userdb.txt")
        try fileManager.createDirectory(at: synced.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# snapshot\n".utf8).write(to: synced)
        try Data("# snapshot\n".utf8).write(to: extra)
        let dictionaries = UserDictionaryImport(dictionaries: ["ghost", "old", "synced"], snapshots: [extra, synced])

        let exported = UserWordsMigrator().exportSnapshots(dictionaries, from: squirrel, workDirectory: root.appending(path: "work"))

        // Nothing could be copied, so librime never started.
        #expect(exported.snapshots == ["synced": synced, "extra": extra])
        #expect(exported.failed.keys.sorted() == ["ghost", "old"])
        #expect(exported.failed["old"]?.contains("old.userdb.kct") == true)
        #expect(exported.failed["ghost"]?.contains("ghost.userdb") == true)
        #expect(!LibrimeEngine.shared.isRunning)
    }

    @Test func restoringNothingLeavesTheEngineAlone() {
        #expect(UserWordsMigrator().restore([:], into: URL(filePath: "/nonexistent/Scribe")) == UserWordsMigrationResult(merged: [], failed: [:]))
        #expect(!LibrimeEngine.shared.isRunning)
    }

    /// Tests/Fixtures/rime with learning turned on.
    private static func learningSharedData(in root: URL) throws -> URL {
        let shared = root.appending(path: "shared", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: FakeRimeDirectory.fixture.deletingLastPathComponent().appending(path: "rime"), to: shared)
        let schema = shared.appending(path: "scribe_test.schema.yaml")
        let text = try String(contentsOf: schema, encoding: .utf8)
        let learning = text.replacingOccurrences(of: "enable_user_dict: false", with: "enable_user_dict: true")
        try #require(learning != text)
        try learning.write(to: schema, atomically: true, encoding: .utf8)
        return shared
    }

    private static func candidates(_ input: String, _ engine: LibrimeEngine, _ session: RimeSessionID) -> [String] {
        type(input, engine, session)
        defer { engine.clearComposition(in: session) }
        return engine.context(in: session).menu?.candidates.map(\.text) ?? []
    }

    /// Types `input` and selects `text` wherever it is on the first page.
    private static func choose(_ text: String, for input: String, _ engine: LibrimeEngine, _ session: RimeSessionID) {
        type(input, engine, session)
        let index = engine.context(in: session).menu?.candidates.firstIndex { $0.text == text }
        #expect(index != nil)
        #expect(engine.selectCandidate(onCurrentPage: index ?? 0, in: session))
        #expect(engine.consumeCommit(in: session) == text)
    }

    private static func type(_ input: String, _ engine: LibrimeEngine, _ session: RimeSessionID) {
        for character in input.unicodeScalars {
            _ = engine.processKey(Int32(character.value), modifiers: 0, in: session)
        }
    }
}
