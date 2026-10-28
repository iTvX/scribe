import AppKit
import RimeKit
import ScribeConfig
import ScribeCore
import ScribeTestSupport
import ScribeUI
import Testing

/// Records what the adapter does to the client and the candidate window, in
/// order.
@MainActor
final class CallLog: TextClient, CandidatePresenting {
    var calls: [String] = []
    weak var delegate: (any CandidatePanelDelegate)?
    var bundleIdentifier = "com.example.Editor"

    func insertText(_ text: String) {
        calls.append("insert \(text)")
    }

    func setMarkedText(_ text: MarkedText) {
        calls.append("mark \(text.text)|\(text.caret)")
    }

    func caretRect() -> NSRect {
        calls.append("caret")
        return NSRect(x: 100, y: 400, width: 1, height: 18)
    }

    func show(_ snapshot: CandidateSnapshot, near caretRect: NSRect) {
        calls.append("show " + snapshot.entries.map(\.text).joined(separator: " "))
    }

    func showStatus(_ message: String, near caretRect: NSRect) {
        calls.append("status \(message)")
    }

    func hide() {
        calls.append("hide")
    }
}

@MainActor
@Suite struct InputAdapterTests {
    let log = CallLog()
    let engine = FakeRimeEngine()
    let chordTimer = ManualChordTimer()
    let session: InputSession
    let adapter: InputAdapter
    /// Only passed back to the delegate; never shown.
    let panel = CandidatePanel()

