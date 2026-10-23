import ScribeConfig

/// A theme as sorted "key = value" lines, for comparing whole themes.
/// Colours are "#RRGGBBAA" (with " displayP3" when tagged so), system colour
/// names or blend(foreground, background); strings are quoted with invisible
/// characters escaped.
func snapshot(_ theme: Theme) -> String {
    var lines: [String] = []
    func add(_ key: String, _ value: String) {
        lines.append("\(key) = \(value)")
    }
    add("colorSchemeID", theme.colorSchemeID.map(quoted) ?? "nil")
    add("isNative", "\(theme.isNative)")
    add("colorSpace", theme.colorSpace.rawValue)
    add("layout", theme.layout.rawValue)
    add("orientation", theme.orientation.rawValue)
    add("inlinePreedit", "\(theme.inlinePreedit)")
    add("inlineCandidate", "\(theme.inlineCandidate)")
    add("translucency", "\(theme.translucency)")
    add("mutualExclusive", "\(theme.mutualExclusive)")
    add("memorizeSize", "\(theme.memorizeSize)")
    add("showPaging", "\(theme.showPaging)")
    add("statusMessageType", theme.statusMessageType.rawValue)
    add("candidateFormat", quoted(theme.candidateFormat.template))
    add("alpha", "\(theme.alpha)")
    add("cornerRadius", "\(theme.cornerRadius)")
    add("hilitedCornerRadius", "\(theme.hilitedCornerRadius)")
    add("surroundingExtraExpansion", "\(theme.surroundingExtraExpansion)")
    add("shadowSize", "\(theme.shadowSize)")
    add("borderWidth", "\(theme.borderWidth)")
    add("borderHeight", "\(theme.borderHeight)")
    add("lineSpacing", "\(theme.lineSpacing)")
    add("spacing", "\(theme.spacing)")
    add("baseOffset", "\(theme.baseOffset)")

    let fonts = [
        ("candidateFont", theme.candidateFont),
        ("labelFont", theme.labelFont),
        ("commentFont", theme.commentFont),
        ("preeditFont", theme.preeditFont),
    ]
    for (key, font) in fonts {
        add("\(key).faces", "[" + font.faces.map(describe).joined(separator: ", ") + "]")
        add("\(key).pointSize", font.pointSize.map { "\($0)" } ?? "nil")
    }

    let colors = theme.colors
    let colorFields: [(String, ThemeColor?)] = [
        ("background", colors.background),
        ("hilitedPreeditBackground", colors.hilitedPreeditBackground),
        ("hilitedCandidateBackground", colors.hilitedCandidateBackground),
        ("preeditBackground", colors.preeditBackground),
        ("candidateBackground", colors.candidateBackground),
        ("border", colors.border),
        ("text", colors.text),
        ("hilitedText", colors.hilitedText),
        ("candidateText", colors.candidateText),
        ("hilitedCandidateText", colors.hilitedCandidateText),
        ("label", colors.label),
        ("hilitedCandidateLabel", colors.hilitedCandidateLabel),
        ("commentText", colors.commentText),
        ("hilitedCommentText", colors.hilitedCommentText),
        ("accentText", colors.accentText),
        ("warningText", colors.warningText),
    ]
    for (key, color) in colorFields {
        add("colors.\(key)", color.map(describe) ?? "nil")
    }
    return lines.sorted().joined(separator: "\n") + "\n"
}

func describe(_ color: ThemeColor) -> String {
    switch color {
    case .rgba(let rgba):
        describe(rgba)
    case .system(let system):
        system.rawValue
    case .blend(let foreground, let background):
        "blend(\(describe(foreground)), \(describe(background)))"
    }
}

func describe(_ color: RGBAColor) -> String {
    color.colorSpace == .sRGB ? color.hex : "\(color.hex) displayP3"
}

func describe(_ face: FontFace) -> String {
    guard let family = face.family, let style = face.style else { return quoted(face.name) }
    return "\(quoted(face.name)) (\(quoted(family)) \(quoted(style)))"
}

/// Double-quoted, with quotes, backslashes and invisible characters escaped.
func quoted(_ string: String) -> String {
    var result = "\""
    for scalar in string.unicodeScalars {
        switch scalar {
        case "\"", "\\":
            result += "\\" + String(scalar)
        case " ":
            result += " "
        case _ where scalar.properties.isWhitespace || scalar.properties.generalCategory == .control
            || scalar.properties.generalCategory == .format:
            result += "\\u{" + String(scalar.value, radix: 16, uppercase: true) + "}"
        default:
            result.unicodeScalars.append(scalar)
        }
    }
    return result + "\""
}
