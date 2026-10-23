/// Edits the `patch:` map of a Rime `*.custom.yaml` in place. Only the entries it sets or removes change; every other
/// byte (comments, blank lines, order, quoting, line endings) stays as it was.
///
/// An entry spans its key line and the lines of its value, including a
/// compact sequence at the entry's own indentation. Comment lines inside a
/// span survive edits: a replaced value is followed by them, one level
/// deeper than the entry, and a removed entry leaves them where they were.
public struct CustomPatchEditor: Equatable, Sendable {
    public private(set) var text: String
    private var document: PatchDocument

    /// "" (or a missing file) is an empty document. Throws for layouts it cannot edit safely.
    public init(text: String) throws(CustomPatchError) {
        self.text = text
        document = try PatchDocument(parsing: text)
    }

    /// Patch keys in file order, unquoted, exactly as librime reads them ("switcher/hotkeys", "schema_list/+").
    public var keys: [String] {
        document.entries.map(\.key)
    }

    /// Replaces the entry for `key` (keeping its key spelling) or appends a new entry at the end of the patch map.
    public mutating func set(_ key: String, to value: ConfigNode) {
        var lines = document.lines
        let renderer = PatchRenderer(unit: document.unit)
        if let entry = document.entry(key) {
            let commentPad = String(repeating: " ", count: entry.indent + document.unit)
            let comments = entry.innerComments.map { index in
                commentPad + lines[index].content.drop { $0 == " " }
            }
            let replacement = renderer.entry(rawKey: entry.rawKey, value: value, indent: entry.indent,
                                             comment: entry.trailingComment) + comments
            replace(&lines, entry.start...entry.end, with: replacement)
        } else if let patchLine = document.patchLine {
            let at = document.entries.last.map { $0.end + 1 } ?? patchLine + 1
            let indent = document.entryIndent ?? document.unit
            insert(&lines, renderer.entry(rawKey: PatchRenderer.key(key), value: value, indent: indent), at: at)
        } else {
            let entry = renderer.entry(rawKey: PatchRenderer.key(key), value: value, indent: document.unit)
            insert(&lines, ["patch:"] + entry, at: lines.count)
        }
        update(lines)
    }

    /// Removes the entry for `key`, if any. Returns whether it existed.
    @discardableResult
    public mutating func remove(_ key: String) -> Bool {
        guard let entry = document.entry(key) else { return false }
        var lines = document.lines
        delete(&lines, entry)
        update(lines)
        return true
    }

    /// Removes the entries whose key starts with "<key>/" (such as "schema_list/+", "schema_list/@0",
    /// "ascii_composer/switch_key/Shift_L"). Returns the removed keys in file order.
    @discardableResult
    public mutating func removeDescendants(of key: String) -> [String] {
        let prefix = Array((key + "/").utf8)
        let descendants = document.entries.filter { $0.key.utf8.starts(with: prefix) }
        guard !descendants.isEmpty else { return [] }
        var lines = document.lines
        for entry in descendants.reversed() {
            delete(&lines, entry)
        }
        update(lines)
        return descendants.map(\.key)
    }

    // MARK: - Lines

    /// Deletes an entry's lines except the comments inside it.
    private func delete(_ lines: inout [PatchDocument.Line], _ entry: PatchDocument.Entry) {
        let kept = entry.innerComments.map { lines[$0].content }
        replace(&lines, entry.start...entry.end, with: kept)
    }

    /// Replaces lines with new ones in the file's line ending. A file that
    /// ended without a final newline still does.
    private func replace(_ lines: inout [PatchDocument.Line], _ range: ClosedRange<Int>, with contents: [String]) {
        let endsFile = range.upperBound == lines.count - 1
        let finalEnding = endsFile ? lines[range.upperBound].ending : document.newline
        var replacement = contents.map { PatchDocument.Line(content: $0, ending: document.newline) }
        if !replacement.isEmpty {
            replacement[replacement.count - 1].ending = finalEnding
        }
        lines.replaceSubrange(range, with: replacement)
        if replacement.isEmpty, endsFile, !lines.isEmpty {
            lines[lines.count - 1].ending = finalEnding
        }
    }

    /// Inserts lines before `index`. Appended lines start on a new line, and a
    /// missing final newline stays missing.
    private func insert(_ lines: inout [PatchDocument.Line], _ contents: [String], at index: Int) {
        var inserted = contents.map { PatchDocument.Line(content: $0, ending: document.newline) }
        if index == lines.count, let last = lines.last, last.ending.isEmpty {
            lines[lines.count - 1].ending = document.newline
            inserted[inserted.count - 1].ending = ""
        }
        lines.insert(contentsOf: inserted, at: index)
    }

    private mutating func update(_ lines: [PatchDocument.Line]) {
        var edited = document
        edited.lines = lines
        let text = edited.text
        do {
            document = try PatchDocument(parsing: text)
        } catch {
            preconditionFailure("CustomPatchEditor wrote a layout it cannot read: \(error)")
        }
        self.text = text
    }
}

public enum CustomPatchError: Error, Equatable, Sendable {
    /// `line` is 1-based.
    case unsupportedLayout(line: Int, reason: UnsupportedLayout)
}

/// Why a file cannot be edited safely.
public enum UnsupportedLayout: String, Sendable {
    /// `patch: {…}`
    case flowPatch
    /// A tab in a line's indentation.
    case tabIndentation
    /// `&anchor` or `*alias`.
    case anchorOrAlias
    /// `!tag`
    case tag
    /// A second top-level `patch:`, or a patch key that appears twice.
    case duplicateKey
    /// `? key`
    case complexKey
    /// A `---` after content, or a `...`.
    case multipleDocuments
    /// A `patch:` (or the whole document) not at column 0.
    case indentedPatch
    /// A patch entry indented differently from the first.
    case inconsistentIndentation
    /// Anything else that is not a `key: value` entry where one should be.
    case invalidEntry
}