    init() {
        session = InputSession(engine: engine, chordTimer: chordTimer)
        adapter = InputAdapter(session: session, candidates: log)
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

    /// Squirrel creates the Rime session with the client's controller and
    /// keeps it until the controller goes away, so a key never waits for
    /// librime to load the schema and open the user dictionaries.
    @Test func activatingStartsTheSessionBeforeTheFirstKey() {
        adapter.activate(capsLockOn: false)
        #expect(engine.createdSessionCount == 1)
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        #expect(engine.createdSessionCount == 1)
    }

    @Test func theSessionOutlivesADeactivation() {
        adapter.activate(capsLockOn: false)
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        adapter.deactivate(client: log)
        adapter.activate(capsLockOn: false)
        _ = adapter.handle(input(key("i", code: 34)), client: log)
        #expect(engine.createdSessionCount == 1)
        #expect(engine.liveSessionCount == 1)
    }

    @Test func closingEndsTheSession() {
        adapter.activate(capsLockOn: false)
        adapter.close()
        #expect(engine.liveSessionCount == 0)
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
        #expect(KeyInput(event) == KeyInput(kind: .keyDown, keyCode: 0, characters: "A", charactersIgnoringModifiers: "A", flags: [.shift, .command]))
        #expect(KeyInput(flags(.option, code: 58)).kind == .flagsChanged)
    }

    @Test func commandShortcutsNeverReachRime() {
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        #expect(!adapter.handle(input(key("c", code: 8, flags: .command)), client: log))
        #expect(engine.processedKeys == [KeyEvent(0x6e)])
        // The composition is untouched.
        #expect(adapter.handle(input(key("i", code: 34)), client: log))
        #expect(log.calls.contains("mark ni|2"))
    }

    @Test func modifierChangesGoToRimeAndTheClient() {
        #expect(!adapter.handle(input(flags(.shift, code: 56)), client: log))
        #expect(!adapter.handle(input(flags([], code: 56)), client: log))
        #expect(engine.processedKeys == [
            KeyEvent(Keysym.shiftL, modifiers: .shift),
            KeyEvent(Keysym.shiftL, modifiers: .release),
        ])
        #expect(log.calls.isEmpty)
    }

    @Test func unchangedModifiersAreConsumed() {
        _ = adapter.handle(input(flags(.shift, code: 56)), client: log)
        #expect(adapter.handle(input(flags(.shift, code: 56)), client: log))
        #expect(engine.processedKeys.count == 1)
    }

    /// Activation brings no modifier event, so the Caps Lock state comes
    /// from the hardware; otherwise the next toggle would look like no
    /// change and be dropped.
    @Test func capsLockStateIsSeededOnActivation() {
        adapter.activate(capsLockOn: true)
        #expect(!adapter.handle(input(flags([], code: 57)), client: log))
        #expect(engine.processedKeys == [KeyEvent(Keysym.capsLock, modifiers: .capsLock)])
    }

    /// keyboard_layout, as Squirrel applies it on activation.
    @Test(arguments: [
        (KeyboardLayout.last, nil),
        (.named("com.apple.keylayout.ABC"), "com.apple.keylayout.ABC"),
        (KeyboardLayout(squirrel: "default"), "com.apple.keylayout.ABC"),
        (KeyboardLayout(squirrel: "USExtended"), "com.apple.keylayout.USExtended"),
    ] as [(KeyboardLayout, String?)])
    func activationNamesTheKeyboardLayoutToUse(layout: KeyboardLayout, expected: String?) {
        adapter.configuration.keyboardLayout = layout
        #expect(adapter.activate(capsLockOn: false) == expected)
    }

    @Test func commitCompositionCommitsTheUnconvertedInput() {
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        _ = adapter.handle(input(key("i", code: 34)), client: log)
        log.calls.removeAll()
        adapter.commitComposition(client: log)
        #expect(log.calls == ["insert ni", "hide"])
    }

    /// For when a script switches the input source and InputMethodKit does
    /// not deactivate Scribe, as on macOS 26.
    @Test func finishingCommitsToTheLastClient() {
        adapter.finishComposition()
        #expect(log.calls.isEmpty)
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        _ = adapter.handle(input(key("i", code: 34)), client: log)
        log.calls.removeAll()
        adapter.finishComposition()
        #expect(log.calls == ["insert ni", "hide", "hide"])
    }

    @Test func deactivatingNeverDropsText() {
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        _ = adapter.handle(input(key("i", code: 34)), client: log)
        log.calls.removeAll()
        adapter.deactivate(client: log)
        #expect(log.calls == ["insert ni", "hide", "hide"])
    }

    @Test func chordReleasesReachTheLastClient() {
        session.setOption("_chord_typing", true)
        #expect(adapter.handle(input(key("a", code: 0)), client: log))
        #expect(adapter.handle(input(key("s", code: 1)), client: log))
        #expect(log.calls.isEmpty)
        chordTimer.fire()
        #expect(log.calls == ["insert as"])
    }

    @Test func statusIsShownNearTheCaret() throws {
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        log.calls.removeAll()
        let sessionID = try #require(session.currentSessionID)
        adapter.handle(RimeNotification(sessionID: sessionID, type: "option", value: "ascii_mode"))
        #expect(log.calls == ["caret", "status A"])
    }

    @Test func statusFollowsTheConfiguration() throws {
        adapter.configuration.notifications = .never
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        log.calls.removeAll()
        let sessionID = try #require(session.currentSessionID)
        adapter.handle(RimeNotification(sessionID: sessionID, type: "option", value: "ascii_mode"))
        #expect(log.calls.isEmpty)
    }

    @Test func theSessionsSchemaIsReported() {
        var schemas: [String] = []
        adapter.onSchemaChange = { schemas.append($0) }
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        #expect(schemas == ["scribe_test"])
    }

    @Test func theChordDurationReachesTheSession() {
        adapter.configuration.chordDuration = 0.4
        #expect(session.chordDuration == 0.4)
    }

    @Test func theModeIndicatorFollowsASCIIMode() {
        #expect(adapter.modeIndicator == nil)
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        #expect(adapter.modeIndicator == "中")
        adapter.setASCIIMode(true)
        #expect(adapter.modeIndicator == "A")
    }

    @Test func otherSessionsStatusIsIgnored() {
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        log.calls.removeAll()
        adapter.handle(RimeNotification(sessionID: RimeSessionID(rawValue: 999), type: "option", value: "ascii_mode"))
        #expect(log.calls.isEmpty)
    }

    // Round trips through the candidate window: it reports clicks and scrolls
    // to its delegate, the adapter that showed candidates last.

    @Test func showingCandidatesMakesTheAdapterTheWindowsDelegate() {
        #expect(log.delegate == nil)
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        #expect(log.delegate === adapter)
    }

    @Test func clickingACandidateCommitsIt() throws {
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        _ = adapter.handle(input(key("i", code: 34)), client: log)
        log.calls.removeAll()
        try #require(log.delegate).candidatePanel(panel, didSelectCandidateAt: 1)
        #expect(log.calls == ["insert 泥", "hide"])
    }

    @Test func scrollingPagesTheCandidates() throws {
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        _ = adapter.handle(input(key("i", code: 34)), client: log)
        log.calls.removeAll()
        let delegate = try #require(log.delegate)
        delegate.candidatePanel(panel, didRequestPage: .down)
        delegate.candidatePanel(panel, didRequestPage: .up)
        #expect(log.calls == ["caret", "show 拟 腻", "caret", "show 你 泥 呢 尼 逆"])
    }

    @Test func clickingThePreeditMovesTheCaret() throws {
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        _ = adapter.handle(input(key("i", code: 34)), client: log)
        let sessionID = try #require(session.currentSessionID)
        let delegate = try #require(log.delegate)
        delegate.candidatePanel(panel, didRequestCaretMove: .towardStart)
        #expect(engine.caretPosition(in: sessionID) == 1)
        delegate.candidatePanel(panel, didRequestCaretMove: .towardEnd)
        #expect(engine.caretPosition(in: sessionID) == 2)
    }

    /// Clients share the one candidate window; a click goes to the client
    /// whose candidates it shows.
    @Test func requestsGoToTheClientShownLast() throws {
        let other = CallLog()
        let otherAdapter = InputAdapter(session: InputSession(engine: engine, chordTimer: chordTimer), candidates: log)
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        _ = otherAdapter.handle(input(key("n", code: 45)), client: other)
        _ = otherAdapter.handle(input(key("i", code: 34)), client: other)
        log.calls.removeAll()
        other.calls.removeAll()
        try #require(log.delegate).candidatePanel(panel, didSelectCandidateAt: 0)
        #expect(other.calls == ["insert 你"])
        #expect(log.calls == ["hide"])
    }

    func configuration(appOptions: [String: [String: Bool]]) -> SessionConfiguration {
        var configuration = SessionConfiguration()
        configuration.appOptions = AppOptions(byBundleID: appOptions)
        return configuration
    }

    @Test func theClientsAppOptionsApply() throws {
        adapter.configuration = configuration(appOptions: ["com.apple.Terminal": ["ascii_mode": true]])
        log.bundleIdentifier = "com.apple.Terminal"
        #expect(!adapter.handle(input(key("n", code: 45)), client: log))
        #expect(adapter.isASCIIMode == true)
    }

    @Test func theWindowShowsTheInputAloneWhenTheClientDoesNot() {
        adapter.configuration.presentation.inlinePreedit = false
        // "x" spells nothing in the test dictionary.
        _ = adapter.handle(input(key("x", code: 7)), client: log)
        #expect(log.calls == ["mark 　|0", "caret", "show "])
    }

    @Test func aNoInlineAppSeesTheInputInTheWindowEvenWithoutCandidates() {
        adapter.configuration = configuration(appOptions: ["com.googlecode.iterm2": ["no_inline": true]])
        log.bundleIdentifier = "com.googlecode.iterm2"
        _ = adapter.handle(input(key("x", code: 7)), client: log)
        #expect(log.calls == ["mark 　|0", "caret", "show "])
    }

    @Test func aPluginsRefreshRedrawsTheWindow() throws {
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        _ = adapter.handle(input(key("i", code: 34)), client: log)
        log.calls.removeAll()
        let sessionID = try #require(session.currentSessionID)
        for value in ["_comment_highlight=1", "_refresh_ui=1"] {
            adapter.handle(RimeNotification(sessionID: sessionID, type: "property", value: value))
        }
        #expect(log.calls == ["caret", "show 你 泥 呢 尼 逆"])
    }

    @Test func pageDownUpdatesOnlyTheWindow() {
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        _ = adapter.handle(input(key("i", code: 34)), client: log)
        log.calls.removeAll()
        #expect(adapter.handle(input(key("\u{F72D}", code: 121)), client: log))
        #expect(log.calls == ["caret", "show 拟 腻"])
    }
}

extension InputAdapterTests {
    @Test func closingAnOldControllerKeepsTheCurrentCandidatesVisible() {
        let current = InputAdapter(session: InputSession(engine: engine), candidates: log)
        _ = adapter.handle(input(key("n", code: 45)), client: log)
        _ = current.handle(input(key("h", code: 4)), client: log)
        #expect(log.delegate === current)
        log.calls.removeAll()
        adapter.close()
        #expect(log.calls.isEmpty)
        #expect(log.delegate === current)
        current.close()
        #expect(log.calls == ["hide"])
    }
}
