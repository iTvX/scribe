import AppKit
import ScribeConfig

/// A theme resolved for drawing: AppKit colours and fonts, the text
/// attributes built from them, and the values Squirrel derives from the
/// style settings.
struct PanelTheme {
    var linear: Bool
    var vertical: Bool
    var inlinePreedit: Bool
    var inlineCandidate: Bool
    var translucency: Bool
    var mutualExclusive: Bool
    var memorizeSize: Bool
    var showPaging: Bool
    var statusMessageType: StatusMessageType
    var candidateFormat: String

    var alpha: CGFloat
    var cornerRadius: CGFloat
    var hilitedCornerRadius: CGFloat
    var surroundingExtraExpansion: CGFloat
    var shadowSize: CGFloat
    var borderWidth: CGFloat
    var borderHeight: CGFloat
    /// `line_spacing`: between candidates.
    var lineSpacing: CGFloat
    /// `spacing`: between the preedit and the candidates.
    var spacing: CGFloat
    var baseOffset: CGFloat

    var backgroundColor: NSColor
    var textColor: NSColor
    var highlightedTextColor: NSColor
    var candidateTextColor: NSColor
    var highlightedCandidateTextColor: NSColor
    var candidateLabelColor: NSColor
    var highlightedCandidateLabelColor: NSColor
    var commentTextColor: NSColor
    var highlightedCommentTextColor: NSColor
    var borderColor: NSColor?
    var preeditBackgroundColor: NSColor?
    var candidateBackColor: NSColor?
    var highlightedPreeditColor: NSColor?
    var highlightedBackColor: NSColor?
    var accentCommentTextColor: NSColor?
    var warningCommentTextColor: NSColor?

    var font: NSFont
    var labelFont: NSFont
    var commentFont: NSFont
    var preeditFont: NSFont
    /// The label size as configured, which sizes the paging arrows.
    var labelPointSize: CGFloat

    init(_ theme: Theme, palette: SystemPalette) {
        linear = theme.layout == .linear
        vertical = theme.orientation == .vertical
        inlinePreedit = theme.inlinePreedit
        inlineCandidate = theme.inlineCandidate
        translucency = theme.translucency
        mutualExclusive = theme.mutualExclusive
        memorizeSize = theme.memorizeSize
        showPaging = theme.showPaging
        statusMessageType = theme.statusMessageType
        candidateFormat = theme.candidateFormat.template

        alpha = theme.alpha
        cornerRadius = theme.cornerRadius
        hilitedCornerRadius = theme.hilitedCornerRadius
        surroundingExtraExpansion = theme.surroundingExtraExpansion
        shadowSize = theme.shadowSize
        borderWidth = theme.borderWidth
        borderHeight = theme.borderHeight
        lineSpacing = theme.lineSpacing
        spacing = theme.spacing
        baseOffset = theme.baseOffset

        func resolve(_ color: ThemeColor) -> NSColor {
            Self.color(color, palette: palette)
        }
        let colors = theme.colors
        backgroundColor = resolve(colors.background)
        textColor = resolve(colors.text)
        highlightedTextColor = resolve(colors.hilitedText)
        candidateTextColor = resolve(colors.candidateText)
        highlightedCandidateTextColor = resolve(colors.hilitedCandidateText)
        candidateLabelColor = resolve(colors.label)
        highlightedCandidateLabelColor = resolve(colors.hilitedCandidateLabel)
        commentTextColor = resolve(colors.commentText)
        highlightedCommentTextColor = resolve(colors.hilitedCommentText)
        borderColor = colors.border.map(resolve)
        preeditBackgroundColor = colors.preeditBackground.map(resolve)
        candidateBackColor = colors.candidateBackground.map(resolve)
        highlightedPreeditColor = colors.hilitedPreeditBackground.map(resolve)
        highlightedBackColor = colors.hilitedCandidateBackground.map(resolve)
        accentCommentTextColor = colors.accentText.map(resolve)
        warningCommentTextColor = colors.warningText.map(resolve)

        let font = Self.font(theme.candidateFont) ?? Self.defaultFont(size: theme.candidateFont.pointSize)
        func derived(_ themeFont: ThemeFont) -> NSFont {
            Self.font(themeFont) ?? themeFont.pointSize.map { font.withSize($0) } ?? font
        }
        self.font = font
        labelFont = derived(theme.labelFont)
        commentFont = derived(theme.commentFont)
        preeditFont = derived(theme.preeditFont)
        labelPointSize = theme.labelFont.pointSize ?? NSFont.systemFontSize
    }

