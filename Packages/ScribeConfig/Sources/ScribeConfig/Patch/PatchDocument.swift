/// A `*.custom.yaml` read line by line: where its `patch:` map is, and the
/// lines each patch entry spans. Only the structure an edit needs is parsed;
/// the text itself is never normalized.
struct PatchDocument: Equatable {
    struct Line: Equatable {
        var content: String
        /// "\n", "\r\n", or "" for a last line without one.
        var ending: String
    }

    struct Entry: Equatable {
        /// As librime reads it: unquoted.
        var key: String
        /// As written, quotes included.
        var rawKey: String
        var indent: Int
        /// The key line.
        var start: Int
        /// The last line of the value, inclusive. Blank lines and comments
        /// after it are not part of the entry.
        var end: Int
        /// The comment after the key line's value, with the spaces before it,
        /// or "".
        var trailingComment: String
        /// Comment lines between `start` and `end`.
        var innerComments: [Int]
    }

    var hasByteOrderMark: Bool
    var lines: [Line]
    /// The line ending new lines get: the file's first one, or "\n".
    var newline: String
    /// The `patch:` line, if there is one.
    var patchLine: Int?
    /// One past the last line of the patch block.
    var blockEnd: Int
    /// The indentation of the entries, or nil while there are none.
    var entryIndent: Int?
    /// The indentation step for nested lines.
    var unit: Int
    var entries: [Entry]

    var text: String {
        var text = hasByteOrderMark ? "\u{FEFF}" : ""
        for line in lines {
            text += line.content
            text += line.ending
        }
        return text
    }

    func entry(_ key: String) -> Entry? {
        entries.first { $0.key.utf8.elementsEqual(key.utf8) }
    }

    init(parsing text: String) throws(CustomPatchError) {
        var bytes = Array(text.utf8)
        hasByteOrderMark = bytes.starts(with: [0xEF, 0xBB, 0xBF])
        if hasByteOrderMark {
            bytes.removeFirst(3)
        }
        lines = Self.split(bytes)
        newline = lines.first { !$0.ending.isEmpty }?.ending ?? "\n"
        patchLine = nil
        blockEnd = lines.count
        entryIndent = nil
        unit = 2
        entries = []

        let infos = try Self.analyze(lines)
        try findPatch(infos)
        if let patchLine {
            try parseEntries(infos, after: patchLine)
        }
    }

    // MARK: - Lines

    private enum Kind: Equatable {
        case blank, comment, marker, content
        /// Inside a block scalar (`|` or `>`): text, whatever it looks like.
        case scalarText
    }

    private struct LineInfo {
        var kind: Kind
        var indent: Int
        /// The line after its indentation, as UTF-8.
        var rest: ArraySlice<UInt8>
        var scan: LineScan
    }

    private static func split(_ bytes: [UInt8]) -> [Line] {
        var lines: [Line] = []
        var start = 0
        while start < bytes.count {
            guard let newline = bytes[start...].firstIndex(of: UInt8(ascii: "\n")) else {
                lines.append(Line(content: String(decoding: bytes[start...], as: UTF8.self), ending: ""))
                break
            }
            let crlf = newline > start && bytes[newline - 1] == UInt8(ascii: "\r")
            let end = crlf ? newline - 1 : newline
            lines.append(Line(content: String(decoding: bytes[start..<end], as: UTF8.self), ending: crlf ? "\r\n" : "\n"))
            start = newline + 1
        }
        return lines
    }

