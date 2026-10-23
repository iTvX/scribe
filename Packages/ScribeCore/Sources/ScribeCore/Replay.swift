import Foundation
import RimeKit
import ScribeConfig

/// A recorded key sequence with the expected results, for replay tests.
///
/// The format is line based:
///
///     # Comments start with "#"; blank lines are ignored.
///     @engines fake rime        # optional: engines this file applies to
///     @option vim_mode true     # sets a Rime option before the next step
///     n
///     i       => marked "ni"; candidates "你" "泥"
///     space   => commit "你"; marked ""; candidates none
///
/// Each step is a key, named as in `KeyEvent(name:)`, or an action that is
/// not a key:
///
/// - `!commit-composition`: the client lost focus or the input source changed
/// - `!select N`, `!page up|down`, `!caret start|end`: from the candidate window
/// - `!tick`: the chord duration passed
/// - `!notify TYPE VALUE`: librime sent a notification, such as
///   `!notify option !ascii_mode` or `!notify schema luna_pinyin/朙月拼音`
///
/// `@notifications always|appropriate|never` and `@status-message
/// mix|long|short` set how notifications are announced from then on.
///
/// A step may be followed by "=>" and expectations separated by ";":
///
/// - `commit "text"` or `commit none`: what this step committed
/// - `marked "text"`: the marked text afterwards; `marked ""` means none
/// - `caret N`: the caret in the marked text, in UTF-16 code units
/// - `candidates "a" "b" ...`: the candidates shown afterwards start with
///   these; `candidates none` means there are none
/// - `highlighted N`, `page N`: zero-based highlighted candidate and page
/// - `handled` or `unhandled`: whether the key was consumed
/// - `option NAME true|false`: a Rime option afterwards
/// - `status "text"` or `status none`: what this step announced
public struct ReplayScript: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case commitComposition
        case select(Int)
        case page(PageDirection)
        case caret(CaretMove)
        case tick
        case notify(type: String, value: String)
    }

    public enum Input: Equatable, Sendable {
        case key(KeyEvent)
        case action(Action)
    }

    public enum Expectation: Equatable, Sendable {
        case commit(String?)
        case marked(String)
        case caret(Int)
        case candidates([String]?)
        case highlighted(Int)
        case page(Int)
        case handled(Bool)
        case option(String, Bool)
        case status(String?)
    }

    public struct Option: Equatable, Sendable {
        public var name: String
        public var value: Bool
    }

    public struct Step: Equatable, Sendable {
        public var input: Input
        public var expectations: [Expectation]
        public var line: Int
        /// Options set just before the step.
        public var options: [Option] = []
        public var notifications: NotificationPolicy = .appropriate
        public var messageType: StatusMessageType = .mix
    }

    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public var line: Int
        public var message: String

        public init(line: Int, message: String) {
            self.line = line
            self.message = message
        }

        public var description: String {
            "line \(line): \(message)"
        }
    }

    /// Nil means every engine.
    public var engines: Set<String>?
    public var steps: [Step]

    public init(_ source: String) throws {
        engines = nil
        steps = []
        var pendingOptions: [Option] = []
        var notifications = NotificationPolicy.appropriate
        var messageType = StatusMessageType.mix
        for (index, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = index + 1
            let line = Self.stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                continue
            }
            func fail(_ message: String) -> ParseError {
                ParseError(line: lineNumber, message: message)
            }
            if line.hasPrefix("@") {
                let words = line.split(separator: " ").map(String.init)
                switch words[0] {
                case "@engines":
                    engines = Set(words.dropFirst())
                case "@option":
                    guard words.count == 3, let value = Bool(words[2]) else {
                        throw fail("expected \"@option NAME true|false\"")
                    }
                    pendingOptions.append(Option(name: words[1], value: value))
                case "@notifications":
                    guard words.count == 2, let policy = NotificationPolicy(rawValue: words[1]) else {
                        throw fail("expected \"@notifications always|appropriate|never\"")
                    }
                    notifications = policy
                case "@status-message":
                    guard words.count == 2, let type = StatusMessageType(rawValue: words[1]) else {
                        throw fail("expected \"@status-message mix|long|short\"")
                    }
                    messageType = type
                default:
                    throw fail("unknown directive \"\(words[0])\"")
                }
                continue
            }
            let parts: [String] = line.range(of: "=>").map {
                [String(line[..<$0.lowerBound]), String(line[$0.upperBound...])]
            } ?? [line]
            let stepText = parts[0].trimmingCharacters(in: .whitespaces)
            let input: Input
            if stepText.hasPrefix("!") {
                guard let action = Self.action(stepText) else {
                    throw fail("unknown action \"\(stepText)\"")
                }
                input = .action(action)
            } else {
                guard let key = KeyEvent(name: stepText) else {
                    throw fail("unknown key \"\(stepText)\"")
                }
                input = .key(key)
            }
            var expectations: [Expectation] = []
            if parts.count == 2 {
                for clause in Self.clauses(parts[1]) {
                    let clause = clause.trimmingCharacters(in: .whitespaces)
                    if clause.isEmpty {
                        continue
                    }
                    guard let expectation = Self.expectation(clause) else {
                        throw fail("unknown expectation \"\(clause)\"")
                    }
                    expectations.append(expectation)
                }
            }
            steps.append(Step(
                input: input,
                expectations: expectations,
                line: lineNumber,
                options: pendingOptions,
                notifications: notifications,
                messageType: messageType
            ))
            pendingOptions = []
        }
    }

    private static func action(_ text: String) -> Action? {
        let words = text.split(separator: " ", maxSplits: 2).map(String.init)
        switch (words[0], words.count) {
        case ("!commit-composition", 1):
            return .commitComposition
        case ("!tick", 1):
            return .tick
        case ("!select", 2):
            return Int(words[1]).map { .select($0) }
        case ("!page", 2):
            return ["up": Action.page(.up), "down": .page(.down)][words[1]]
        case ("!caret", 2):
            return ["start": Action.caret(.towardStart), "end": .caret(.towardEnd)][words[1]]
        case ("!notify", 3):
            return .notify(type: words[1], value: words[2])
        default:
            return nil
        }
    }

    /// Splits at semicolons outside quotes.
    private static func clauses(_ text: String) -> [String] {
        var clauses = [""]
        var inQuotes = false
        for character in text {
            if character == "\"" {
                inQuotes.toggle()
            }
            if character == ";", !inQuotes {
                clauses.append("")
            } else {
                clauses[clauses.count - 1].append(character)
            }
        }
        return clauses
    }

    /// A "#" starts a comment unless it is inside quotes.
    private static func stripComment(_ line: String) -> String {
        var inQuotes = false
        for (offset, character) in line.enumerated() {
            if character == "\"" {
                inQuotes.toggle()
            } else if character == "#", !inQuotes {
                return String(line.prefix(offset))
            }
        }
        return line
    }

    private static func expectation(_ clause: String) -> Expectation? {
        let words = clause.split(separator: " ", maxSplits: 1).map(String.init)
        let argument = words.count > 1 ? words[1].trimmingCharacters(in: .whitespaces) : ""
        switch words[0] {
        case "commit":
            return argument == "none" ? .commit(nil) : quoted(argument).first.map { .commit($0) }
        case "status":
            return argument == "none" ? .status(nil) : quoted(argument).first.map { .status($0) }
        case "marked":
            return quoted(argument).first.map { .marked($0) }
        case "caret":
            return Int(argument).map { .caret($0) }
        case "candidates":
            if argument == "none" {
                return .candidates(nil)
            }
            let texts = quoted(argument)
            return texts.isEmpty ? nil : .candidates(texts)
        case "highlighted":
            return Int(argument).map { .highlighted($0) }
        case "page":
            return Int(argument).map { .page($0) }
        case "handled":
            return argument.isEmpty ? .handled(true) : nil
        case "unhandled":
            return argument.isEmpty ? .handled(false) : nil
        case "option":
            let parts = argument.split(separator: " ").map(String.init)
            guard parts.count == 2, let value = Bool(parts[1]) else { return nil }
            return .option(parts[0], value)
        default:
            return nil
        }
    }

    /// The double-quoted strings in `text`, such as `"a" "b"`.
    private static func quoted(_ text: String) -> [String] {
        text.split(separator: "\"", omittingEmptySubsequences: false)
            .enumerated()
            .filter { $0.offset.isMultiple(of: 2) == false }
            .map { String($0.element) }
    }
}

