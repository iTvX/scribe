/// The colours of one theme, with Squirrel's fallbacks already applied.
/// Optional colours are not drawn when nil.
public struct ThemeColors: Equatable, Sendable {
    public var background: ThemeColor
    /// Behind the selected part of the preedit.
    public var hilitedPreeditBackground: ThemeColor?
    /// Behind the highlighted candidate.
    public var hilitedCandidateBackground: ThemeColor?
    public var preeditBackground: ThemeColor?
    public var candidateBackground: ThemeColor?
    public var border: ThemeColor?
    /// Preedit text.
    public var text: ThemeColor
    /// The selected part of the preedit.
    public var hilitedText: ThemeColor
    public var candidateText: ThemeColor
    public var hilitedCandidateText: ThemeColor
    public var label: ThemeColor
    public var hilitedCandidateLabel: ThemeColor
    public var commentText: ThemeColor
    public var hilitedCommentText: ThemeColor
    /// Comments a plugin marks as highlighted (rime/squirrel#1124).
    public var accentText: ThemeColor?
    /// Comments a plugin marks as warnings (rime/squirrel#1124).
    public var warningText: ThemeColor?

    public init(
        background: ThemeColor,
        hilitedPreeditBackground: ThemeColor?,
        hilitedCandidateBackground: ThemeColor?,
        preeditBackground: ThemeColor?,
        candidateBackground: ThemeColor?,
        border: ThemeColor?,
        text: ThemeColor,
        hilitedText: ThemeColor,
        candidateText: ThemeColor,
        hilitedCandidateText: ThemeColor,
        label: ThemeColor,
        hilitedCandidateLabel: ThemeColor,
        commentText: ThemeColor,
        hilitedCommentText: ThemeColor,
        accentText: ThemeColor?,
        warningText: ThemeColor?
    ) {
        self.background = background
        self.hilitedPreeditBackground = hilitedPreeditBackground
        self.hilitedCandidateBackground = hilitedCandidateBackground
        self.preeditBackground = preeditBackground
        self.candidateBackground = candidateBackground
        self.border = border
        self.text = text
        self.hilitedText = hilitedText
        self.candidateText = candidateText
        self.hilitedCandidateText = hilitedCandidateText
        self.label = label
        self.hilitedCandidateLabel = hilitedCandidateLabel
        self.commentText = commentText
        self.hilitedCommentText = hilitedCommentText
        self.accentText = accentText
        self.warningText = warningText
    }

    /// Squirrel's palette when there is no colour scheme or it is "native".
    public static let native = ThemeColors(
        background: .system(.windowBackground),
        hilitedPreeditBackground: nil,
        hilitedCandidateBackground: .system(.selectedTextBackground),
        preeditBackground: nil,
        candidateBackground: nil,
        border: nil,
        text: .system(.secondaryLabel),
        hilitedText: .system(.label),
        candidateText: .system(.label),
        hilitedCandidateText: .system(.label),
        label: .system(.secondaryLabel),
        hilitedCandidateLabel: .system(.secondaryLabel),
        commentText: .system(.secondaryLabel),
        hilitedCommentText: .system(.secondaryLabel),
        accentText: nil,
        warningText: nil
    )

    /// The colours of the scheme at `prefix` (such as
    /// "preset_color_schemes/aqua"), following SquirrelTheme.load. Every key
    /// may be missing.
    init(source: some ConfigSource, prefix: String, colorSpace: ColorSpace) {
        func color(_ key: String) -> ThemeColor? {
            source.parsed(at: "\(prefix)/\(key)") { RGBAColor(squirrel: $0, colorSpace: colorSpace) }
                .map(ThemeColor.rgba)
        }
        background = color("back_color") ?? .system(.windowBackground)
        hilitedPreeditBackground = color("hilited_back_color")
        hilitedCandidateBackground = color("hilited_candidate_back_color") ?? hilitedPreeditBackground
        preeditBackground = color("preedit_back_color")
        candidateBackground = color("candidate_back_color")
        border = color("border_color")
        text = color("text_color") ?? .system(.secondaryLabel)
        hilitedText = color("hilited_text_color") ?? text
        candidateText = color("candidate_text_color") ?? text
        hilitedCandidateText = color("hilited_candidate_text_color") ?? hilitedText
        label = color("label_color") ?? .blend(foreground: candidateText, background: background)
        hilitedCandidateLabel = color("hilited_candidate_label_color")
            ?? .blend(foreground: hilitedCandidateText, background: hilitedCandidateBackground ?? .system(.gray))
        commentText = color("comment_text_color") ?? candidateText
        hilitedCommentText = color("hilited_comment_text_color") ?? hilitedCandidateText
        accentText = color("accent_text_color")
        warningText = color("warning_text_color")
    }
}
