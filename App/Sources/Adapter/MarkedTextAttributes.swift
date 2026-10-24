import AppKit
import Carbon
import InputMethodKit
import ScribeCore

extension MarkedText {
    /// The text as Squirrel hands it to the client: the converted words
    /// before the selection marked as converted text, the rest as selected
    /// raw input, each with the attributes `mark` gives for that highlight
    /// style and nothing else. With InputMethodKit's marks the client draws
    /// its usual underlines.
    func attributedString(
        marking mark: (_ style: Int, _ range: NSRange) -> [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let string = NSMutableAttributedString(string: text)
        guard let selectionStart else { return string }
        let start = min(selectionStart, string.length)
        if start > 0 {
            let converted = NSRange(location: 0, length: start)
            string.setAttributes(mark(Int(kTSMHiliteConvertedText), converted), range: converted)
        }
        let remaining = NSRange(location: start, length: string.length - start)
        string.setAttributes(mark(Int(kTSMHiliteSelectedRawText), remaining), range: remaining)
        return string
    }

    /// The selection the client keeps: the caret, as in Squirrel.
    var selectionRange: NSRange {
        NSRange(location: caret, length: 0)
    }
}

extension IMKInputController {
    /// `mark(forStyle:at:)`, typed for an attributed string.
    func markAttributes(_ style: Int, _ range: NSRange) -> [NSAttributedString.Key: Any] {
        mark(forStyle: style, at: range) as? [NSAttributedString.Key: Any] ?? [:]
    }
}
