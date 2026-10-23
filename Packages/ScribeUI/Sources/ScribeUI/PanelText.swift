import AppKit
import ScribeCore

extension NSAttributedString.Key {
    /// TextKit may not break a line before a character carrying this.
    static let noBreak = NSAttributedString.Key("ScribeNoBreak")
}

/// The panel's text, built the way Squirrel builds it, and where each part
/// of it is. Ranges are UTF-16, as in `NSString`.
struct PanelText {
    var string: NSAttributedString
    /// One per candidate row, without the separators between rows. A status
    /// message is a single unhighlighted row.
    var candidateRanges: [NSRange]
    /// -1 when no row is highlighted.
    var highlightedIndex: Int
    var preeditRange: NSRange?
    var highlightedPreeditRange: NSRange?
    /// Width of the space between rows in linear layout, which widens the
    /// candidate backgrounds there.
    var separatorWidth: CGFloat
    var canPageUp: Bool
    var canPageDown: Bool

    /// Nil when the window has nothing to show. The session leaves the
    /// preedit out of the snapshot when it is inline, which Squirrel decides
    /// per app, so a preedit is drawn whenever there is one.
    init?(_ content: PanelContent, theme: PanelTheme) {
        let snapshot = content.snapshot
        let entries = snapshot?.entries ?? []
        let preedit = snapshot?.preedit.flatMap { $0.text.isEmpty ? nil : $0 }
        if preedit == nil && entries.isEmpty {
            guard let message = content.statusMessage, !message.isEmpty else { return nil }
            self.init(statusMessage: message, theme: theme)
            return
        }
        let highlightedIndex = snapshot?.highlightedIndex ?? 0

        let text = NSMutableAttributedString()
        var preeditRange: NSRange?
        var highlightedPreeditRange: NSRange?
        if let preedit {
            let range = NSRange(location: 0, length: (preedit.text as NSString).length)
            let selected = NSRange(location: preedit.selectedRange.lowerBound, length: preedit.selectedRange.count)
            let line = NSMutableAttributedString(string: preedit.text)
            line.addAttributes(theme.preeditAttributes, range: range)
            if let selected = selected.intersection(range) {
                line.addAttributes(theme.highlightedPreeditAttributes, range: selected)
            }
            text.append(line)
            text.addAttribute(.paragraphStyle, value: theme.preeditParagraphStyle, range: range)
            if !entries.isEmpty {
                text.append(NSAttributedString(string: "\n", attributes: theme.preeditAttributes))
            }
            preeditRange = range
            highlightedPreeditRange = selected
        }

        var candidateRanges: [NSRange] = []
        var separatorWidth: CGFloat = 0
        for (index, entry) in entries.enumerated() {
            let highlighted = index == highlightedIndex
            let attributes = highlighted ? theme.highlightedCandidateAttributes : theme.candidateAttributes
            var commentAttributes = highlighted ? theme.highlightedCommentAttributes : theme.commentAttributes
            if !highlighted, let snapshot {
                // Accent wins over warning. A missing accent or warning
                // colour leaves the comment in the label colour, as in
                // Squirrel.
                if snapshot.accentCommentIndices.contains(index) {
                    commentAttributes[.foregroundColor] = theme.accentCommentTextColor
                } else if snapshot.warningCommentIndices.contains(index) {
                    commentAttributes[.foregroundColor] = theme.warningCommentTextColor
                }
            }
            let line = Self.candidateLine(
                entry,
                format: theme.candidateFormat,
                attributes: attributes,
                labelAttributes: highlighted ? theme.highlightedLabelAttributes : theme.labelAttributes,
                commentAttributes: commentAttributes
            )

            let separator = NSAttributedString(string: theme.linear ? "  " : "\n", attributes: attributes)
            if index > 0 {
                text.append(separator)
            }
            let measuredSeparator = NSMutableAttributedString(attributedString: separator)
            if theme.vertical {
                measuredSeparator.addAttribute(.verticalGlyphForm, value: 1, range: NSRange(location: 0, length: measuredSeparator.length))
            }
            separatorWidth = measuredSeparator.boundingRect(with: .zero, options: [], context: nil).width

            let style = (index == 0 ? theme.firstParagraphStyle : theme.paragraphStyle).mutableCopy() as! NSMutableParagraphStyle
            if theme.linear {
                style.paragraphSpacingBefore -= theme.lineSpacing
                style.lineSpacing = theme.lineSpacing
            } else if let labelWidth = line.labelWidth {
                // Wrapped lines start under the candidate, not the label.
                style.headIndent = labelWidth
            }
            line.text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.text.length))

