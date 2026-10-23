import Foundation
import RimeKit
import ScribeConfig

/// Text shown inline in the client while composing.
public struct MarkedText: Equatable, Sendable {
    public var text: String
    /// Caret position in UTF-16 code units.
    public var caret: Int

    public init(text: String, caret: Int) {
        self.text = text
        self.caret = caret
    }

    public static let empty = MarkedText(text: "", caret: 0)
}

/// The text being composed, as the candidate window may show it. Offsets
/// count UTF-16 code units of `text`.
public struct Preedit: Equatable, Sendable {
    public var text: String
    /// The part of the input currently being converted.
    public var selectedRange: Range<Int>
    public var caret: Int

    public init(text: String, selectedRange: Range<Int>, caret: Int) {
        self.text = text
        self.selectedRange = selectedRange
        self.caret = caret
    }
}

/// Everything the candidate window shows for one page.
public struct CandidateSnapshot: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var label: String
        public var text: String
        public var comment: String?

        public init(label: String, text: String, comment: String? = nil) {
            self.label = label
            self.text = text
            self.comment = comment
        }
    }

    /// Empty while composing input that has no candidates.
    public var entries: [Entry]
    public var highlightedIndex: Int
    /// Zero-based.
    public var pageNumber: Int
    public var isLastPage: Bool
    /// Nil when nothing is being composed.
    public var preedit: Preedit?

    public init(
        entries: [Entry],
        highlightedIndex: Int = 0,
        pageNumber: Int = 0,
        isLastPage: Bool = true,
        preedit: Preedit? = nil
    ) {
        self.entries = entries
        self.highlightedIndex = highlightedIndex
        self.pageNumber = pageNumber
        self.isLastPage = isLastPage
        self.preedit = preedit
    }

    /// Labels follow Squirrel: the menu's select keys, one per character;
    /// otherwise its select labels; otherwise, or past the end of either,
    /// the candidate's number on the page, so the tenth is "10".
    public init(menu: CandidateMenu?, composition: Composition?) {
        let labels = menu.map(Self.labels) ?? []
        self.init(
            entries: (menu?.candidates ?? []).enumerated().map { index, candidate in
                Entry(label: index < labels.count ? labels[index] : "\(index + 1)", text: candidate.text, comment: candidate.comment)
            },
            highlightedIndex: menu?.highlightedIndex ?? 0,
            pageNumber: menu?.pageNumber ?? 0,
            isLastPage: menu?.isLastPage ?? true,
            preedit: composition.map { composition in
                Preedit(
                    text: composition.preedit,
                    selectedRange: composition.selectionStart..<max(composition.selectionStart, composition.selectionEnd),
                    caret: composition.cursor
                )
            }
        )
    }

    private static func labels(for menu: CandidateMenu) -> [String] {
        if let keys = menu.selectKeys, !keys.isEmpty {
            return keys.map(String.init)
        }
        return menu.selectLabels ?? []
    }
}

/// What the client application should do after a key.
public enum SessionAction: Equatable, Sendable {
    /// Insert this text, replacing the marked text.
    case commit(String)
    /// Replace the marked text; empty text removes it.
    case setMarkedText(MarkedText)
    case showCandidates(CandidateSnapshot)
    case hideCandidates
    /// Announce a mode or schema change briefly near the caret.
    case showStatus(String)
}

public struct KeyResult: Equatable, Sendable {
    /// False when the key should go on to the client unchanged.
    public var handled: Bool
    public var actions: [SessionAction]

    public init(handled: Bool, actions: [SessionAction]) {
        self.handled = handled
        self.actions = actions
    }
}

/// One input session: keys go in, actions for the client come out.
///
/// The session remembers what the client was last told and reports only
/// changes, in the order they must be applied: commit, then marked text,
/// then candidates.
@MainActor
public final class InputSession {
    /// How long to wait for more keys of a chord, from `chord_duration`.
    public var chordDuration: TimeInterval = 0.1
    /// Receives actions that happen without a key, such as a chord being
    /// released after `chordDuration`.
    public var onAsyncActions: (([SessionAction]) -> Void)?

