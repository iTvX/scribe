import Foundation
@testable import ScribeConfig
import Testing

/// One edit and what it must leave untouched: deleting the edited entries
/// from the text before and after leaves the same lines, and every new line
/// uses the file's line ending.
enum PatchEdit {
    case set(String, ConfigNode)
    case remove(String)
    case removeDescendants(String)

    /// Applies the edit, checks the invariant, and returns the new text.
    func apply(to text: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        let before = try PatchDocument(parsing: text)
        var editor = try CustomPatchEditor(text: text)
        var untouchedBefore = before.lines.map(\.content)
        var untouchedAfter: [String]

        switch self {
        case .set(let key, let value):
            editor.set(key, to: value)
            let after = try PatchDocument(parsing: editor.text)
            untouchedAfter = after.lines.map(\.content)
            let entry = try #require(after.entry(key), sourceLocation: sourceLocation)
            if let old = before.entry(key) {
                untouchedBefore.removeSubrange(old.start...old.end)
                // The comments inside the old value follow the new one.
                untouchedAfter.removeSubrange(entry.start...(entry.end + old.innerComments.count))
            } else {
                untouchedAfter.removeSubrange(entry.start...entry.end)
                if before.patchLine == nil {
                    untouchedAfter.remove(at: entry.start - 1)
                }
            }
        case .remove(let key):
            let existed = before.entry(key) != nil
            let removed = editor.remove(key)
            #expect(removed == existed, sourceLocation: sourceLocation)
            untouchedBefore = Self.removingContent(of: before.entry(key).map { [$0] } ?? [], from: before)
            untouchedAfter = try PatchDocument(parsing: editor.text).lines.map(\.content)
        case .removeDescendants(let key):
            let removed = before.entries.filter { $0.key.hasPrefix(key + "/") }
            let removedKeys = editor.removeDescendants(of: key)
            #expect(removedKeys == removed.map(\.key), sourceLocation: sourceLocation)
            untouchedBefore = Self.removingContent(of: removed, from: before)
            untouchedAfter = try PatchDocument(parsing: editor.text).lines.map(\.content)
        }

        #expect(untouchedAfter == untouchedBefore, "lines outside the edit changed", sourceLocation: sourceLocation)
        let after = try PatchDocument(parsing: editor.text)
        #expect(after.lines.dropLast().allSatisfy { $0.ending == before.newline }, sourceLocation: sourceLocation)
        #expect(after.hasByteOrderMark == before.hasByteOrderMark, sourceLocation: sourceLocation)
        #expect((after.lines.last?.ending.isEmpty ?? false) == (before.lines.last?.ending.isEmpty ?? false),
                "the final newline changed", sourceLocation: sourceLocation)
        return editor.text
    }

    /// The lines left after deleting entries but keeping their inner comments.
    private static func removingContent(of entries: [PatchDocument.Entry], from document: PatchDocument) -> [String] {
        var deleted = Set<Int>()
        for entry in entries {
            deleted.formUnion(Set(entry.start...entry.end).subtracting(entry.innerComments))
        }
        return document.lines.indices.filter { !deleted.contains($0) }.map { document.lines[$0].content }
    }
}

/// Applies an edit and compares the result with the expected text.
func expectEdit(_ edit: PatchEdit, in text: String, gives expected: String,
                sourceLocation: SourceLocation = #_sourceLocation) throws {
    let result = try edit.apply(to: text, sourceLocation: sourceLocation)
    #expect(result == expected, sourceLocation: sourceLocation)
    // Doing it again changes nothing.
    if case .set = edit {
        #expect(try edit.apply(to: result, sourceLocation: sourceLocation) == result, sourceLocation: sourceLocation)
    }
}
