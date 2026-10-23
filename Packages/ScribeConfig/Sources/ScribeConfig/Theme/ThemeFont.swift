import Foundation

/// One entry of a Squirrel font list such as "PingFangSC-Regular,HanaMinB".
///
/// The renderer resolves a list like Squirrel's decodeFonts: for each face,
/// try the font with `family` and `style` when both are present, then the font
/// named `name`. A family or name that an earlier face supplied is not used
/// again (a face whose family was used is skipped outright). The first font
/// found is the primary font and the rest form its cascade list. If a list
/// yields no font, the label, comment and preedit fonts use the candidate
/// font, and the candidate font uses `NSFont.userFont(ofSize:)`.
public struct FontFace: Equatable, Sendable {
    /// The entry trimmed of spaces and tabs, used as a PostScript or full name.
    public var name: String
    /// The part before the last "-" without leading whitespace, when the entry
    /// has a "-" followed by a style.
    public var family: String?
    /// The part after the last "-", trailing whitespace included.
    public var style: String?

    public init(name: String, family: String? = nil, style: String? = nil) {
        self.name = name
        self.family = family
        self.style = style
    }

    /// The faces of a Squirrel font list: comma-separated, empty entries
    /// dropped. Nil gives no faces.
    public static func list(squirrel value: String?) -> [FontFace] {
        guard let value else { return [] }
        return value.split(separator: ",").map { entry in
            let match = entry.firstMatch(of: /^\s*(.+)-([^-]+)\s*$/)
            return FontFace(
                name: entry.trimmingCharacters(in: .whitespaces),
                family: match.map { String($0.output.1) },
                style: match.map { String($0.output.2) }
            )
        }
    }
}

/// A font setting: a list of faces and a size.
public struct ThemeFont: Equatable, Sendable {
    public var faces: [FontFace]
    /// Nil means `NSFont.systemFontSize`.
    public var pointSize: Double?

    public init(faces: [FontFace] = [], pointSize: Double? = nil) {
        self.faces = faces
        self.pointSize = pointSize
    }
}
