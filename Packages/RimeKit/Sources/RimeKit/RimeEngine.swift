import Foundation

/// A Rime session, as returned by `RimeEngine.createSession()`.
public struct RimeSessionID: Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
}

/// The text being composed. Offsets count UTF-16 code units of `preedit`, so
/// they can be used directly in an `NSRange`.
public struct Composition: Equatable, Sendable {
    public var preedit: String
    public var cursor: Int
    public var selectionStart: Int
    public var selectionEnd: Int

    public init(preedit: String, cursor: Int, selectionStart: Int, selectionEnd: Int) {
        self.preedit = preedit
        self.cursor = cursor
        self.selectionStart = selectionStart
        self.selectionEnd = selectionEnd
    }
}

public struct Candidate: Equatable, Sendable {
    public var text: String
    public var comment: String?

    public init(text: String, comment: String? = nil) {
        self.text = text
        self.comment = comment
    }
}

/// The current page of candidates.
public struct CandidateMenu: Equatable, Sendable {
    public var candidates: [Candidate]
    public var pageSize: Int
    /// Zero-based.
    public var pageNumber: Int
    public var isLastPage: Bool
    public var highlightedIndex: Int
    /// Labels for the candidates on this page, when the schema defines them.
    public var selectLabels: [String]?
    /// Keys that select candidates on this page, such as "1234567890".
    public var selectKeys: String?

    public init(
        candidates: [Candidate],
        pageSize: Int,
        pageNumber: Int = 0,
        isLastPage: Bool = true,
        highlightedIndex: Int = 0,
        selectLabels: [String]? = nil,
        selectKeys: String? = nil
    ) {
        self.candidates = candidates
        self.pageSize = pageSize
        self.pageNumber = pageNumber
        self.isLastPage = isLastPage
        self.highlightedIndex = highlightedIndex
        self.selectLabels = selectLabels
        self.selectKeys = selectKeys
    }
}

/// What a session shows after a key: the composition and its candidates.
public struct EngineContext: Equatable, Sendable {
    /// Nil when nothing is being composed.
    public var composition: Composition?
    /// Nil when there are no candidates.
    public var menu: CandidateMenu?
    /// The text that would be committed now, if the schema provides it.
    public var commitPreview: String?

    public init(composition: Composition? = nil, menu: CandidateMenu? = nil, commitPreview: String? = nil) {
        self.composition = composition
        self.menu = menu
        self.commitPreview = commitPreview
    }
}

public struct EngineStatus: Equatable, Sendable {
    public var schemaID: String
    public var schemaName: String
    public var isDisabled: Bool
    public var isComposing: Bool
    public var isASCIIMode: Bool

    public init(schemaID: String, schemaName: String, isDisabled: Bool, isComposing: Bool, isASCIIMode: Bool) {
        self.schemaID = schemaID
        self.schemaName = schemaName
        self.isDisabled = isDisabled
        self.isComposing = isComposing
        self.isASCIIMode = isASCIIMode
    }
}

/// An event reported by librime, such as a deployment finishing.
public struct RimeNotification: Equatable, Sendable {
    /// Zero for events not tied to a session, such as deployment.
    public var sessionID: RimeSessionID
    public var type: String
    public var value: String

    public init(sessionID: RimeSessionID, type: String, value: String) {
        self.sessionID = sessionID
        self.type = type
        self.value = value
    }
}

/// The session operations ScribeCore needs from Rime. `LibrimeEngine` is the
/// real implementation; tests substitute a fake.
///
/// Key codes and modifier masks are librime's: X11 keysyms and Rime modifier
/// bits.
@MainActor
public protocol RimeEngine: AnyObject {
    /// True while librime deploys; sessions cannot be used meanwhile.
    var isInMaintenance: Bool { get }
    func createSession() -> RimeSessionID?
    /// False once librime has dropped the session, such as after a restart.
    func sessionExists(_ session: RimeSessionID) -> Bool
    func destroySession(_ session: RimeSessionID)
    func processKey(_ keycode: Int32, modifiers: Int32, in session: RimeSessionID) -> Bool
    /// Returns and clears the text committed since the last call.
    func consumeCommit(in session: RimeSessionID) -> String?
    func context(in session: RimeSessionID) -> EngineContext
    func selectCandidate(onCurrentPage index: Int, in session: RimeSessionID) -> Bool
    func changePage(backward: Bool, in session: RimeSessionID) -> Bool
    /// Commits whatever is being composed.
    func commitComposition(in session: RimeSessionID) -> Bool
    func clearComposition(in session: RimeSessionID)
    func option(_ option: String, in session: RimeSessionID) -> Bool
    func setOption(_ option: String, _ value: Bool, in session: RimeSessionID)
}