            candidateRanges.append(NSRange(location: text.length, length: line.text.length))
            text.append(line.text)
        }

        self.init(
            string: text,
            candidateRanges: candidateRanges,
            highlightedIndex: highlightedIndex,
            preeditRange: preeditRange,
            highlightedPreeditRange: highlightedPreeditRange,
            separatorWidth: separatorWidth,
            canPageUp: (snapshot?.pageNumber ?? 0) > 0,
            canPageDown: !(snapshot?.isLastPage ?? true)
        )
    }

    private init(statusMessage: String, theme: PanelTheme) {
        let text = NSMutableAttributedString(string: statusMessage, attributes: theme.candidateAttributes)
        let range = NSRange(location: 0, length: text.length)
        text.addAttribute(.paragraphStyle, value: theme.paragraphStyle, range: range)
        self.init(
            string: text,
            candidateRanges: [range],
            highlightedIndex: -1,
            preeditRange: nil,
            highlightedPreeditRange: nil,
            separatorWidth: 0,
            canPageUp: false,
            canPageDown: false
        )
    }

    private init(
        string: NSAttributedString,
        candidateRanges: [NSRange],
        highlightedIndex: Int,
        preeditRange: NSRange?,
        highlightedPreeditRange: NSRange?,
        separatorWidth: CGFloat,
        canPageUp: Bool,
        canPageDown: Bool
    ) {
        self.string = string
        self.candidateRanges = candidateRanges
        self.highlightedIndex = highlightedIndex
        self.preeditRange = preeditRange
        self.highlightedPreeditRange = highlightedPreeditRange
        self.separatorWidth = separatorWidth
        self.canPageUp = canPageUp
        self.canPageDown = canPageDown
    }

    /// One candidate filled into `format`. The format starts out in the
    /// label style; the placeholders take the candidate and comment styles,
    /// and each replacement keeps the style of its placeholder.
    private static func candidateLine(
        _ entry: CandidateSnapshot.Entry,
        format: String,
        attributes: [NSAttributedString.Key: Any],
        labelAttributes: [NSAttributedString.Key: Any],
        commentAttributes: [NSAttributedString.Key: Any]
    ) -> (text: NSMutableAttributedString, labelWidth: CGFloat?) {
        let candidate = entry.text.precomposedStringWithCanonicalMapping
        let comment = (entry.comment ?? "").precomposedStringWithCanonicalMapping
        let line = NSMutableAttributedString(string: format, attributes: labelAttributes)
        for range in format.ranges(of: "[candidate]") {
            let range = NSRange(range, in: format)
            line.addAttributes(attributes, range: range)
            if candidate.count <= 5 {
                line.addAttribute(.noBreak, value: true, range: NSRange(location: range.location + 1, length: range.length - 1))
            }
        }
        for range in format.ranges(of: "[comment]") {
            line.addAttributes(commentAttributes, range: NSRange(range, in: format))
        }
        replace("[label]", with: format.contains("[label]") ? entry.label : "", in: line)

        // The label is everything before the first candidate or comment.
        let labeled = line.string as NSString
        let labelEnd = [labeled.range(of: "[candidate]"), labeled.range(of: "[comment]")]
            .filter { $0.location != NSNotFound }
            .map(\.location)
            .min()
        let labelWidth = labelEnd.map {
            line.attributedSubstring(from: NSRange(location: 0, length: $0))
                .boundingRect(with: .zero, options: [.usesLineFragmentOrigin], context: nil).width
        }

        replace("[candidate]", with: candidate, in: line)
        replace("[comment]", with: comment, in: line)
        if line.length <= 10 && line.length > 0 {
            line.addAttribute(.noBreak, value: true, range: NSRange(location: 1, length: line.length - 1))
        }
        return (line, labelWidth)
    }

    private static func replace(_ placeholder: String, with replacement: String, in line: NSMutableAttributedString) {
        line.mutableString.replaceOccurrences(of: placeholder, with: replacement, options: [], range: NSRange(location: 0, length: line.length))
    }
}
