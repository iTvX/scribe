import Foundation
import librime
import RimeKit
import Testing

/// Uses the shared test engine without restarting it and without committing
/// words: the test schema does not learn, so a user dictionary created here
/// never changes the candidate order other tests expect.
@MainActor
@Suite struct LibrimeLeversTests {
    let engine = TestEngine.engine

    /// A snapshot of `scribe_test.userdb` as another installation would write it.
    static let snapshot = """
        # Rime user dictionary
        #@/db_name\tscribe_test
        #@/db_type\tuserdb
        #@/rime_version\t1.17.0
        #@/tick\t3
        #@/user_id\tsquirrel-test
        ni \t呢\tc=3 d=2.98506 t=3

        """

    @Test func customizeWritesPatchEntries() throws {
        #expect(engine.customize("levers_test", [
            (key: "menu/page_size", value: .int(9)),
            (key: "style/inline_preedit", value: .bool(true)),
            (key: "ratio", value: .double(1.5)),
            (key: "label", value: .string("two words")),
            (key: "list", value: .yaml("[a, b]")),
            (key: "map", value: .yaml("{k: v, n: 1}")),
        ]))
        let text = try customFile("levers_test")
        #expect(text.contains("customization:\n"))
        #expect(text.contains("  generator: Scribe\n"))
        #expect(patch(of: text) == """
            patch:
              label: "two words"
              list:
                - a
                - b
              map:
                k: v
                n: 1
              "menu/page_size": 9
              ratio: 1.500000
              "style/inline_preedit": true
            """)

        #expect(engine.customize("levers_test", [
            (key: "label", value: .string("changed")),
            (key: "extra", value: .bool(false)),
        ], generator: "ScribeTests"))
        let updated = try customFile("levers_test")
        #expect(updated.contains("  generator: ScribeTests\n"))
        #expect(patch(of: updated) == """
            patch:
              extra: false
              label: changed
              list:
                - a
                - b
              map:
                k: v
                n: 1
              "menu/page_size": 9
              ratio: 1.500000
              "style/inline_preedit": true
            """)
    }

    @Test func customizeRejectsBadValues() {
        #expect(!engine.customize("levers_bad", [(key: "big", value: .int(Int(Int32.max) + 1))]))
        #expect(!engine.customize("levers_bad", [(key: "list", value: .yaml("[unclosed"))]))
        #expect(!FileManager.default.fileExists(atPath: userDirectory().appending(path: "levers_bad.custom.yaml").path(percentEncoded: false)))
    }

    @Test func runsDeploymentTasks() {
        #expect(engine.runTask("installation_update"))
        #expect(!engine.runTask("no_such_task"))
    }

    @Test func restoresListsAndBacksUpUserDictionaries() throws {
        // With installation.yaml in place, the sync directory is the user
        // directory's own rather than one relative to the working directory.
        #expect(engine.runTask("installation_update"))
        let snapshot = try writeSnapshot(Self.snapshot)
        defer { try? FileManager.default.removeItem(at: snapshot) }

        #expect(engine.restoreUserDictionary(from: snapshot))
        #expect(engine.userDictionaryNames().contains("scribe_test"))
        #expect(FileManager.default.fileExists(atPath: userDirectory().appending(path: "scribe_test.userdb").path(percentEncoded: false)))

        let syncDirectory = try #require(engine.userDataSyncDirectory)
        #expect(syncDirectory.path(percentEncoded: false).hasPrefix(userDirectory().appending(path: "sync/").path(percentEncoded: false)))
        let backup = try #require(engine.backupUserDictionary("scribe_test"))
        #expect(backup.deletingLastPathComponent().path(percentEncoded: false) == syncDirectory.path(percentEncoded: false))
        #expect(backup.lastPathComponent == "scribe_test.userdb.txt")
        let text = try String(contentsOf: backup, encoding: .utf8)
        #expect(text.hasPrefix("# Rime user dictionary\n"))
        #expect(text.contains("#@/db_name\tscribe_test\n"))
        #expect(text.contains("ni \t呢\tc=3 "))

        #expect(engine.restoreUserDictionary(from: backup))
        #expect(engine.backupUserDictionary("no_such_dictionary") == nil)
    }

    @Test func restoringGarbageFailsCleanly() throws {
        let garbage = try writeSnapshot("not a snapshot\n\u{0}\u{1}\n")
        let missing = garbage.deletingLastPathComponent().appending(path: "missing.userdb.txt")
        let snapshot = try writeSnapshot(Self.snapshot)
        defer {
            try? FileManager.default.removeItem(at: garbage)
            try? FileManager.default.removeItem(at: snapshot)
        }

        #expect(!engine.restoreUserDictionary(from: garbage))
        #expect(!engine.restoreUserDictionary(from: missing))
        #expect(engine.restoreUserDictionary(from: snapshot))
    }

    /// The test engine's user data directory.
    private func userDirectory() -> URL {
        var buffer = [CChar](repeating: 0, count: 4096)
        rime_get_api_stdbool().pointee.get_user_data_dir_s(&buffer, buffer.count)
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    private func customFile(_ configID: String) throws -> String {
        try String(contentsOf: userDirectory().appending(path: "\(configID).custom.yaml"), encoding: .utf8)
    }

    /// The `patch:` map and everything after it; levers writes no final newline.
    private func patch(of text: String) -> String? {
        text.range(of: "patch:\n").map { String(text[$0.lowerBound...]) }
    }

    private func writeSnapshot(_ text: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "scribe-levers-\(UUID().uuidString).userdb.txt", directoryHint: .notDirectory)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