    /// Space between the panel edge and the text; width and height swap
    /// places in vertical mode.
    var edgeInset: NSSize {
        if vertical {
            NSSize(width: borderHeight + cornerRadius, height: borderWidth + cornerRadius)
        } else {
            NSSize(width: borderWidth + cornerRadius, height: borderHeight + cornerRadius)
        }
    }

    var borderLineWidth: CGFloat {
        min(borderHeight, borderWidth)
    }

    /// Width of the strip left of the panel that holds the paging arrows.
    var pagingOffset: CGFloat {
        showPaging ? labelPointSize * 1.5 : 0
    }

    var metrics: PanelMetrics {
        PanelMetrics(
            edgeInset: edgeInset,
            lineSpacing: lineSpacing,
            spacing: spacing,
            cornerRadius: cornerRadius,
            hilitedCornerRadius: hilitedCornerRadius,
            borderWidth: borderWidth,
            borderLineWidth: borderLineWidth,
            surroundingExtraExpansion: surroundingExtraExpansion,
            pagingOffset: pagingOffset,
            linear: linear,
            mutualExclusive: mutualExclusive,
            showPaging: showPaging,
            drawsPreeditBackground: preeditBackgroundColor != nil,
            drawsCandidateBackground: candidateBackColor != nil,
            drawsHighlightedCandidate: highlightedBackColor != nil,
            drawsHighlightedPreedit: highlightedPreeditColor != nil
        )
    }

    // MARK: Text attributes

