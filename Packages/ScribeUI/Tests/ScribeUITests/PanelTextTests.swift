import AppKit
import ScribeConfig
import ScribeCore
@testable import ScribeUI
import Testing

@MainActor
@Suite struct PanelTextTests {
    private func panelTheme(_ change: (inout Theme) -> Void = { _ in }) -> PanelTheme {
        var theme = Fixtures.squirrelDefaults
        change(&theme)
        return PanelTheme(theme, palette: Fixtures.lightPalette)
    }

    private let page = CandidateSnapshot(
        entries: [.init(label: "1", text: "中书"), .init(label: "2", text: "中枢", comment: "zhōng shū")],
        highlightedIndex: 0
    )

    @Test func stackedRowsAreSeparatedByNewlines() throws {
        let text = try #require(PanelText(PanelContent(page), theme: panelTheme()))
        #expect(text.string.string == "1. 中书 \n2. 中枢 zhōng shū")
        #expect(text.candidateRanges == [NSRange(location: 0, length: 6), NSRange(location: 7, length: 15)])
        #expect(text.highlightedIndex == 0)
        #expect(text.preeditRange == nil)
    }

    @Test func linearRowsAreSeparatedByTwoSpaces() throws {
        let theme = panelTheme { $0.layout = .linear }
        let text = try #require(PanelText(PanelContent(page), theme: theme))
        #expect(text.string.string == "1. 中书   2. 中枢 zhōng shū")
        #expect(text.candidateRanges[1].location == 8)
        let spaceWidth = NSAttributedString(string: "  ", attributes: theme.candidateAttributes).boundingRect(with: .zero, options: [], context: nil).width
        #expect(text.separatorWidth == spaceWidth)
        #expect(text.separatorWidth > 0)
    }

    @Test func preeditComesFirst() throws {
        var snapshot = page
        snapshot.preedit = Preedit(text: "zhong shu", selectedRange: 6..<9, caret: 9)
        let shown = try #require(PanelText(PanelContent(snapshot), theme: panelTheme { $0.inlinePreedit = false }))
        #expect(shown.string.string.hasPrefix("zhong shu\n1. 中书"))
        #expect(shown.preeditRange == NSRange(location: 0, length: 9))
        #expect(shown.highlightedPreeditRange == NSRange(location: 6, length: 3))
        #expect(shown.candidateRanges.first?.location == 10)

        let noPreedit = try #require(PanelText(PanelContent(page), theme: panelTheme { $0.inlinePreedit = false }))
        #expect(noPreedit.preeditRange == nil)
        #expect(noPreedit.string.string.hasPrefix("1. 中书"))
    }

    /// The session decides whether the preedit is inline, per app (Squirrel's
    /// no_inline and inline options); the panel draws whatever preedit the
    /// snapshot has, whatever the theme says.
    @Test func preeditShowsWhateverTheTheme() throws {
        var snapshot = page
        snapshot.preedit = Preedit(text: "zhong shu", selectedRange: 6..<9, caret: 9)
        let inlineTheme = try #require(PanelText(PanelContent(snapshot), theme: panelTheme { $0.inlinePreedit = true }))
        #expect(inlineTheme.preeditRange == NSRange(location: 0, length: 9))
        #expect(inlineTheme.string.string.hasPrefix("zhong shu\n1. 中书"))
    }

    @Test func preeditAloneHasNoTrailingNewline() throws {
        let snapshot = CandidateSnapshot(entries: [], preedit: Preedit(text: "zh", selectedRange: 0..<2, caret: 2))
        let text = try #require(PanelText(PanelContent(snapshot), theme: panelTheme()))
        #expect(text.string.string == "zh")
        #expect(text.candidateRanges.isEmpty)
        let empty = CandidateSnapshot(entries: [], preedit: Preedit(text: "", selectedRange: 0..<0, caret: 0))
        #expect(PanelText(PanelContent(empty), theme: panelTheme()) == nil)
    }

    @Test func statusMessageShowsOnlyWithoutCandidates() throws {
        let status = try #require(PanelText(PanelContent(nil, statusMessage: "中文"), theme: panelTheme()))
        #expect(status.string.string == "中文")
        #expect(status.candidateRanges == [NSRange(location: 0, length: 2)])
        #expect(status.highlightedIndex == -1)
        #expect(PanelText(PanelContent(nil, statusMessage: ""), theme: panelTheme()) == nil)
        #expect(PanelText(PanelContent(nil), theme: panelTheme()) == nil)
        let candidates = try #require(PanelText(PanelContent(page, statusMessage: "中文"), theme: panelTheme()))
        #expect(candidates.candidateRanges.count == 2)
    }

    @Test func formatPlaceholdersAndLabels() throws {
        let fourPerEm = try #require(PanelText(PanelContent(page), theme: panelTheme { $0.candidateFormat = CandidateFormat("[label]\u{2005}[candidate]\u{2005}[comment]") }))
        #expect(fourPerEm.string.string == "1\u{2005}中书\u{2005}\n2\u{2005}中枢\u{2005}zhōng shū")
        let unlabeled = try #require(PanelText(PanelContent(page), theme: panelTheme { $0.candidateFormat = CandidateFormat("[candidate] [comment]") }))
        #expect(unlabeled.string.string == "中书 \n中枢 zhōng shū")
    }

    @Test func candidatesAndCommentsAreComposed() throws {
        let snapshot = CandidateSnapshot(entries: [.init(label: "1", text: "e\u{301}", comment: "a\u{30A}")])
        let text = try #require(PanelText(PanelContent(snapshot), theme: panelTheme()))
        #expect(text.string.string == "1. \u{E9} \u{E5}")
    }

