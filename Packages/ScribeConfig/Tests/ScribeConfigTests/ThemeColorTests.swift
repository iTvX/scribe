import ScribeConfig
import Testing

/// The colours of a scheme "custom" with the given keys.
private func colors(_ scheme: [String: ConfigNode]) -> ThemeColors {
    let config: ConfigNode = [
        "style": ["color_scheme": "custom"],
        "preset_color_schemes": ["custom": .map(scheme)],
    ]
    return Theme(source: config, colorSchemeKey: "style/color_scheme").colors
}

private func rgba(_ literal: String, _ colorSpace: ColorSpace = .sRGB) -> ThemeColor {
    .rgba(RGBAColor(squirrel: literal, colorSpace: colorSpace)!)
}

@Suite("Theme colours")
struct ThemeColorTests {
    static let missingEverything = ThemeColors(
        background: .system(.windowBackground),
        hilitedPreeditBackground: nil,
        hilitedCandidateBackground: nil,
        preeditBackground: nil,
        candidateBackground: nil,
        border: nil,
        text: .system(.secondaryLabel),
        hilitedText: .system(.secondaryLabel),
        candidateText: .system(.secondaryLabel),
        hilitedCandidateText: .system(.secondaryLabel),
        label: .blend(foreground: .system(.secondaryLabel), background: .system(.windowBackground)),
        hilitedCandidateLabel: .blend(foreground: .system(.secondaryLabel), background: .system(.gray)),
        commentText: .system(.secondaryLabel),
        hilitedCommentText: .system(.secondaryLabel),
        accentText: nil,
        warningText: nil
    )

    @Test func schemeWithoutColors() {
        #expect(colors(["name": "Empty"]) == Self.missingEverything)
    }

    @Test func unknownSchemeUsesTheSameTable() {
        let theme = Theme(source: ConfigNode.map(["style": ["color_scheme": "missing"]]), colorSchemeKey: "style/color_scheme")
        #expect(!theme.isNative)
        #expect(theme.colorSchemeID == "missing")
        #expect(theme.colors == Self.missingEverything)
    }

    @Test func everyKeySet() {
        let keys = [
            "back_color", "hilited_back_color", "hilited_candidate_back_color", "preedit_back_color",
            "candidate_back_color", "border_color", "text_color", "hilited_text_color", "candidate_text_color",
            "hilited_candidate_text_color", "label_color", "hilited_candidate_label_color", "comment_text_color",
            "hilited_comment_text_color", "accent_text_color", "warning_text_color",
        ]
        var scheme: [String: ConfigNode] = [:]
        for (index, key) in keys.enumerated() {
            scheme[key] = .scalar("0x0000\(index + 10)")
        }
        let c = colors(scheme)
        let expected: [ThemeColor?] = [
            c.background, c.hilitedPreeditBackground, c.hilitedCandidateBackground, c.preeditBackground,
            c.candidateBackground, c.border, c.text, c.hilitedText, c.candidateText,
            c.hilitedCandidateText, c.label, c.hilitedCandidateLabel, c.commentText,
            c.hilitedCommentText, c.accentText, c.warningText,
        ]
        #expect(expected == keys.indices.map { rgba("0x0000\($0 + 10)") })
    }

    @Test func hilitedCandidateBackgroundFallsBackToHilitedBackground() {
        let c = colors(["hilited_back_color": "0x112233"])
        #expect(c.hilitedPreeditBackground == rgba("0x112233"))
        #expect(c.hilitedCandidateBackground == rgba("0x112233"))
        #expect(c.hilitedCandidateLabel == .blend(foreground: .system(.secondaryLabel), background: rgba("0x112233")))
        #expect(colors(["hilited_back_color": "0x112233", "hilited_candidate_back_color": "0x445566"]).hilitedCandidateBackground == rgba("0x445566"))
    }

