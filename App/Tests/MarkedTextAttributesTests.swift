import AppKit
import Carbon
import InputMethodKit
import ScribeCore
import Testing

/// The attributed string and selection Scribe hands the client, compared with
/// Squirrel's `show(preedit:selRange:caretPos:)`: the converted text before
/// the selection is marked `kTSMHiliteConvertedText`, the rest
/// `kTSMHiliteSelectedRawText`, with exactly the attributes InputMethodKit's
/// `mark(forStyle:at:)` returns, and the selection is the caret.
@MainActor
@Suite struct MarkedTextAttributesTests {
    nonisolated static let style = NSAttributedString.Key("style")
    nonisolated static let converted = Int(kTSMHiliteConvertedText)
    nonisolated static let selectedRaw = Int(kTSMHiliteSelectedRawText)

    /// Records the marks asked for, and returns one attribute naming the style.
    final class Marks {
        var requests: [String] = []

        func mark(_ style: Int, _ range: NSRange) -> [NSAttributedString.Key: Any] {
            requests.append("\(style) \(range.location)+\(range.length)")
            return [MarkedTextAttributesTests.style: style]
        }
    }

    /// The string's runs as "start+length key=value …".
    static func runs(_ string: NSAttributedString) -> [String] {
        var runs: [String] = []
        string.enumerateAttributes(in: NSRange(location: 0, length: string.length)) { attributes, range, _ in
            let described = attributes.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: " ")
            runs.append("\(range.location)+\(range.length) \(described)".trimmingCharacters(in: .whitespaces))
        }
        return runs
    }

    @Test func rawInputIsMarkedAsSelectedRawText() {
        let marks = Marks()
        let marked = MarkedText(text: "wo", caret: 2, selectionStart: 0)
        let string = marked.attributedString(marking: marks.mark)
        #expect(string.string == "wo")
        #expect(Self.runs(string) == ["0+2 style=\(Self.selectedRaw)"])
        #expect(marks.requests == ["\(Self.selectedRaw) 0+2"])
        #expect(marked.selectionRange == NSRange(location: 2, length: 0))
    }

    @Test func convertedWordsAreMarkedAsConvertedText() {
        let marks = Marks()
        let marked = MarkedText(text: "你hao", caret: 4, selectionStart: 1)
        let string = marked.attributedString(marking: marks.mark)
        #expect(Self.runs(string) == ["0+1 style=\(Self.converted)", "1+3 style=\(Self.selectedRaw)"])
        #expect(marks.requests == ["\(Self.converted) 0+1", "\(Self.selectedRaw) 1+3"])
        #expect(marked.selectionRange == NSRange(location: 4, length: 0))
    }

    @Test func theSelectionIsTheCaretWhereverItIs() {
        let marks = Marks()
        let marked = MarkedText(text: "xiang zuo guangbiao", caret: 9, selectionStart: 0)
        #expect(Self.runs(marked.attributedString(marking: marks.mark)) == ["0+19 style=\(Self.selectedRaw)"])
        #expect(marked.selectionRange == NSRange(location: 9, length: 0))
    }

    @Test func thePlaceholderIsMarkedToo() {
        let marks = Marks()
        let marked = MarkedText(text: "　", caret: 0, selectionStart: 0)
        #expect(Self.runs(marked.attributedString(marking: marks.mark)) == ["0+1 style=\(Self.selectedRaw)"])
        #expect(marked.selectionRange == NSRange(location: 0, length: 0))
    }

    @Test func aFullyConvertedPreviewStillAsksForTheEmptyRawRange() {
        // As Squirrel does, which keeps the clause numbering the same.
        let marks = Marks()
        let marked = MarkedText(text: "木", caret: 1, selectionStart: 1)
        #expect(Self.runs(marked.attributedString(marking: marks.mark)) == ["0+1 style=\(Self.converted)"])
        #expect(marks.requests == ["\(Self.converted) 0+1", "\(Self.selectedRaw) 1+0"])
    }

    @Test func textBeforeADirectCommitIsUnmarked() {
        let marks = Marks()
        let marked = MarkedText(text: "as", caret: 2, selectionStart: nil)
        #expect(Self.runs(marked.attributedString(marking: marks.mark)) == ["0+2"])
        #expect(marks.requests.isEmpty)
        #expect(marked.selectionRange == NSRange(location: 2, length: 0))
    }

    @Test func noTextRemovesTheMarkedText() {
        let marks = Marks()
        let string = MarkedText.empty.attributedString(marking: marks.mark)
        #expect(string.length == 0)
    }

    /// The real marks are InputMethodKit's underlines and clause numbers, with
    /// no background colour.
    @Test func inputMethodKitMarksAreUnderlines() {
        let controller = IMKInputController()
        for style in [Self.converted, Self.selectedRaw] {
            let attributes = controller.markAttributes(style, NSRange(location: 0, length: 2))
            #expect(attributes[.underlineStyle] != nil)
            #expect(attributes[.markedClauseSegment] != nil)
            #expect(attributes[.backgroundColor] == nil)
        }
    }
}
