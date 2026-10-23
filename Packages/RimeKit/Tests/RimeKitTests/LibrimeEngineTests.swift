import Foundation
import RimeKit
import Testing

@MainActor
@Suite struct LibrimeEngineTests {
    let engine = TestEngine.engine
    let session: RimeSessionID

    init() throws {
        session = try #require(TestEngine.engine.createSession())
    }

    @Test func sessionUsesTheDeployedSchema() throws {
        defer { engine.destroySession(session) }
        let status = try #require(engine.status(in: session))
        #expect(status.schemaID == "scribe_test")
        #expect(!status.isComposing)
    }

    @Test func typingShowsCompositionAndCandidates() throws {
        defer { engine.destroySession(session) }
        engine.type("ni", in: session)
        let context = engine.context(in: session)
        let composition = try #require(context.composition)
        #expect(composition.preedit == "ni")
        #expect(composition.cursor == 2)
        let menu = try #require(context.menu)
        #expect(menu.candidates.map(\.text) == ["你", "泥", "呢", "尼", "逆"])
        #expect(menu.pageSize == 5)
        #expect(menu.pageNumber == 0)
        #expect(!menu.isLastPage)
        #expect(menu.highlightedIndex == 0)
        #expect(engine.consumeCommit(in: session) == nil)
    }

    @Test func spaceCommitsTheFirstCandidate() {
        defer { engine.destroySession(session) }
        engine.type("nihao", in: session)
        #expect(engine.context(in: session).menu?.candidates.first?.text == "你好")
        #expect(engine.processKey(Key.space, modifiers: 0, in: session))
        #expect(engine.consumeCommit(in: session) == "你好")
        #expect(engine.consumeCommit(in: session) == nil)
        #expect(engine.context(in: session) == EngineContext())
    }

    @Test func selectingOnThePageCommitsThatCandidate() {
        defer { engine.destroySession(session) }
        engine.type("ni", in: session)
        #expect(engine.selectCandidate(onCurrentPage: 2, in: session))
        #expect(engine.consumeCommit(in: session) == "呢")
    }

    @Test func pagingMovesThroughCandidates() throws {
        defer { engine.destroySession(session) }
        engine.type("ni", in: session)
        #expect(engine.processKey(Key.pageDown, modifiers: 0, in: session))
        let second = try #require(engine.context(in: session).menu)
        #expect(second.pageNumber == 1)
        #expect(second.isLastPage)
        #expect(second.candidates.map(\.text) == ["拟", "腻"])

        #expect(engine.changePage(backward: true, in: session))
        #expect(engine.context(in: session).menu?.pageNumber == 0)
    }

    @Test func returnCommitsTheRawInput() {
        defer { engine.destroySession(session) }
        engine.type("nihao", in: session)
        #expect(engine.processKey(Key.returnKey, modifiers: 0, in: session))
        #expect(engine.consumeCommit(in: session) == "nihao")
    }

    @Test func escapeClearsTheComposition() {
        defer { engine.destroySession(session) }
        engine.type("ni", in: session)
        #expect(engine.processKey(Key.escape, modifiers: 0, in: session))
        #expect(engine.consumeCommit(in: session) == nil)
        #expect(engine.context(in: session) == EngineContext())
    }

    @Test func keysAreNotHandledWhenNothingIsComposed() {
        defer { engine.destroySession(session) }
        #expect(!engine.processKey(Key.space, modifiers: 0, in: session))
        #expect(!engine.processKey(Key.returnKey, modifiers: 0, in: session))
    }

    @Test func commitCompositionCommitsTheHighlightedCandidate() {
        defer { engine.destroySession(session) }
        engine.type("ni", in: session)
        #expect(engine.commitComposition(in: session))
        #expect(engine.consumeCommit(in: session) == "你")
    }

    @Test func propertiesRoundTrip() {
        defer { engine.destroySession(session) }
        #expect(engine.property("client_app", in: session) == nil)
        engine.setProperty("client_app", "com.apple.TextEdit", in: session)
        #expect(engine.property("client_app", in: session) == "com.apple.TextEdit")
    }

    /// Frontend config files such as squirrel.yaml are not part of the
    /// workspace; the frontend deploys them itself, with the user's patches.
    @Test func deployingAConfigFileAppliesTheUserPatch() throws {
        defer { engine.destroySession(session) }
        let patch = TestEngine.userDirectory.appending(path: "scribe_frontend_test.custom.yaml")
        try "patch:\n  style/color_scheme: patched\n".write(to: patch, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: patch) }

        #expect(engine.deployConfigFile("scribe_frontend_test.yaml", versionKey: "config_version"))
        let built = try String(
            contentsOf: TestEngine.userDirectory.appending(path: "build/scribe_frontend_test.yaml"),
            encoding: .utf8
        )
        #expect(built.contains("color_scheme: patched"))
    }

    /// As in Squirrel, a user copy of a frontend config file that is not
    /// newer than the shipped one, by its config_version, is moved to the
    /// trash and the shipped one is deployed.
    @Test func anOutdatedUserCopyIsReplaced() throws {
        defer { engine.destroySession(session) }
        let fileManager = FileManager.default
        let userCopy = TestEngine.userDirectory.appending(path: "scribe_frontend_test.yaml")
        let trash = TestEngine.userDirectory.appending(path: "trash", directoryHint: .isDirectory)
        try "config_version: \"0.9\"\nstyle:\n  color_scheme: outdated\n".write(to: userCopy, atomically: true, encoding: .utf8)
        defer {
            try? fileManager.removeItem(at: userCopy)
            try? fileManager.removeItem(at: trash)
        }

        #expect(engine.deployConfigFile("scribe_frontend_test.yaml", versionKey: "config_version"))
        #expect(!fileManager.fileExists(atPath: userCopy.path(percentEncoded: false)))
        #expect(fileManager.fileExists(atPath: trash.appending(path: "scribe_frontend_test.yaml").path(percentEncoded: false)))
        let built = try String(
            contentsOf: TestEngine.userDirectory.appending(path: "build/scribe_frontend_test.yaml"),
            encoding: .utf8
        )
        #expect(built.contains("color_scheme: native"))
    }

    /// scribe.yaml may be missing from older or trimmed shared data.
    @Test func deployingAMissingConfigFileBuildsNothing() {
        defer { engine.destroySession(session) }
        _ = engine.deployConfigFile("scribe_missing_test.yaml", versionKey: "config_version")
        let built = TestEngine.userDirectory.appending(path: "build/scribe_missing_test.yaml")
        #expect(!FileManager.default.fileExists(atPath: built.path(percentEncoded: false)))
    }

    /// glog keeps the app name librime passes it and names log files it
    /// opens later, such as for the first warning, after it.
    @Test func logFilesAreNamedAfterTheApp() throws {
        defer { engine.destroySession(session) }
        let files = try FileManager.default.contentsOfDirectory(atPath: TestEngine.logDirectory.path(percentEncoded: false))
        // Deploying the test schema warns that user.yaml does not exist.
        #expect(files.contains { $0.contains(".log.WARNING.") })
        for file in files {
            #expect(file.hasPrefix(TestEngine.appName + "."), "log file \(file)")
        }
    }

    @Test func preeditOffsetsCountUTF16() throws {
        defer { engine.destroySession(session) }
        engine.type("nihao", in: session)
        let composition = try #require(engine.context(in: session).composition)
        #expect(composition.cursor == composition.preedit.utf16.count)
    }
}