    var candidateAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: candidateTextColor, .font: font, .baselineOffset: baseOffset]
    }

    var highlightedCandidateAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: highlightedCandidateTextColor, .font: font, .baselineOffset: baseOffset]
    }

    var labelAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: candidateLabelColor, .font: labelFont, .baselineOffset: baseOffset + baselineShift(for: labelFont)]
    }

    var highlightedLabelAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: highlightedCandidateLabelColor, .font: labelFont, .baselineOffset: baseOffset + baselineShift(for: labelFont)]
    }

    var commentAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: commentTextColor, .font: commentFont, .baselineOffset: baseOffset + baselineShift(for: commentFont)]
    }

    var highlightedCommentAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: highlightedCommentTextColor, .font: commentFont, .baselineOffset: baseOffset + baselineShift(for: commentFont)]
    }

    var preeditAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: textColor, .font: preeditFont, .baselineOffset: baseOffset]
    }

    var highlightedPreeditAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: highlightedTextColor, .font: preeditFont, .baselineOffset: baseOffset]
    }

    /// Smaller label and comment fonts sit higher in horizontal text so they
    /// look centred on the candidate.
    private func baselineShift(for smallerFont: NSFont) -> CGFloat {
        vertical ? 0 : (font.pointSize - smallerFont.pointSize) / 2.5
    }

    // MARK: Paragraph styles

    var firstParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = lineSpacing / 2
        style.paragraphSpacingBefore = spacing / 2 + hilitedCornerRadius / 2
        return style
    }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = lineSpacing / 2
        style.paragraphSpacingBefore = lineSpacing / 2
        return style
    }

    var preeditParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = spacing / 2 + hilitedCornerRadius / 2
        style.lineSpacing = lineSpacing
        return style
    }

    // MARK: Resolving

    static func color(_ color: ThemeColor, palette: SystemPalette) -> NSColor {
        switch color {
        case let .rgba(rgba):
            let (red, green, blue, alpha) = (CGFloat(rgba.red) / 255, CGFloat(rgba.green) / 255, CGFloat(rgba.blue) / 255, CGFloat(rgba.alpha) / 255)
            return switch rgba.colorSpace {
            case .sRGB: NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
            case .displayP3: NSColor(displayP3Red: red, green: green, blue: blue, alpha: alpha)
            }
        case let .system(systemColor):
            return palette.color(systemColor)
        case let .blend(foreground, background):
            return blend(Self.color(foreground, palette: palette), Self.color(background, palette: palette))
        }
    }

    /// Two parts `foreground` to one part `background`, per component.
    static func blend(_ foreground: NSColor, _ background: NSColor) -> NSColor {
        let foreground = foreground.usingColorSpace(.deviceRGB) ?? foreground
        let background = background.usingColorSpace(.deviceRGB) ?? background
        func mix(_ foreground: CGFloat, _ background: CGFloat) -> CGFloat {
            (foreground * 2 + background) / 3
        }
        return NSColor(
            deviceRed: mix(foreground.redComponent, background.redComponent),
            green: mix(foreground.greenComponent, background.greenComponent),
            blue: mix(foreground.blueComponent, background.blueComponent),
            alpha: mix(foreground.alphaComponent, background.alphaComponent)
        )
    }

    /// The first face that exists, with the others as its cascade list;
    /// nil when none exists.
    static func font(_ themeFont: ThemeFont) -> NSFont? {
        let fonts = installedFonts(themeFont.faces)
        guard let first = fonts.first else { return nil }
        let size = themeFont.pointSize.map { CGFloat($0) }
        if fonts.count == 1 {
            return size.map { first.withSize($0) } ?? first
        }
        let descriptor = first.fontDescriptor.addingAttributes([.cascadeList: fonts.dropFirst().map(\.fontDescriptor)])
        return NSFont(descriptor: descriptor, size: size ?? first.pointSize)
    }

    /// Squirrel's lookup: "Family-Face" by family and face, otherwise the
    /// whole entry by name, skipping families already found.
    private static func installedFonts(_ faces: [FontFace]) -> [NSFont] {
        var seen = Set<String>()
        var fonts: [NSFont] = []
        for face in faces {
            if let family = face.family, let style = face.style {
                if seen.contains(family) { continue }
                let descriptor = NSFontDescriptor(fontAttributes: [.family: family, .face: style])
                if let font = NSFont(descriptor: descriptor, size: NSFont.systemFontSize) {
                    fonts.append(font)
                    seen.insert(family)
                    continue
                }
            }
            if seen.contains(face.name) { continue }
            let descriptor = NSFontDescriptor(fontAttributes: [.name: face.name])
            if let font = NSFont(descriptor: descriptor, size: NSFont.systemFontSize) {
                fonts.append(font)
                seen.insert(face.name)
            }
        }
        return fonts
    }

    /// The user's default font, as Squirrel uses when no face is set.
    private static func defaultFont(size: Double?) -> NSFont {
        let font = NSFont.userFont(ofSize: NSFont.systemFontSize) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return size.map { font.withSize($0) } ?? font
    }
}

/// The theme values the panel's shapes depend on.
struct PanelMetrics: Equatable, Sendable {
    var edgeInset: CGSize
    var lineSpacing: CGFloat
    var spacing: CGFloat
    var cornerRadius: CGFloat
    var hilitedCornerRadius: CGFloat
    var borderWidth: CGFloat
    var borderLineWidth: CGFloat
    var surroundingExtraExpansion: CGFloat
    var pagingOffset: CGFloat
    var linear: Bool
    var mutualExclusive: Bool
    var showPaging: Bool
    var drawsPreeditBackground: Bool
    var drawsCandidateBackground: Bool
    var drawsHighlightedCandidate: Bool
    var drawsHighlightedPreedit: Bool
}
