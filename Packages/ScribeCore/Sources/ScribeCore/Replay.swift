import Foundation

/// A recorded key sequence with the expected results, for replay tests.
///
/// The format is line based:
///
///     # Comments start with "#"; blank lines are ignored.
///     @engines fake rime        # optional: engines this file applies to
///     @option vim_mode true     # sets a Rime option before the next key
///     n
///     i       => marked "ni"; candidates "你" "泥"
///     space   => commit "你"; marked ""; candidates none
///
/// Each line is one key, named as in `KeyEvent(name:)`, optionally followed
/// by "=>" and expectations separated by ";":
///
/// - `commit "text"` or `commit none`: what this key committed
/// - `marked "text"`: the marked text afterwards; `marked ""` means none
/// - `candidates "a" "b" ...`: the candidates shown afterwards start with
///   these; `candidates none` means there are none
/// - `highlighted N`, `page N`: zero-based highlighted candidate and page
/// - `handled` or `unhandled`: whether the key was consumed
/// - `option NAME true|false`: a Rime option afterwards
public struct ReplayScript: Equatable, Sendable {
    public enum Expectation: Equatable, Sendable {
        case commit(String?)
        case marked(String)
        case candidates([String]?)
        case highlighted(Int)
        case page(Int)
        case handled(Bool)
        case option(String, Bool)
    }

    public struct Step: Equatable, Sendable {
        public var key: KeyEvent
        public var expectations: [Expectation]
        public var line: Int
        /// Options set just before the key.
        public var options: [(String, Bool)] = []

        public static func == (lhs: Step, rhs: Step) -> Bool {
            lhs.key == rhs.key && lhs.expectations == rhs.expectations && lhs.line == rhs.line
                && lhs.options.map(\.0) == rhs.options.map(\.0) && lhs.options.map(\.1) == rhs.options.map(\.1)
        }
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
        var pendingOptions: [(String, Bool)] = []
        for (index, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = index + 1
            let line = Self.stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                continue
            }
            if line.hasPrefix("@engines") {
                engines = Set(line.dropFirst("@engines".count).split(separator: " ").map(String.init))
                continue
            }
            if line.hasPrefix("@option") {
                let words = line.split(separator: " ").map(String.init)
                guard words.count == 3, let value = Bool(words[2]) else {
                    throw ParseError(line: lineNumber, message: "expected \"@option NAME true|false\"")
                }
                pendingOptions.append((words[1], value))
                continue
            }
            let parts: [String] = line.range(of: "=>").map {
                [String(line[..<$0.lowerBound]), String(line[$0.upperBound...])]
            } ?? [line]
            let keyName = parts[0].trimmingCharacters(in: .whitespaces)
            guard let key = KeyEvent(name: keyName) else {
                throw ParseError(line: lineNumber, message: "unknown key \"\(keyName)\"")
            }
            var expectations: [Expectation] = []
            if parts.count == 2 {
                for clause in Self.clauses(parts[1]) {
                    let clause = clause.trimmingCharacters(in: .whitespaces)
                    if clause.isEmpty {
                        continue
                    }
                    guard let expectation = try Self.expectation(clause) else {
                        throw ParseError(line: lineNumber, message: "unknown expectation \"\(clause)\"")
                    }
                    expectations.append(expectation)
                }
            }
            steps.append(Step(key: key, expectations: expectations, line: lineNumber, options: pendingOptions))
            pendingOptions = []
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

    /// A "#" starts a comment unless it is the key itself or inside quotes.
    private static func stripComment(_ line: String) -> String {
        var inQuotes = false
        for (offset, character) in line.enumerated() {
            if character == "\"" {
                inQuotes.toggle()
            } else if character == "#", !inQuotes, offset > 0 {
                return String(line.prefix(offset))
            } else if character == "#", offset == 0 {
                return ""
            }
        }
        return line
    }

    private static func expectation(_ clause: String) throws -> Expectation? {
        let words = clause.split(separator: " ", maxSplits: 1).map(String.init)
        let argument = words.count > 1 ? words[1].trimmingCharacters(in: .whitespaces) : ""
        switch words[0] {
        case "commit":
            return argument == "none" ? .commit(nil) : quoted(argument).first.map { .commit($0) }
        case "marked":
            return quoted(argument).first.map { .marked($0) }
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
        public var key: String
        public var message: String

        public var description: String {
            "line \(line) (\(key)): \(message)"
        }
    }

    public static func run(_ script: ReplayScript, in session: InputSession) -> [Failure] {
        var marked = ""
        var candidates: CandidateSnapshot?
        var failures: [Failure] = []
        for step in script.steps {
            for (name, value) in step.options {
                session.setOption(name, value)
            }
            let result = session.handle(step.key)
            var committed: [String] = []
            for action in result.actions {
                switch action {
                case .commit(let text):
                    committed.append(text)
                    marked = ""
                case .setMarkedText(let markedText):
                    marked = markedText.text
                case .showCandidates(let snapshot):
                    candidates = snapshot
                case .hideCandidates:
                    candidates = nil
                }
            }
            func fail(_ message: String) {
                failures.append(Failure(line: step.line, key: step.key.description, message: message))
            }
            for expectation in step.expectations {
                switch expectation {
                case .commit(let expected):
                    let actual = committed.isEmpty ? nil : committed.joined()
                    if actual != expected {
                        fail("committed \(describe(actual)), expected \(describe(expected))")
                    }
                case .marked(let expected):
                    if marked != expected {
                        fail("marked text \(describe(marked)), expected \(describe(expected))")
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
                    if result.handled != expected {
                        fail(expected ? "key was not handled" : "key was handled")
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
