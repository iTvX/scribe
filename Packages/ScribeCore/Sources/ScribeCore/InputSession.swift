import RimeKit

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
    private let engine: any RimeEngine
    private var session: RimeSessionID?
    private var markedText = MarkedText.empty
    private var candidates: CandidateSnapshot?

    public init(engine: any RimeEngine) {
        self.engine = engine
    }

    /// Passes the key to Rime. While librime deploys, every key goes to the
    /// client unhandled.
    public func handle(_ key: KeyEvent) -> KeyResult {
        guard let session = activeSession() else { return KeyResult(handled: false, actions: []) }
        let handled = engine.processKey(key.keycode, modifiers: key.modifiers.rawValue, in: session)
        return KeyResult(handled: handled, actions: update(session))
    }

    /// Commits the candidate at `index` on the current page.
    public func selectCandidate(at index: Int) -> [SessionAction] {
        guard let session = activeSession() else { return [] }
        _ = engine.selectCandidate(onCurrentPage: index, in: session)
        return update(session)
    }

    public func changePage(backward: Bool) -> [SessionAction] {
        guard let session = activeSession() else { return [] }
        _ = engine.changePage(backward: backward, in: session)
        return update(session)
    }

    /// Commits whatever is being composed, for when the client asks the input
    /// method to finish, such as on a focus change.
    public func commitComposition() -> [SessionAction] {
        guard let session = activeSession() else { return [] }
        _ = engine.commitComposition(in: session)
        return update(session)
    }

    /// Discards whatever is being composed.
    public func clearComposition() -> [SessionAction] {
        guard let session = activeSession() else { return [] }
        engine.clearComposition(in: session)
        return update(session)
    }

    /// Ends the Rime session. A later key starts a new one.
    public func close() {
        if let session {
            engine.destroySession(session)
        }
        session = nil
        markedText = .empty
        candidates = nil
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