    private let engine: any RimeEngine
    private let chordTimer: ChordTimer?
    private var session: RimeSessionID?
    private var markedText = MarkedText.empty
    private var candidates: CandidateSnapshot?
    private var chordKeys: [KeyEvent] = []

    /// Without a chord timer, chord typing is off.
    public init(engine: any RimeEngine, chordTimer: ChordTimer? = nil) {
        self.engine = engine
        self.chordTimer = chordTimer
    }

    /// Passes the key to Rime. While librime deploys, every key goes to the
    /// client unhandled.
    public func handle(_ key: KeyEvent) -> KeyResult {
        guard let session = activeSession() else { return KeyResult(handled: false, actions: []) }
        let handled = engine.processKey(key.keycode, modifiers: key.modifiers.rawValue, in: session)
        if !handled {
            if Self.leavesVimInsertMode(key), engine.option("vim_mode", in: session),
               !engine.option("ascii_mode", in: session) {
                // Back in Vim's normal mode, commands are typed in ASCII.
                engine.setOption("ascii_mode", true, in: session)
            }
        } else if Self.isChordKey(key), engine.option("_chord_typing", in: session) {
            addToChord(key, in: session)
        } else if !key.modifiers.contains(.release) {
            clearChord()
        }
        return KeyResult(handled: handled, actions: update(session))
    }

    /// The value of a Rime option, such as "ascii_mode", or nil while there
    /// is no session.
    public func option(_ name: String) -> Bool? {
        activeSession().map { engine.option(name, in: $0) }
    }

    /// Sets a Rime option and reports what changed for the client.
    @discardableResult
    public func setOption(_ name: String, _ value: Bool) -> [SessionAction] {
        guard let session = activeSession() else { return [] }
        engine.setOption(name, value, in: session)
        return update(session)
    }

    /// Commits the candidate at `index` on the current page.
    public func selectCandidate(at index: Int) -> [SessionAction] {
        guard let session = activeSession() else { return [] }
        _ = engine.selectCandidate(onCurrentPage: index, in: session)
        return update(session)
    }

    public func changePage(_ direction: PageDirection) -> [SessionAction] {
        guard let session = activeSession() else { return [] }
        _ = engine.changePage(backward: direction == .up, in: session)
        return update(session)
    }

    /// Moves the caret one position in the raw input.
    public func moveCaret(_ move: CaretMove) -> [SessionAction] {
        guard let session = activeSession(), let input = engine.input(in: session) else { return [] }
        let position = engine.caretPosition(in: session)
        switch move {
        case .towardStart where position > 0:
            engine.setCaretPosition(position - 1, in: session)
        case .towardEnd where position < input.utf8.count:
            engine.setCaretPosition(position + 1, in: session)
        default:
            return []
        }
        return update(session)
    }

    /// Commits what was typed, unconverted, and ends the composition: for
    /// when the client loses focus or the input source changes, so that no
    /// text is lost.
    public func commitComposition() -> [SessionAction] {
        guard let session = activeSession(), let input = engine.input(in: session), !input.isEmpty else { return [] }
        engine.clearComposition(in: session)
        clearChord()
        // Inserting text replaces the client's marked text.
        markedText = .empty
        return [.commit(input)] + update(session)
    }

    /// The Rime session, started if there is none yet; nil while librime
    /// deploys.
    public var currentSessionID: RimeSessionID? {
        activeSession()
    }

    /// Whether a notification concerns this session.
    public func owns(_ sessionID: RimeSessionID) -> Bool {
        session == sessionID
    }