/// Plays a script through an input session, tracking what a client would
/// show, and reports every expectation that does not hold.
@MainActor
public enum ReplayRunner {
    public struct Failure: Equatable, Sendable, CustomStringConvertible {
        public var line: Int
        public var step: String
        public var message: String

        public var description: String {
            "line \(line) (\(step)): \(message)"
        }
    }

    /// `chordTimer` is the one the session was created with, so that `!tick`
    /// can fire it.
    public static func run(_ script: ReplayScript, in session: InputSession, chordTimer: ManualChordTimer? = nil) -> [Failure] {
        var marked = MarkedText.empty
        var candidates: CandidateSnapshot?
        var failures: [Failure] = []
        var asyncActions: [SessionAction] = []
        session.onAsyncActions = { asyncActions += $0 }
        defer { session.onAsyncActions = nil }

        for step in script.steps {
            for option in step.options {
                session.setOption(option.name, option.value)
            }
            var handled: Bool?
            var actions: [SessionAction]
            switch step.input {
            case .key(let key):
                let result = session.handle(key)
                handled = result.handled
                actions = result.actions
            case .action(let action):
                actions = perform(action, step: step, session: session, chordTimer: chordTimer)
            }
            actions = asyncActions + actions
            asyncActions = []

            var committed: [String] = []
            var announced: [String] = []
            for action in actions {
                switch action {
                case .commit(let text):
                    committed.append(text)
                    marked = .empty
                case .setMarkedText(let markedText):
                    marked = markedText
                case .showCandidates(let snapshot):
                    candidates = snapshot
                case .hideCandidates:
                    candidates = nil
                case .showStatus(let message):
                    announced.append(message)
                }
            }
            let name = switch step.input {
            case .key(let key): key.description
            case .action(let action): "\(action)"
            }
            func fail(_ message: String) {
                failures.append(Failure(line: step.line, step: name, message: message))
            }
            for expectation in step.expectations {
                switch expectation {
                case .commit(let expected):
                    let actual = committed.isEmpty ? nil : committed.joined()
                    if actual != expected {
                        fail("committed \(describe(actual)), expected \(describe(expected))")
                    }
                case .status(let expected):
                    let actual = announced.last
                    if actual != expected {
                        fail("announced \(describe(actual)), expected \(describe(expected))")
                    }
                case .marked(let expected):
                    if marked.text != expected {
                        fail("marked text \(describe(marked.text)), expected \(describe(expected))")
                    }
                case .caret(let expected):
                    if marked.caret != expected {
                        fail("caret \(marked.caret), expected \(expected)")
                    }
                case .candidates(let expected):
                    let texts = candidates?.entries.map(\.text) ?? []
                    let actual = texts.isEmpty ? nil : texts
                    if let expected {
                        if actual.map({ Array($0.prefix(expected.count)) }) != expected {
                            fail("candidates \(describe(actual)), expected to start with \(describe(expected))")
                        }
                    } else if actual != nil {
                        fail("candidates \(describe(actual)), expected none")
                    }
                case .highlighted(let expected):
                    if candidates?.highlightedIndex != expected {
                        fail("highlighted \(describe(candidates?.highlightedIndex)), expected \(expected)")
                    }
                case .page(let expected):
                    if candidates?.pageNumber != expected {
                        fail("page \(describe(candidates?.pageNumber)), expected \(expected)")
                    }
                case .handled(let expected):
                    if handled != expected {
                        fail(expected ? "not handled" : "handled")
                    }
                case .option(let name, let expected):
                    let actual = session.option(name)
                    if actual != expected {
                        fail("option \(name) is \(actual.map(String.init) ?? "unavailable"), expected \(expected)")
                    }
                }
            }
        }
        return failures
    }

    private static func perform(
        _ action: ReplayScript.Action,
        step: ReplayScript.Step,
        session: InputSession,
        chordTimer: ManualChordTimer?
    ) -> [SessionAction] {
        switch action {
        case .commitComposition:
            return session.commitComposition()
        case .select(let index):
            return session.selectCandidate(at: index)
        case .page(let direction):
            return session.changePage(direction)
        case .caret(let move):
            return session.moveCaret(move)
        case .tick:
            chordTimer?.fire()
            return []
        case .notify(let type, let value):
            guard let sessionID = session.currentSessionID else { return [] }
            return session.status(
                for: RimeNotification(sessionID: sessionID, type: type, value: value),
                notifications: step.notifications,
                messageType: step.messageType
            )
        }
    }

    private static func describe(_ value: String?) -> String {
        value.map { "\"\($0)\"" } ?? "none"
    }

    private static func describe(_ values: [String]?) -> String {
        values.map { $0.map { "\"\($0)\"" }.joined(separator: " ") } ?? "none"
    }

    private static func describe(_ value: Int?) -> String {
        value.map(String.init) ?? "none"
    }
}
