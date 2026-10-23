public enum CandidateListLayout: String, Sendable {
    case stacked, linear
}

public enum TextOrientation: String, Sendable {
    case horizontal, vertical
}

/// How a schema or option change is announced: `long` shows the full state
/// label, `short` its abbreviation, `mix` the abbreviation when there is one.
public enum StatusMessageType: String, Sendable {
    case long, short, mix
}

/// One candidate window theme (light or dark), read like SquirrelTheme.load.
/// Lengths are in points.
public struct Theme: Equatable, Sendable {
    /// The `color_scheme` value as written; nil when the key is absent.
    public var colorSchemeID: String?
    /// True without a colour scheme or with "native": system colours that
    /// follow the appearance.
    public var isNative: Bool
    public var colorSpace: ColorSpace
    public var colors: ThemeColors
    public var layout: CandidateListLayout
    public var orientation: TextOrientation
    public var inlinePreedit: Bool
    public var inlineCandidate: Bool
    public var translucency: Bool
    public var mutualExclusive: Bool
    /// Only `style` sets this; a colour scheme cannot.
    public var memorizeSize: Bool
    public var showPaging: Bool
    /// Only `style` sets this; a colour scheme cannot.
    public var statusMessageType: StatusMessageType
    public var candidateFormat: CandidateFormat
    /// 0...1.
    public var alpha: Double
    public var cornerRadius: Double
    public var hilitedCornerRadius: Double
    public var surroundingExtraExpansion: Double
    /// At least 0.
    public var shadowSize: Double
    public var borderWidth: Double
    public var borderHeight: Double
    /// `line_spacing`: between candidates.
    public var lineSpacing: Double
    /// `spacing`: between the preedit and the candidates.
    public var spacing: Double
    public var baseOffset: Double
    public var candidateFont: ThemeFont
    public var labelFont: ThemeFont
    public var commentFont: ThemeFont
    public var preeditFont: ThemeFont

    /// Squirrel's theme when nothing is configured.
    public init() {
        colorSchemeID = nil
        isNative = true
        colorSpace = .sRGB
        colors = .native
        layout = .stacked
        orientation = .horizontal
        inlinePreedit = false
        inlineCandidate = false
        translucency = false
        mutualExclusive = false
        memorizeSize = true
        showPaging = false
        statusMessageType = .mix
        candidateFormat = .default
        alpha = 1
        cornerRadius = 0
        hilitedCornerRadius = 0
        surroundingExtraExpansion = 0
        shadowSize = 0
        borderWidth = 0
        borderHeight = 0
        lineSpacing = 0
        spacing = 0
        baseOffset = 0
        candidateFont = ThemeFont()
        labelFont = ThemeFont()
        commentFont = ThemeFont()
        preeditFont = ThemeFont()
    }

    /// Reads `style/…`, then lets the colour scheme named at `colorSchemeKey`
    /// (such as "style/color_scheme") override it, as SquirrelTheme.load does.
    public init(source: some ConfigSource, colorSchemeKey: String) {
        self.init()
        var fonts = FontKeys()
        apply(source: source, prefix: "style", fonts: &fonts)
        if let memorizeSize = source.bool(at: "style/memorize_size") {
            self.memorizeSize = memorizeSize
        }
        if let type = source.string(at: "style/status_message_type").flatMap(StatusMessageType.init) {
            statusMessageType = type
        }

        colorSchemeID = source.string(at: colorSchemeKey)
        if let id = colorSchemeID, id != "native" {
            let prefix = "preset_color_schemes/\(id)"
            isNative = false
            colorSpace = ColorSpace(squirrel: source.string(at: "\(prefix)/color_space"))
            colors = ThemeColors(source: source, prefix: prefix, colorSpace: colorSpace)
            apply(source: source, prefix: prefix, fonts: &fonts)
        }

        candidateFont = ThemeFont(faces: FontFace.list(squirrel: fonts.face), pointSize: fonts.point)
        labelFont = ThemeFont(
            faces: FontFace.list(squirrel: fonts.labelFace ?? fonts.face),
            pointSize: fonts.labelPoint ?? fonts.point
        )
        commentFont = ThemeFont(
            faces: FontFace.list(squirrel: fonts.commentFace ?? fonts.face),
            pointSize: fonts.commentPoint ?? fonts.point
        )
        preeditFont = ThemeFont(
            faces: FontFace.list(squirrel: fonts.preeditFace ?? fonts.face),
            pointSize: fonts.preeditPoint ?? fonts.point
        )
    }

    /// The font keys as read so far; fonts are combined once both levels are read.
    private struct FontKeys {
        var face, labelFace, commentFace, preeditFace: String?
        var point, labelPoint, commentPoint, preeditPoint: Double?
    }

    /// Reads the keys that both `style` and a colour scheme may set, keeping
    /// the current value where a key is missing or does not convert.
    private mutating func apply(source: some ConfigSource, prefix: String, fonts: inout FontKeys) {
        func string(_ key: String) -> String? { source.string(at: "\(prefix)/\(key)") }
        func bool(_ key: String) -> Bool? { source.bool(at: "\(prefix)/\(key)") }
        func double(_ key: String) -> Double? { source.double(at: "\(prefix)/\(key)") }

        if let value = string("candidate_list_layout") {
            layout = value == "linear" ? .linear : .stacked
        }
        if let value = string("text_orientation") {
            orientation = value == "vertical" ? .vertical : .horizontal
        }
        inlinePreedit = bool("inline_preedit") ?? inlinePreedit
        inlineCandidate = bool("inline_candidate") ?? inlineCandidate
        translucency = bool("translucency") ?? translucency
        mutualExclusive = bool("mutual_exclusive") ?? mutualExclusive
        showPaging = bool("show_paging") ?? showPaging
        candidateFormat = string("candidate_format").map(CandidateFormat.init) ?? candidateFormat

        // Squirrel clamps in a different order at each level, which only
        // matters for NaN: 0 from style, 1 from a colour scheme.
        alpha = double("alpha").map { prefix == "style" ? min(1, max(0, $0)) : max(0, min(1, $0)) } ?? alpha
        cornerRadius = double("corner_radius") ?? cornerRadius
        hilitedCornerRadius = double("hilited_corner_radius") ?? hilitedCornerRadius
        surroundingExtraExpansion = double("surrounding_extra_expansion") ?? surroundingExtraExpansion
        borderHeight = double("border_height") ?? borderHeight
        borderWidth = double("border_width") ?? borderWidth
        lineSpacing = double("line_spacing") ?? lineSpacing
        spacing = double("spacing") ?? spacing
        baseOffset = double("base_offset") ?? baseOffset
        shadowSize = double("shadow_size").map { max(0, $0) } ?? shadowSize

        fonts.face = string("font_face") ?? fonts.face
        fonts.point = double("font_point") ?? fonts.point
        fonts.labelFace = string("label_font_face") ?? fonts.labelFace
        fonts.labelPoint = double("label_font_point") ?? fonts.labelPoint
        fonts.commentFace = string("comment_font_face") ?? fonts.commentFace
        fonts.commentPoint = double("comment_font_point") ?? fonts.commentPoint
        fonts.preeditFace = string("preedit_font_face") ?? fonts.preeditFace
        fonts.preeditPoint = double("preedit_font_point") ?? fonts.preeditPoint
    }
}
