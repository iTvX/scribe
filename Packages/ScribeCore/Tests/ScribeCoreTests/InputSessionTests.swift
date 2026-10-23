import ScribeCore
import ScribeTestSupport
import Testing

@MainActor
@Suite struct InputSessionTests {
    let engine = FakeRimeEngine()
    let session: InputSession

    init() {
        session = InputSession(engine: engine)
    }

    func type(_ text: String) -> [SessionAction] {
        text.flatMap { session.handle(KeyEvent(Keysym.character($0.unicodeScalars.first!))).actions }
    }

    @Test func typingUpdatesMarkedTextThenCandidates() {
        let first = session.handle(KeyEvent(name: "n")!)
        #expect(first.handled)
        #expect(first.actions.first == .setMarkedText(MarkedText(text: "n", caret: 1)))

        let second = session.handle(KeyEvent(name: "i")!)
        #expect(second.handled)
        #expect(second.actions == [
            .setMarkedText(MarkedText(text: "ni", caret: 2)),
            .showCandidates(CandidateSnapshot(
                entries: [
                    .init(label: "1", text: "你"), .init(label: "2", text: "泥"), .init(label: "3", text: "呢"),
                    .init(label: "4", text: "尼"), .init(label: "5", text: "逆"),
                ],
                isLastPage: false
            )),
        ])
    }

    @Test func withoutInlinePreeditTheWindowShowsTheInput() {
        session.presentation.inlinePreedit = false
        #expect(type("n").first == .setMarkedText(MarkedText(text: "　", caret: 0)))
        // The client keeps its placeholder; only the window changes.
        #expect(type("i") == [
            .showCandidates(CandidateSnapshot(
                entries: [
                    .init(label: "1", text: "你"), .init(label: "2", text: "泥"), .init(label: "3", text: "呢"),
                    .init(label: "4", text: "尼"), .init(label: "5", text: "逆"),
                ],
                isLastPage: false,
                preedit: Preedit(text: "ni‸", selectedRange: 0..<2, caret: 2)
            )),
        ])
    }

    // The client app, as Squirrel handles it.

    @Test func appOptionsAreSetWhenTheSessionStarts() throws {
        session.setClientApp(InputSession.ClientApp(bundleID: "com.apple.Terminal", options: ["ascii_mode": true]))
        _ = session.handle(KeyEvent(name: "a")!)
        let id = try #require(session.currentSessionID)
        #expect(engine.option("ascii_mode", in: id))
        #expect(engine.property("client_app", in: id) == nil)
    }

    @Test func appOptionsAreSetAgainWhenTheAppChanges() throws {
        _ = type("n")
        let id = try #require(session.currentSessionID)
        session.setClientApp(InputSession.ClientApp(bundleID: "org.vim.MacVim", options: ["vim_mode": true]))
        #expect(engine.option("vim_mode", in: id))
        engine.setOption("vim_mode", false, in: id)
        session.setClientApp(InputSession.ClientApp(bundleID: "org.vim.MacVim", options: ["vim_mode": true]))
        #expect(!engine.option("vim_mode", in: id), "the same app again changes nothing")
    }

    @Test func theBundleIDIsReportedWhenAllowed() throws {
        session.setClientApp(InputSession.ClientApp(bundleID: "com.apple.TextEdit", options: [:], reportsBundleID: true))
        let id = try #require(session.currentSessionID)
        #expect(engine.property("client_app", in: id) == "com.apple.TextEdit")
    }

    /// Some text views accept text only after marked text, as Alacritty does.
    @Test func forcedMarkedTextPrecedesADirectCommit() throws {
        let chordTimer = ManualChordTimer()
        let session = InputSession(engine: engine, chordTimer: chordTimer)
        session.setClientApp(InputSession.ClientApp(
            bundleID: "org.alacritty",
            options: ["force_marked_text_for_direct_commit": true, "_chord_typing": true]
        ))
        var actions: [SessionAction] = []
        session.onAsyncActions = { actions += $0 }
        _ = session.handle(KeyEvent(name: "a")!)
        _ = session.handle(KeyEvent(name: "s")!)
        chordTimer.fire()
        #expect(actions == [.setMarkedText(MarkedText(text: "as", caret: 2)), .commit("as")])
    }

    @Test func committingAfterMarkedTextNeedsNoForcing() {
        session.setClientApp(InputSession.ClientApp(bundleID: "org.alacritty", options: ["force_marked_text_for_direct_commit": true]))
        _ = type("ni")
        #expect(session.handle(KeyEvent(Keysym.space)).actions.first == .commit("你"))
    }

    @Test func committingReplacesMarkedTextAndHidesCandidates() {
        _ = type("ni")
        let result = session.handle(KeyEvent(Keysym.space))
        #expect(result.handled)
        // Inserting text replaces the marked text, so no separate update.
        #expect(result.actions == [.commit("你"), .hideCandidates])
    }

    @Test func onlyChangesAreReported() {
        _ = type("ni")
        // Already on the last page of "ni"? No: paging changes candidates only.
        let result = session.handle(KeyEvent(Keysym.pageDown))
        #expect(result.actions.count == 1)
        guard case .showCandidates(let snapshot) = result.actions.first else {
            Issue.record("expected a candidate update")
            return
        }
        #expect(snapshot.pageNumber == 1)
        #expect(snapshot.entries.map(\.text) == ["拟", "腻"])
    }

    @Test func escapeClearsMarkedTextAndCandidates() {
        _ = type("ni")
        #expect(session.handle(KeyEvent(Keysym.escape)).actions == [.setMarkedText(.empty), .hideCandidates])
    }

    /// So that the window can show the input alone.
    @Test func aCompositionWithoutCandidatesStillHasASnapshot() {
        session.presentation.inlinePreedit = false
        // "x" spells nothing in the test dictionary.
        let result = session.handle(KeyEvent(name: "x")!)
        #expect(result.actions == [
            .setMarkedText(MarkedText(text: "　", caret: 0)),
            .showCandidates(CandidateSnapshot(
                entries: [],
                preedit: Preedit(text: "x‸", selectedRange: 0..<1, caret: 1)
            )),
        ])
    }

    @Test func idleKeysAreNotHandled() {
        let result = session.handle(KeyEvent(Keysym.space))
        #expect(!result.handled)
        #expect(result.actions.isEmpty)
    }

    @Test func keysPassThroughWhileDeploying() {
        engine.isInMaintenance = true
        let result = session.handle(KeyEvent(name: "n")!)
        #expect(!result.handled)
        #expect(result.actions.isEmpty)
    }

    @Test func commitCompositionCommitsTheUnconvertedInput() {
        _ = type("nihao")
        #expect(session.commitComposition() == [.commit("nihao"), .hideCandidates])
        #expect(session.commitComposition().isEmpty)
    }

    @Test func selectCandidateCommitsIt() {
        _ = type("ni")
        #expect(session.selectCandidate(at: 1) == [.commit("泥"), .hideCandidates])
    }

    @Test func clearCompositionDiscardsIt() {
        _ = type("ni")
        #expect(session.clearComposition() == [.setMarkedText(.empty), .hideCandidates])
    }

    @Test func aDroppedSessionIsReplaced() {
        _ = type("ni")
        session.close()
        #expect(session.handle(KeyEvent(Keysym.space)).handled == false)
        #expect(type("ni").contains(.setMarkedText(MarkedText(text: "ni", caret: 2))))
    }
}