    /// Classifies every line and rejects what no edit can handle safely:
    /// tabs in indentation, node properties, complex keys and extra documents.
    private static func analyze(_ lines: [Line]) throws(CustomPatchError) -> [LineInfo] {
        var infos: [LineInfo] = []
        var scalarParentIndent: Int?
        var seenContent = false
        var seenMarker = false
        for (index, line) in lines.enumerated() {
            let bytes = Array(line.content.utf8)
            let whitespace = bytes.prefix { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") }
            let indent = whitespace.prefix { $0 == UInt8(ascii: " ") }.count
            let rest = bytes[whitespace.count...]
            var info = LineInfo(kind: .content, indent: indent, rest: rest, scan: LineScan())

            if let parent = scalarParentIndent {
                if rest.isEmpty || indent > parent {
                    info.kind = .scalarText
                    infos.append(info)
                    continue
                }
                scalarParentIndent = nil
            }
            if rest.isEmpty {
                info.kind = .blank
            } else if rest.first == UInt8(ascii: "#") {
                info.kind = .comment
            } else if whitespace.isEmpty, let marker = documentMarker(rest) {
                guard marker == .start, !seenContent, !seenMarker else {
                    throw .unsupportedLayout(line: index + 1, reason: .multipleDocuments)
                }
                // Only a comment may follow the marker.
                let after = rest.dropFirst(3).drop { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") }
                guard after.isEmpty || after.first == UInt8(ascii: "#") else {
                    throw .unsupportedLayout(line: index + 1, reason: .invalidEntry)
                }
                seenMarker = true
                info.kind = .marker
            } else {
                if whitespace.contains(UInt8(ascii: "\t")) {
                    throw .unsupportedLayout(line: index + 1, reason: .tabIndentation)
                }
                info.scan = LineScan(rest)
                if let problem = info.scan.problem {
                    throw .unsupportedLayout(line: index + 1, reason: problem)
                }
                if info.scan.opensBlockScalar {
                    scalarParentIndent = indent
                }
                seenContent = true
            }
            infos.append(info)
        }
        return infos
    }

    private enum Marker { case start, end }

    private static func documentMarker(_ rest: ArraySlice<UInt8>) -> Marker? {
        for (prefix, marker) in [("---", Marker.start), ("...", Marker.end)] where rest.starts(with: prefix.utf8) {
            let after = rest.dropFirst(3)
            if after.isEmpty || after.first == UInt8(ascii: " ") || after.first == UInt8(ascii: "\t") {
                return marker
            }
        }
        return nil
    }

    // MARK: - Top level

    /// Finds the top-level `patch:` key and where its block ends.
    private mutating func findPatch(_ infos: [LineInfo]) throws(CustomPatchError) {
        var seenTopLevel = false
        // After a top-level key with no inline value other than patch, its
        // value may be a compact sequence at column 0, such as `__patch:`
        // followed by `- rime_ice_suggestion:/`.
        var sequenceAllowed = false
        for (index, info) in infos.enumerated() where info.kind == .content {
            if !seenTopLevel && info.indent > 0 {
                throw .unsupportedLayout(line: index + 1, reason: .indentedPatch)
            }
            guard info.indent == 0 else { continue }
            seenTopLevel = true
            if patchLine != nil && blockEnd == lines.count {
                blockEnd = index
            }
            if sequenceAllowed && Self.isSequenceItem(info.rest) {
                continue
            }
            guard let key = KeyLine(info.rest, scan: info.scan) else {
                throw .unsupportedLayout(line: index + 1, reason: .invalidEntry)
            }
            sequenceAllowed = key.value.isEmpty && key.key != "patch"
            guard key.key == "patch" else { continue }
            guard patchLine == nil else {
                throw .unsupportedLayout(line: index + 1, reason: .duplicateKey)
            }
            if key.value.first == UInt8(ascii: "{") {
                throw .unsupportedLayout(line: index + 1, reason: .flowPatch)
            }
            guard key.value.isEmpty else {
                throw .unsupportedLayout(line: index + 1, reason: .invalidEntry)
            }
            patchLine = index
        }
    }

    // MARK: - Entries

    private mutating func parseEntries(_ infos: [LineInfo], after patchLine: Int) throws(CustomPatchError) {
        enum Value {
            /// The key line has its value.
            case inline
            /// Nothing yet after `key:`.
            case pending
            /// Lines indented deeper than the entry.
            case nested
            /// `- item` lines at the entry's own indentation.
            case compactSequence
        }
        var value = Value.pending
        // Indentation and content column of the enclosing lines, for the indent step.
        var parents: [(indent: Int, column: Int)] = []
        var steps: [Int] = []

        for index in (patchLine + 1)..<blockEnd {
            let info = infos[index]
            switch info.kind {
            case .blank, .comment, .marker:
                continue
            case .scalarText:
                guard !entries.isEmpty else { throw .unsupportedLayout(line: index + 1, reason: .invalidEntry) }
                entries[entries.count - 1].end = index
                continue
            case .content:
                break
            }
            let indent = info.indent
            let isItem = Self.isSequenceItem(info.rest)
            let entryIndent = self.entryIndent ?? indent
            if self.entryIndent == nil {
                guard !isItem else { throw .unsupportedLayout(line: index + 1, reason: .invalidEntry) }
                self.entryIndent = indent
            }
            guard indent >= entryIndent else {
                throw .unsupportedLayout(line: index + 1, reason: .inconsistentIndentation)
            }

            while let last = parents.last, last.indent >= indent {
                parents.removeLast()
            }
            if indent > entryIndent, let parent = parents.last, indent > parent.column {
                steps.append(indent - parent.column)
            }
            parents.append((indent, indent + Self.itemPrefixLength(info.rest)))

            if indent > entryIndent {
                if case .pending = value { value = .nested }
                entries[entries.count - 1].end = index
            } else if isItem {
                switch value {
                case .pending, .compactSequence:
                    value = .compactSequence
                    entries[entries.count - 1].end = index
                case .inline, .nested:
                    throw .unsupportedLayout(line: index + 1, reason: .invalidEntry)
                }
            } else {
                guard let key = KeyLine(info.rest, scan: info.scan) else {
                    throw .unsupportedLayout(line: index + 1, reason: .invalidEntry)
                }
                guard entry(key.key) == nil else {
                    throw .unsupportedLayout(line: index + 1, reason: .duplicateKey)
                }
                entries.append(Entry(
                    key: key.key, rawKey: key.rawKey, indent: indent, start: index, end: index,
                    trailingComment: key.comment, innerComments: []
                ))
                value = key.value.isEmpty ? .pending : .inline
            }
        }

        unit = steps.min() ?? 2
        for index in entries.indices {
            let entry = entries[index]
            entries[index].innerComments = ((entry.start + 1)..<max(entry.end, entry.start + 1)).filter {
                infos[$0].kind == .comment
            }
        }
    }

    /// `-` followed by a space or the end of the line.
    private static func isSequenceItem(_ rest: ArraySlice<UInt8>) -> Bool {
        rest.first == UInt8(ascii: "-") && (rest.count == 1 || rest.dropFirst().first == UInt8(ascii: " "))
    }

    /// The width of the `- ` indicators that start a line, such as 4 for `- - a`.
    private static func itemPrefixLength(_ rest: ArraySlice<UInt8>) -> Int {
        var rest = rest
        var length = 0
        while isSequenceItem(rest) {
            let spaces = rest.dropFirst().prefix { $0 == UInt8(ascii: " ") }.count
            length += 1 + spaces
            rest = rest.dropFirst(1 + spaces)
        }
        return length
    }
}

/// A `key: value` line: the key as written and as librime reads it, the
/// inline value and the trailing comment.
struct KeyLine {
    var rawKey: String
    var key: String
    /// The inline value without its comment, trimmed; empty for none.
    var value: ArraySlice<UInt8>
    /// The comment with the whitespace before it, or "".
    var comment: String

    init?(_ rest: ArraySlice<UInt8>, scan: LineScan) {
        let code = rest[..<(scan.commentStart.map(Self.whitespaceStart(in: rest)) ?? rest.endIndex)]
        let keyEnd: Int
        if rest.first == UInt8(ascii: "\"") || rest.first == UInt8(ascii: "'") {
            guard let quoted = YAMLQuoted(code) else { return nil }
            key = quoted.value
            keyEnd = quoted.end
        } else {
            guard let first = code.first, !Self.indicators.contains(first) else { return nil }
            guard let colon = Self.mappingColon(in: code) else { return nil }
            var end = colon
            while end > code.startIndex, code[end - 1] == UInt8(ascii: " ") || code[end - 1] == UInt8(ascii: "\t") {
                end -= 1
            }
            key = String(decoding: code[..<end], as: UTF8.self)
            keyEnd = end
        }
        var cursor = keyEnd
        while cursor < code.endIndex, code[cursor] == UInt8(ascii: " ") || code[cursor] == UInt8(ascii: "\t") {
            cursor += 1
        }
        guard cursor < code.endIndex, code[cursor] == UInt8(ascii: ":") else { return nil }
        let afterColon = cursor + 1
        guard afterColon == code.endIndex || code[afterColon] == UInt8(ascii: " ") || code[afterColon] == UInt8(ascii: "\t")
        else { return nil }
        rawKey = String(decoding: rest[rest.startIndex..<keyEnd], as: UTF8.self)
        value = Self.trimmed(code[afterColon...])
        comment = String(decoding: rest[code.endIndex...], as: UTF8.self)
    }

    /// Characters that cannot start a plain key.
    private static let indicators: Set<UInt8> = Set("-?:,[]{}#&*!|>'\"%@`".utf8)

    /// The first `:` followed by a space, a tab or the end.
    private static func mappingColon(in code: ArraySlice<UInt8>) -> Int? {
        var index = code.startIndex
        while index < code.endIndex {
            if code[index] == UInt8(ascii: ":") {
                let next = index + 1
                if next == code.endIndex || code[next] == UInt8(ascii: " ") || code[next] == UInt8(ascii: "\t") {
                    return index
                }
            }
            index += 1
        }
        return nil
    }

    /// Where the whitespace before a comment starts.
    private static func whitespaceStart(in rest: ArraySlice<UInt8>) -> (Int) -> Int {
        { hash in
            var start = hash
            while start > rest.startIndex, rest[start - 1] == UInt8(ascii: " ") || rest[start - 1] == UInt8(ascii: "\t") {
                start -= 1
            }
            return start
        }
    }

    private static func trimmed(_ bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        let isSpace = { (byte: UInt8) in byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") }
        guard let first = bytes.firstIndex(where: { !isSpace($0) }), let last = bytes.lastIndex(where: { !isSpace($0) })
        else { return [] }
        return bytes[first...last]
    }
}

/// A cheap scan of one YAML line that skips quoted text: where its comment
/// starts, whether it opens a block scalar, and node properties or complex
/// keys, which the editor does not handle.
struct LineScan {
    /// The index of the `#` that starts the comment.
    var commentStart: Int?
    var opensBlockScalar = false
    var problem: UnsupportedLayout?

    init() {}

    init(_ bytes: ArraySlice<UInt8>) {
        var index = bytes.startIndex
        var atNodeStart = true
        var flowDepth = 0
        var quote: UInt8?
        func byte(_ offset: Int) -> UInt8? {
            index + offset < bytes.endIndex ? bytes[index + offset] : nil
        }
        func isBreak(_ byte: UInt8?) -> Bool {
            byte == nil || byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
        }
        while index < bytes.endIndex {
            let current = bytes[index]
            if let open = quote {
                if open == UInt8(ascii: "\"") && current == UInt8(ascii: "\\") {
                    index += 2
                    continue
                }
                if current == open {
                    if open == UInt8(ascii: "'") && byte(1) == UInt8(ascii: "'") {
                        index += 2
                        continue
                    }
                    quote = nil
                }
                index += 1
                continue
            }
            if current == UInt8(ascii: "#") && (index == bytes.startIndex || isBreak(bytes[index - 1])) {
                commentStart = index
                return
            }
            if isBreak(current) {
                index += 1
                continue
            }
            if atNodeStart {
                switch current {
                case UInt8(ascii: "\""), UInt8(ascii: "'"):
                    quote = current
                    atNodeStart = false
                case UInt8(ascii: "&"), UInt8(ascii: "*"):
                    problem = .anchorOrAlias
                    return
                case UInt8(ascii: "!"):
                    problem = .tag
                    return
                case UInt8(ascii: "|"), UInt8(ascii: ">"):
                    opensBlockScalar = flowDepth == 0
                    atNodeStart = false
                case UInt8(ascii: "-") where isBreak(byte(1)):
                    break
                case UInt8(ascii: "?") where isBreak(byte(1)):
                    problem = .complexKey
                    return
                case UInt8(ascii: "["), UInt8(ascii: "{"):
                    flowDepth += 1
                default:
                    atNodeStart = false
                }
                index += 1
                continue
            }
            switch current {
            case UInt8(ascii: ":") where isBreak(byte(1)) || (flowDepth > 0 && ",]}".utf8.contains(byte(1) ?? 0)):
                atNodeStart = true
            case UInt8(ascii: ",") where flowDepth > 0:
                atNodeStart = true
            case UInt8(ascii: "]"), UInt8(ascii: "}"):
                flowDepth = max(flowDepth - 1, 0)
            default:
                break
            }
            index += 1
        }
    }
}

/// A single- or double-quoted scalar at the start of some bytes.
struct YAMLQuoted {
    var value: String
    /// One past the closing quote.
    var end: Int

    init?(_ bytes: ArraySlice<UInt8>) {
        guard let open = bytes.first, open == UInt8(ascii: "\"") || open == UInt8(ascii: "'") else { return nil }
        var result: [UInt8] = []
        var index = bytes.startIndex + 1
        while index < bytes.endIndex {
            let current = bytes[index]
            if open == UInt8(ascii: "'") {
                if current == UInt8(ascii: "'") {
                    if index + 1 < bytes.endIndex, bytes[index + 1] == UInt8(ascii: "'") {
                        result.append(current)
                        index += 2
                        continue
                    }
                    value = String(decoding: result, as: UTF8.self)
                    end = index + 1
                    return
                }
                result.append(current)
                index += 1
                continue
            }
            switch current {
            case UInt8(ascii: "\""):
                value = String(decoding: result, as: UTF8.self)
                end = index + 1
                return
            case UInt8(ascii: "\\"):
                guard index + 1 < bytes.endIndex else { return nil }
                let escape = bytes[index + 1]
                index += 2
                switch escape {
                case UInt8(ascii: "n"): result.append(0x0A)
                case UInt8(ascii: "t"): result.append(0x09)
                case UInt8(ascii: "r"): result.append(0x0D)
                case UInt8(ascii: "0"): result.append(0x00)
                case UInt8(ascii: "x"), UInt8(ascii: "u"), UInt8(ascii: "U"):
                    let length = escape == UInt8(ascii: "x") ? 2 : escape == UInt8(ascii: "u") ? 4 : 8
                    guard index + length <= bytes.endIndex,
                          let code = UInt32(String(decoding: bytes[index..<(index + length)], as: UTF8.self), radix: 16),
                          let scalar = Unicode.Scalar(code)
                    else { return nil }
                    result.append(contentsOf: Array(String(Character(scalar)).utf8))
                    index += length
                default:
                    result.append(escape)
                }
            default:
                result.append(current)
                index += 1
            }
        }
        return nil
    }
}
