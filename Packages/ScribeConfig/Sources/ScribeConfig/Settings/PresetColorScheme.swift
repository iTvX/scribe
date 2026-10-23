/// One entry of `preset_color_schemes` as written, without Squirrel's
/// fallbacks, for the settings UI and later conversion. (Not `ColorScheme`,
/// which clashes with SwiftUI.)
///
/// A colour that is missing or does not parse is nil. `Theme` applies the
/// fallbacks; scheme-level style keys such as `candidate_format` are read by
/// `Theme` too.
public struct PresetColorScheme: Equatable, Sendable {
    public var id: String
    public var name: String?
    public var author: String?
    public var colorSpace: ColorSpace

    public var backColor: RGBAColor?
    public var hilitedBackColor: RGBAColor?
    public var hilitedCandidateBackColor: RGBAColor?
    public var preeditBackColor: RGBAColor?
    public var candidateBackColor: RGBAColor?
    public var borderColor: RGBAColor?
    public var textColor: RGBAColor?
    public var hilitedTextColor: RGBAColor?
    public var candidateTextColor: RGBAColor?
    public var hilitedCandidateTextColor: RGBAColor?
    public var labelColor: RGBAColor?
    public var hilitedCandidateLabelColor: RGBAColor?
    public var commentTextColor: RGBAColor?
    public var hilitedCommentTextColor: RGBAColor?
    public var accentTextColor: RGBAColor?
    public var warningTextColor: RGBAColor?

    /// Nil unless `preset_color_schemes/<id>` is a map.
    public init?(id: String, source: some ConfigSource) {
        let prefix = "preset_color_schemes/\(id)"
        guard source.mapKeys(at: prefix) != nil else { return nil }
        let colorSpace = ColorSpace(squirrel: source.string(at: "\(prefix)/color_space"))
        func color(_ key: String) -> RGBAColor? {
            source.parsed(at: "\(prefix)/\(key)") { RGBAColor(squirrel: $0, colorSpace: colorSpace) }
        }
        self.id = id
        self.colorSpace = colorSpace
        name = source.string(at: "\(prefix)/name")
        author = source.string(at: "\(prefix)/author")
        backColor = color("back_color")
        hilitedBackColor = color("hilited_back_color")
        hilitedCandidateBackColor = color("hilited_candidate_back_color")
        preeditBackColor = color("preedit_back_color")
        candidateBackColor = color("candidate_back_color")
        borderColor = color("border_color")
        textColor = color("text_color")
        hilitedTextColor = color("hilited_text_color")
        candidateTextColor = color("candidate_text_color")
        hilitedCandidateTextColor = color("hilited_candidate_text_color")
        labelColor = color("label_color")
        hilitedCandidateLabelColor = color("hilited_candidate_label_color")
        commentTextColor = color("comment_text_color")
        hilitedCommentTextColor = color("hilited_comment_text_color")
        accentTextColor = color("accent_text_color")
        warningTextColor = color("warning_text_color")
    }

    /// The IDs under `preset_color_schemes` whose value is a map, in librime's
    /// key order.
    public static func ids(in source: some ConfigSource) -> [String] {
        (source.mapKeys(at: "preset_color_schemes") ?? []).filter { id in
            source.mapKeys(at: "preset_color_schemes/\(id)") != nil
        }
    }
}