    @Test func textColorFeedsTheOtherTextColors() {
        let text = rgba("0x606060")
        let c = colors(["text_color": "0x606060"])
        #expect(c.text == text)
        #expect(c.hilitedText == text)
        #expect(c.candidateText == text)
        #expect(c.hilitedCandidateText == text)
        #expect(c.commentText == text)
        #expect(c.hilitedCommentText == text)
        #expect(c.label == .blend(foreground: text, background: .system(.windowBackground)))
        #expect(c.hilitedCandidateLabel == .blend(foreground: text, background: .system(.gray)))
    }

    @Test func hilitedTextFeedsHilitedCandidateText() {
        let c = colors(["text_color": "0x606060", "hilited_text_color": "0x000000"])
        #expect(c.hilitedText == rgba("0x000000"))
        #expect(c.candidateText == rgba("0x606060"))
        #expect(c.hilitedCandidateText == rgba("0x000000"))
        #expect(c.hilitedCommentText == rgba("0x000000"))
    }

    @Test func candidateTextFeedsCommentAndLabel() {
        let c = colors(["back_color": "0xeeeeee", "candidate_text_color": "0x101010"])
        #expect(c.commentText == rgba("0x101010"))
        #expect(c.label == .blend(foreground: rgba("0x101010"), background: rgba("0xeeeeee")))
        #expect(c.hilitedCandidateText == .system(.secondaryLabel))
    }

    @Test func hilitedCandidateTextFeedsHilitedCommentAndLabel() {
        let c = colors(["hilited_candidate_text_color": "0xffffff", "hilited_candidate_back_color": "0x75B100"])
        #expect(c.hilitedCommentText == rgba("0xffffff"))
        #expect(c.hilitedCandidateLabel == .blend(foreground: rgba("0xffffff"), background: rgba("0x75B100")))
        #expect(c.hilitedPreeditBackground == nil)
    }

    @Test func invalidColorsCountAsMissing() {
        let c = colors(["back_color": "#FFFFFF", "text_color": "0X606060", "accent_text_color": "red"])
        #expect(c == Self.missingEverything)
    }

    @Test func displayP3() {
        let theme = Theme(
            source: ConfigNode.map([
                "style": ["color_scheme": "p3"],
                "preset_color_schemes": ["p3": ["color_space": "display_p3", "back_color": "0x000000"]],
            ]),
            colorSchemeKey: "style/color_scheme"
        )
        #expect(theme.colorSpace == .displayP3)
        #expect(theme.colors.background == rgba("0x000000", .displayP3))
        #expect(colors(["color_space": "Display_P3", "back_color": "0x000000"]).background == rgba("0x000000"))
    }

    @Test func nativePalette() {
        let absent = Theme(source: ConfigNode.map([:]), colorSchemeKey: "style/color_scheme")
        let native = Theme(source: ConfigNode.map(["style": ["color_scheme": "native"]]), colorSchemeKey: "style/color_scheme")
        for theme in [absent, native] {
            #expect(theme.colors == .native)
            #expect(theme.isNative)
            #expect(theme.colorSpace == .sRGB)
        }
        #expect(absent.colorSchemeID == nil)
        #expect(native.colorSchemeID == "native")
        let palette = ThemeColors.native
        #expect(palette.background == .system(.windowBackground))
        #expect(palette.hilitedPreeditBackground == nil)
        #expect(palette.hilitedCandidateBackground == .system(.selectedTextBackground))
        #expect(palette.preeditBackground == nil && palette.candidateBackground == nil && palette.border == nil)
        #expect(palette.text == .system(.secondaryLabel))
        #expect([palette.hilitedText, palette.candidateText, palette.hilitedCandidateText].allSatisfy { $0 == .system(.label) })
        #expect([palette.label, palette.hilitedCandidateLabel, palette.commentText, palette.hilitedCommentText].allSatisfy {
            $0 == .system(.secondaryLabel)
        })
        #expect(palette.accentText == nil && palette.warningText == nil)
    }
}
