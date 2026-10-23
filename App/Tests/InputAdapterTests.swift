import AppKit
import ScribeCore
import ScribeTestSupport
import Testing

/// Records what the adapter does to the client and the candidate window, in
/// order.
@MainActor
final class CallLog: TextClient, CandidatePresenting {
    var calls: [String] = []

    func insertText(_ text: String) {
        calls.append("insert \(text)")
    }

    func setMarkedText(_ text: String, caret: Int) {
        calls.append("mark \(text)|\(caret)")
    }

    func caretRect() -> NSRect {
        calls.append("caret")
        return NSRect(x: 100, y: 400, width: 1, height: 18)
    }

    func show(_ snapshot: CandidateSnapshot, near caretRect: NSRect) {
        calls.append("show " + snapshot.entries.map(\.text).joined(separator: " "))
    }

    func hide() {
        calls.append("hide")
    }
}

@MainActor
@Suite struct InputAdapterTests {
    let log = CallLog()
    let adapter: InputAdapter

    init() {
        adapter = InputAdapter(session: InputSession(engine: FakeRimeEngine()), candidates: log)
    }

    func key(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        )!
    }

    func input(_ event: NSEvent) -> KeyInput {
        KeyInput(event)
    }

    func flags(_ flags: NSEvent.ModifierFlags, code: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        )!
    }

    @Test func typingAndSelectingCallsTheClientInOrder() {
        #expect(adapter.handle(input(key("n", code: 45)), client: log))
        #expect(adapter.handle(input(key("i", code: 34)), client: log))
        #expect(adapter.handle(input(key(" ", code: 49)), client: log))
        #expect(log.calls == [
            // Marked text first, so the caret rect for the window is current.
            "mark n|1", "caret", "show 你好 你 泥 呢 尼",
            "mark ni|2", "caret", "show 你 泥 呢 尼 逆",
            "insert 你", "hide",
        ])
    }

    @Test func noCandidatesHidesTheWindow() {
        // "x" spells nothing in the test dictionary; the preedit is inline.
        #expect(adapter.handle(input(key("x", code: 7)), client: log))
        #expect(log.calls == ["mark x|1", "hide"])
    }

    @Test func idleKeysReachTheClient() {
        #expect(!adapter.handle(input(key(" ", code: 49)), client: log))
        #expect(!adapter.handle(input(key("\r", code: 36)), client: log))
        #expect(log.calls.isEmpty)
    }

    @Test func eventsAreCopiedFaithfully() {
        let event = key("A", code: 0, flags: [.shift, .command])
        #expect(KeyInput(event) == KeyInput(kind: .keyDown, keyCode: 0, charactersIgnoringModifiers: "A", flags: [.shift, .command]))
        #expect(KeyInput(flags(.option, code: 58)).kind == .flagsChanged)
    }

    @Test func shortcutsReachTheClient() {
        #expect(!adapter.handle(input(key("c", code: 8, flags: .command)), client: log))
        #expect(log.calls.isEmpty)
    }

    @Test func modifierChangesAlwaysReachTheClient() {
        #expect(!adapter.handle(input(flags(.shift, code: 56)), client: log))
        #expect(!adapter.handle(input(flags([], code: 56)), client: log))
        #expect(log.calls.isEmpty)
    }

    @Test func commitCompositionCommitsAndHides() {
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        _ = adapter.handle(input(key("i", code: 34)), client: log)
        log.calls.removeAll()
        adapter.commitComposition(client: log)
        #expect(log.calls == ["insert 你", "hide"])
    }

    @Test func deactivatingCommitsAndHides() {
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        _ = adapter.handle(input(key("i", code: 34)), client: log)
        log.calls.removeAll()
        adapter.deactivate(client: log)
        #expect(log.calls == ["insert 你", "hide", "hide"])
    }

    @Test func pageDownUpdatesOnlyTheWindow() {
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        _ = adapter.handle(input(key("i", code: 34)), client: log)
        log.calls.removeAll()
        #expect(adapter.handle(input(key("\u{F72D}", code: 121)), client: log))
        #expect(log.calls == ["caret", "show 拟 腻"])
    }
}