    /// The announcement for an option or schema change, as Squirrel shows
    /// it, or nothing when notifications are off or there is nothing to say.
    public func status(
        for notification: RimeNotification,
        notifications: NotificationPolicy,
        messageType: StatusMessageType
    ) -> [SessionAction] {
        guard notifications != .never, let session else { return [] }
        let long: String
        let short: String
        switch notification.type {
        case "option":
            let state = !notification.value.hasPrefix("!")
            let option = state ? notification.value : String(notification.value.dropFirst())
            long = engine.stateLabel(option, state: state, abbreviated: false, in: session) ?? ""
            short = engine.stateLabel(option, state: state, abbreviated: true, in: session) ?? ""
        case "schema":
            // "luna_pinyin/朙月拼音"
            guard let slash = notification.value.firstIndex(of: "/") else { return [] }
            long = String(notification.value[notification.value.index(after: slash)...])
            short = long
        default:
            return []
        }
        let message = switch messageType {
        case .mix: short.isEmpty ? long : short
        case .long: long
        case .short: short.isEmpty ? long.first.map(String.init) ?? "" : short
        }
        return message.isEmpty ? [] : [.showStatus(message)]
    }

    /// Discards whatever is being composed.
    public func clearComposition() -> [SessionAction] {
        guard let session = activeSession() else { return [] }
        engine.clearComposition(in: session)
        return update(session)
    }

    /// Ends the Rime session. A later key starts a new one.
    public func close() {
        clearChord()
        if let session {
            engine.destroySession(session)
        }
        session = nil
        markedText = .empty
        candidates = nil
    }

    /// Printable keys and the Shift, Control and Alt keys take part in chords.
    private static func isChordKey(_ key: KeyEvent) -> Bool {
        (0x20...0x7e).contains(key.keycode)
            || [Keysym.controlL, Keysym.controlR, Keysym.altL, Keysym.altR, Keysym.shiftL, Keysym.shiftR].contains(key.keycode)
    }

    /// Keys pressed together are released together once no new key has come
    /// for `chordDuration`.
    private func addToChord(_ key: KeyEvent, in session: RimeSessionID) {
        guard let chordTimer, !chordKeys.contains(where: { $0.keycode == key.keycode }), chordKeys.count < 50 else { return }
        chordKeys.append(key)
        chordTimer.start(after: chordDuration) { [weak self] in
            self?.releaseChord()
        }
    }

    private func releaseChord() {
        let keys = chordKeys
        chordKeys = []
        guard let session, engine.sessionExists(session) else { return }
        var handled = false
        for key in keys where engine.processKey(key.keycode, modifiers: key.modifiers.union(.release).rawValue, in: session) {
            handled = true
        }
        if handled {
            onAsyncActions?(update(session))
        }
    }

    private func clearChord() {
        chordKeys = []
        chordTimer?.cancel()
    }

    /// Escape, Control+C and Control+[ return Vim to normal mode.
    private static func leavesVimInsertMode(_ key: KeyEvent) -> Bool {
        guard !key.modifiers.contains(.release) else { return false }
        if key.keycode == Keysym.escape {
            return true
        }
        return key.modifiers.contains(.control) && [0x63, 0x43, 0x5b].contains(key.keycode)
    }

    private func activeSession() -> RimeSessionID? {
        guard !engine.isInMaintenance else { return nil }
        if let session, engine.sessionExists(session) {
            return session
        }
        session = engine.createSession()
        markedText = .empty
        candidates = nil
        return session
    }

    private func update(_ session: RimeSessionID) -> [SessionAction] {
        var actions: [SessionAction] = []
        if let commit = engine.consumeCommit(in: session) {
            actions.append(.commit(commit))
            // Inserting text replaces the client's marked text.
            markedText = .empty
        }
        let context = engine.context(in: session)
        let newMarkedText = context.composition.map { MarkedText(text: $0.preedit, caret: $0.cursor) } ?? .empty
        if newMarkedText != markedText {
            actions.append(.setMarkedText(newMarkedText))
            markedText = newMarkedText
        }
        // A snapshot whenever something is composed, even with no candidates,
        // so the window can show the preedit alone.
        let newCandidates = context.composition == nil && context.menu == nil
            ? nil
            : CandidateSnapshot(menu: context.menu, composition: context.composition)
        if newCandidates != candidates {
            actions.append(newCandidates.map(SessionAction.showCandidates) ?? .hideCandidates)
            candidates = newCandidates
        }
        return actions
    }
}
