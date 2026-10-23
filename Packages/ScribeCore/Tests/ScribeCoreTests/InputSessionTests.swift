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
                isLastPage: false,
                preedit: Preedit(text: "ni", selectedRange: 0..<2, caret: 2)
            )),
        ])
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

    @Test func aCompositionWithoutCandidatesStillHasASnapshot() {
        // "x" spells nothing in the test dictionary.
        let result = session.handle(KeyEvent(name: "x")!)
        #expect(result.actions == [
            .setMarkedText(MarkedText(text: "x", caret: 1)),
            .showCandidates(CandidateSnapshot(
                entries: [],
                preedit: Preedit(text: "x", selectedRange: 0..<1, caret: 1)
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
