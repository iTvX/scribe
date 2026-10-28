import AppKit
import CoreText

/// Reference input normalization for the macOS 27.2 font-cascade defect.
/// This does not use Scribe's renderer, geometry or font-resolution code.
@MainActor
func oracleVerticalFonts(_ text: NSAttributedString, vertical: Bool) -> NSAttributedString {
    guard #available(macOS 27.2, *), vertical else { return text }
    let result = NSMutableAttributedString(attributedString: text)
    let whole = text.string as NSString
    var index = 0
    while index < whole.length {
        let cluster = whole.rangeOfComposedCharacterSequence(at: index)
        if let font = text.attribute(.font, at: index, effectiveRange: nil) as? NSFont {
            let selected = CTFontCreateForString(font as CTFont, whole as CFString,
                                                 CFRange(location: cluster.location, length: cluster.length))
            let name = CTFontCopyPostScriptName(selected) as String
            if name != font.fontName, let concrete = NSFont(name: name, size: font.pointSize) {
                result.addAttribute(.font, value: concrete, range: cluster)
            }
        }
        index = NSMaxRange(cluster)
    }
    return result
}
