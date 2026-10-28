import AppKit
import CoreText
import ScribeConfig
@testable import ScribeUI
import Testing

@MainActor @Suite struct VerticalFontTests {
    @Test func resolvesChineseFallbackWithoutChangingTextOrOtherAttributes() throws {
        let font = try #require(PanelTheme.font(Fixtures.font("Avenir, PingFang SC", 16)))
        let text = NSAttributedString(string: "A中书e\u{301}👨‍👩‍👧‍👦", attributes: [.font: font, .foregroundColor: NSColor.red])
        let resolved = PanelTextLayout.resolvingFallbackFonts(in: text)
        #expect(resolved.string == text.string)
        let latin = try #require(resolved.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(latin.fontName == font.fontName)
        for index in [1, 2] {
            let actual = try #require(resolved.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
            #expect(actual.fontName.hasPrefix("PingFang"))
            #expect(actual.pointSize == font.pointSize)
            #expect(actual.fontDescriptor.object(forKey: .cascadeList) == nil)
        }
        let string = resolved.string as NSString
        let emoji = string.range(of: "👨‍👩‍👧‍👦")
        var fontRange = NSRange()
        _ = resolved.attribute(.font, at: emoji.location, effectiveRange: &fontRange)
        #expect(NSIntersectionRange(emoji, fontRange) == emoji)
        #expect(resolved.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor == .red)
    }
}