    @Test func partsTakeTheirStyles() throws {
        let theme = panelTheme()
        let text = try #require(PanelText(PanelContent(page), theme: theme))
        let string = text.string
        func color(at index: Int) -> NSColor? {
            string.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
        }
        // Row 1 is highlighted, row 2 is not.
        #expect(color(at: 0) == theme.highlightedCandidateLabelColor)
        #expect(color(at: 3) == theme.highlightedCandidateTextColor)
        #expect(color(at: 7) == theme.candidateLabelColor)
        #expect(color(at: 10) == theme.candidateTextColor)
        #expect(color(at: 13) == theme.commentTextColor)
        #expect(string.attribute(.font, at: 13, effectiveRange: nil) as? NSFont == theme.commentFont)
        #expect(string.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == theme.labelFont)
    }

    @Test func accentAndWarningColourUnhighlightedComments() throws {
        let snapshot = CandidateSnapshot(
            entries: (0..<4).map { .init(label: "\($0 + 1)", text: "字", comment: "c") },
            highlightedIndex: 0
        )
        let theme = panelTheme {
            $0.colors.accentText = .rgba(RGBAColor(red: 255, green: 0, blue: 0))
            $0.colors.warningText = .rgba(RGBAColor(red: 0, green: 0, blue: 255))
        }
        let content = PanelContent(snapshot, accentCommentIndices: [0, 1, 2], warningCommentIndices: [2, 3])
        let text = try #require(PanelText(content, theme: theme))
        func commentColor(_ row: Int) -> NSColor? {
            let range = text.candidateRanges[row]
            return text.string.attribute(.foregroundColor, at: NSMaxRange(range) - 1, effectiveRange: nil) as? NSColor
        }
        #expect(commentColor(0) == theme.highlightedCommentTextColor)
        #expect(commentColor(1) == theme.accentCommentTextColor)
        #expect(commentColor(2) == theme.accentCommentTextColor)
        #expect(commentColor(3) == theme.warningCommentTextColor)

        // Without an accent colour the comment keeps the label colour the
        // format started with, as in Squirrel.
        let uncoloured = try #require(PanelText(content, theme: panelTheme()))
        let range = uncoloured.candidateRanges[1]
        #expect(uncoloured.string.attribute(.foregroundColor, at: NSMaxRange(range) - 1, effectiveRange: nil) as? NSColor == panelTheme().candidateLabelColor)
    }

    @Test func stackedRowsIndentWrappedLinesUnderTheCandidate() throws {
        let theme = panelTheme()
        let text = try #require(PanelText(PanelContent(page), theme: theme))
        let style = try #require(text.string.attribute(.paragraphStyle, at: text.candidateRanges[1].location, effectiveRange: nil) as? NSParagraphStyle)
        let label = NSAttributedString(string: "2. ", attributes: theme.labelAttributes)
        #expect(style.headIndent == label.boundingRect(with: .zero, options: [.usesLineFragmentOrigin], context: nil).width)
        #expect(style.paragraphSpacingBefore == theme.lineSpacing / 2)
        let first = try #require(text.string.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(first.paragraphSpacingBefore == theme.spacing / 2)

        let linear = panelTheme { $0.layout = .linear }
        let linearText = try #require(PanelText(PanelContent(page), theme: linear))
        let linearStyle = try #require(linearText.string.attribute(.paragraphStyle, at: linearText.candidateRanges[1].location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(linearStyle.headIndent == 0)
        #expect(linearStyle.lineSpacing == linear.lineSpacing)
        #expect(linearStyle.paragraphSpacingBefore == -linear.lineSpacing / 2)
    }

    @Test func shortRowsDoNotBreak() throws {
        let snapshot = CandidateSnapshot(entries: [.init(label: "1", text: "中书"), .init(label: "2", text: "中书", comment: "zhong shu zhong")])
        let text = try #require(PanelText(PanelContent(snapshot), theme: panelTheme()))
        func noBreaks(in range: NSRange) -> [Int] {
            (range.location..<NSMaxRange(range)).filter { text.string.attribute(.noBreak, at: $0, effectiveRange: nil) as? Bool == true }
        }
        let short = text.candidateRanges[0]
        #expect(noBreaks(in: short) == Array((short.location + 1)..<NSMaxRange(short)))
        // A replaced placeholder takes the style of its first character, so
        // the candidate's own no-break mark is lost in longer rows, as in
        // Squirrel.
        #expect(noBreaks(in: text.candidateRanges[1]).isEmpty)
    }

    @Test func pagingFollowsTheSnapshot() throws {
        let middle = try #require(PanelText(PanelContent(CandidateSnapshot(entries: page.entries, pageNumber: 2, isLastPage: false)), theme: panelTheme()))
        #expect(middle.canPageUp && middle.canPageDown)
        let first = try #require(PanelText(PanelContent(page), theme: panelTheme()))
        #expect(!first.canPageUp && !first.canPageDown)
    }

    @Test func statusMessageType() {
        #expect(PanelContent.statusMessage(long: "中文", short: "中", type: .mix) == "中")
        #expect(PanelContent.statusMessage(long: "中文", short: "", type: .mix) == "中文")
        #expect(PanelContent.statusMessage(long: "中文", short: "中", type: .long) == "中文")
        #expect(PanelContent.statusMessage(long: "西文", short: "", type: .short) == "西")
        #expect(PanelContent.statusMessage(long: "", short: "", type: .short) == "")
    }
}
