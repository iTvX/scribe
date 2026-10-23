import AppKit
import ScribeConfig
@testable import ScribeUI
import Testing

@MainActor
@Suite struct PanelThemeTests {
    private func resolve(_ change: (inout Theme) -> Void) -> PanelTheme {
        var theme = Fixtures.squirrelDefaults
        change(&theme)
        return PanelTheme(theme, palette: Fixtures.lightPalette)
    }

    @Test func insetsSwapInVerticalMode() {
        let horizontal = resolve {
            $0.borderWidth = 4
            $0.borderHeight = 2
        }
        #expect(horizontal.edgeInset == NSSize(width: 11, height: 9))
        #expect(horizontal.borderLineWidth == 2)
        let vertical = resolve {
            $0.borderWidth = 4
            $0.borderHeight = 2
            $0.orientation = .vertical
        }
        #expect(vertical.edgeInset == NSSize(width: 9, height: 11))
    }

    @Test func pagingStripFollowsTheLabelSize() {
        #expect(resolve { _ in }.pagingOffset == 0)
        #expect(resolve { $0.showPaging = true }.pagingOffset == 24)
        #expect(resolve {
            $0.showPaging = true
            $0.labelFont.pointSize = 12
        }.pagingOffset == 18)
        #expect(resolve {
            $0.showPaging = true
            $0.labelFont.pointSize = nil
        }.pagingOffset == NSFont.systemFontSize * 1.5)
    }

    @Test func blendIsTwoPartsForeground() throws {
        let blended = PanelTheme.blend(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 0.4))
        let components = try #require(blended.usingColorSpace(.sRGB))
        #expect(abs(components.redComponent - 2.0 / 3) < 1e-6)
        #expect(abs(components.greenComponent) < 1e-6)
        #expect(abs(components.blueComponent - 1.0 / 3) < 1e-6)
        #expect(abs(components.alphaComponent - 0.8) < 1e-6)
    }

    @Test func coloursResolve() throws {
        let palette = Fixtures.darkPalette
        #expect(PanelTheme.color(.system(.label), palette: palette) == palette.label)
        let p3 = PanelTheme.color(.rgba(RGBAColor(red: 255, green: 0, blue: 0, colorSpace: .displayP3)), palette: palette)
        #expect(p3.colorSpace == .displayP3)
        let squirrel = try #require(PanelTheme.color(Fixtures.color("0x80fa3a0a"), palette: palette).usingColorSpace(.sRGB))
        #expect(Int((squirrel.redComponent * 255).rounded()) == 0x0a)
        #expect(Int((squirrel.greenComponent * 255).rounded()) == 0x3a)
        #expect(Int((squirrel.blueComponent * 255).rounded()) == 0xfa)
        #expect(Int((squirrel.alphaComponent * 255).rounded()) == 0x80)
    }

    @Test func smallerLabelsSitHigherInHorizontalText() {
        let theme = resolve {
            $0.labelFont.pointSize = 12
            $0.baseOffset = 3
        }
        #expect(theme.labelAttributes[.baselineOffset] as? CGFloat == 3 + (16 - 12) / 2.5)
        #expect(theme.candidateAttributes[.baselineOffset] as? CGFloat == 3)
        let vertical = resolve {
            $0.labelFont.pointSize = 12
            $0.baseOffset = 3
            $0.orientation = .vertical
        }
        #expect(vertical.labelAttributes[.baselineOffset] as? CGFloat == 3)
    }

    @Test func fontListsCascade() throws {
        let theme = resolve { _ in }
        #expect(theme.font.familyName == "Avenir")
        #expect(theme.font.pointSize == 16)
        let cascade = try #require(theme.font.fontDescriptor.object(forKey: .cascadeList) as? [NSFontDescriptor])
        #expect(cascade.compactMap(\.postscriptName).contains { $0.hasPrefix("PingFang") })
    }

    @Test func familyAndFaceEntries() {
        let theme = resolve {
            $0.candidateFont = Fixtures.font("Avenir-Heavy, Avenir-Book", 14)
        }
        #expect(theme.font.fontName == "Avenir-Heavy")
        #expect(theme.font.fontDescriptor.object(forKey: .cascadeList) == nil)
    }

    @Test func partsWithoutFacesUseTheCandidateFont() {
        let theme = resolve {
            $0.candidateFont = Fixtures.font("Helvetica", 18)
            $0.labelFont = ThemeFont(faces: [FontFace(name: "No Such Font Anywhere")], pointSize: 12)
            $0.commentFont = Fixtures.font("Menlo", 11)
            $0.preeditFont = ThemeFont(faces: [], pointSize: nil)
        }
        #expect(theme.labelFont.familyName == "Helvetica")
        #expect(theme.labelFont.pointSize == 12)
        #expect(theme.commentFont.familyName == "Menlo")
        #expect(theme.preeditFont == theme.font)
    }

    @Test func noFaceUsesTheUserFont() {
        let theme = resolve {
            $0.candidateFont = ThemeFont(faces: [], pointSize: 20)
        }
        #expect(theme.font.familyName == NSFont.userFont(ofSize: 20)?.familyName)
        #expect(theme.font.pointSize == 20)
    }

    @Test func paragraphSpacingComesFromTheStyle() {
        let theme = resolve {
            $0.lineSpacing = 6
            $0.spacing = 10
            $0.hilitedCornerRadius = 4
        }
        #expect(theme.firstParagraphStyle.paragraphSpacing == 3)
        #expect(theme.firstParagraphStyle.paragraphSpacingBefore == 7)
        #expect(theme.paragraphStyle.paragraphSpacingBefore == 3)
        #expect(theme.preeditParagraphStyle.paragraphSpacing == 7)
        #expect(theme.preeditParagraphStyle.lineSpacing == 6)
    }

    @Test func nativeColoursComeFromThePalette() {
        let light = PanelTheme(Theme(), palette: Fixtures.lightPalette)
        #expect(light.backgroundColor == Fixtures.lightPalette.windowBackground)
        #expect(light.highlightedBackColor == Fixtures.lightPalette.selectedTextBackground)
        #expect(light.highlightedPreeditColor == nil)
        #expect(light.candidateLabelColor == Fixtures.lightPalette.secondaryLabel)
    }
}
