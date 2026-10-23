import RimeKit
import ScribeCore

/// A stand-in for librime with the dictionary of the scribe_test schema in
/// Tests/Fixtures/rime. It follows Rime's basic editing behavior: letters
/// compose, space or a digit selects, Return commits the raw input,
/// BackSpace and Escape edit, Page_Up and Page_Down page.
@MainActor
public final class FakeRimeEngine: RimeEngine {
    /// Spelling, with syllables separated by spaces, to candidates in order.
    public static let testDictionary: [(String, [String])] = [
        ("ni hao", ["你好"]),
        ("zhong shu", ["中书"]),
        ("ni", ["你", "泥", "呢", "尼", "逆", "拟", "腻"]),
        ("hao", ["好", "号"]),
        ("zhong", ["中"]),
        ("shu", ["书"]),
    ]

    public var isInMaintenance = false
    public let pageSize: Int

    private let dictionary: [(String, [String])]
    private let syllables: [String]
    private var sessions: [RimeSessionID: State] = [:]
    private var nextSession: UInt = 1

    private struct State {
        var input = ""
        var page = 0
        var highlighted = 0
        var commit: String?
    }

    public init(dictionary: [(String, [String])] = FakeRimeEngine.testDictionary, pageSize: Int = 5) {
        self.dictionary = dictionary
        self.pageSize = pageSize
        syllables = Set(dictionary.flatMap { $0.0.split(separator: " ").map(String.init) })
            .sorted { $0.count > $1.count }
    }

    public func createSession() -> RimeSessionID? {
        let session = RimeSessionID(rawValue: nextSession)
        nextSession += 1
        sessions[session] = State()
        return session
    }

    public func sessionExists(_ session: RimeSessionID) -> Bool {
        sessions[session] != nil
    }

    public func destroySession(_ session: RimeSessionID) {
        sessions[session] = nil
    }

    public func processKey(_ keycode: Int32, modifiers: Int32, in session: RimeSessionID) -> Bool {
        guard var state = sessions[session] else { return false }
        defer { sessions[session] = state }
        let modifiers = KeyModifiers(rawValue: modifiers)
        guard modifiers.isDisjoint(with: [.release, .control, .alt, .super]) else { return false }

        if let scalar = Unicode.Scalar(UInt32(keycode)), ("a"..."z").contains(scalar) {
            state.input.unicodeScalars.append(scalar)
            state.page = 0
            state.highlighted = 0
            return true
        }
        guard !state.input.isEmpty else { return false }

        let page = currentPage(state)
        switch keycode {
        case Keysym.space:
            commit(page.isEmpty ? state.input : page[state.highlighted], &state)
        case Keysym.return:
            commit(state.input, &state)
        case Keysym.backSpace:
            state.input.removeLast()
            state.page = 0
            state.highlighted = 0
        case Keysym.escape:
            state = State()
        case Keysym.pageDown:
            if (state.page + 1) * pageSize < candidates(for: state.input).count {
                state.page += 1
                state.highlighted = 0
            }
        case Keysym.pageUp:
            if state.page > 0 {
                state.page -= 1
                state.highlighted = 0
            }
        case Keysym.down:
            state.highlighted = min(state.highlighted + 1, max(page.count - 1, 0))
        case Keysym.up:
            state.highlighted = max(state.highlighted - 1, 0)
        case 0x31...0x39, 0x30:
            let index = keycode == 0x30 ? 9 : Int(keycode - 0x31)
            if index < page.count {
                commit(page[index], &state)
            }
        default:
            break
        }
        return true
    }

    public func consumeCommit(in session: RimeSessionID) -> String? {
        defer { sessions[session]?.commit = nil }
        return sessions[session]?.commit
    }

    public func context(in session: RimeSessionID) -> EngineContext {
        guard let state = sessions[session], !state.input.isEmpty else { return EngineContext() }
        let preedit = segmented(state.input)
        let page = currentPage(state)
        let total = candidates(for: state.input).count
        return EngineContext(
            composition: Composition(
                preedit: preedit,
                cursor: preedit.utf16.count,
                selectionStart: 0,
                selectionEnd: preedit.utf16.count
            ),
            menu: page.isEmpty ? nil : CandidateMenu(
                candidates: page.map { Candidate(text: $0) },
                pageSize: pageSize,
                pageNumber: state.page,
                isLastPage: (state.page + 1) * pageSize >= total,
                highlightedIndex: state.highlighted,
                selectKeys: "1234567890"
            )
        )
    }

    public func selectCandidate(onCurrentPage index: Int, in session: RimeSessionID) -> Bool {
        guard var state = sessions[session] else { return false }
        let page = currentPage(state)
        guard index < page.count else { return false }
        commit(page[index], &state)
        sessions[session] = state
        return true
    }

    public func changePage(backward: Bool, in session: RimeSessionID) -> Bool {
        processKey(backward ? Keysym.pageUp : Keysym.pageDown, modifiers: 0, in: session)
    }

    public func commitComposition(in session: RimeSessionID) -> Bool {
        guard var state = sessions[session], !state.input.isEmpty else { return false }
        let page = currentPage(state)
        commit(page.isEmpty ? state.input : page[state.highlighted], &state)
        sessions[session] = state
        return true
    }

    public func clearComposition(in session: RimeSessionID) {
        sessions[session] = sessions[session].map { _ in State() }
    }

    private func commit(_ text: String, _ state: inout State) {
        state = State()
        state.commit = text
    }

    /// Whole-input matches first, then words for the first syllable, then
    /// spellings the input is a prefix of.
    private func candidates(for input: String) -> [String] {
        let exact = dictionary.filter { $0.0.replacingOccurrences(of: " ", with: "") == input }.flatMap(\.1)
        let first = segmented(input).split(separator: " ").first.map(String.init) ?? input
        let partial = first == input ? [] : dictionary.filter { $0.0 == first }.flatMap(\.1)
        let prefixed = exact.isEmpty && partial.isEmpty
            ? dictionary.filter { $0.0.replacingOccurrences(of: " ", with: "").hasPrefix(input) }.flatMap(\.1)
            : []
        var seen = Set<String>()
        return (exact + partial + prefixed).filter { seen.insert($0).inserted }
    }

    private func currentPage(_ state: State) -> [String] {
        Array(candidates(for: state.input).dropFirst(state.page * pageSize).prefix(pageSize))
    }

    /// Splits input into known syllables, longest first, as Rime's preedit
    /// shows it: "nihao" becomes "ni hao".
    private func segmented(_ input: String) -> String {
        var rest = Substring(input)
        var parts: [String] = []
        while !rest.isEmpty {
            if let syllable = syllables.first(where: { rest.hasPrefix($0) }) {
                parts.append(syllable)
                rest = rest.dropFirst(syllable.count)
            } else {
                parts.append(String(rest))
                break
            }
        }
        return parts.joined(separator: " ")
    }
}
