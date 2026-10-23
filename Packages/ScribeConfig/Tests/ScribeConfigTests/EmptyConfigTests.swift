import ScribeConfig
import Testing

@Suite("Empty config")
struct EmptyConfigTests {
    @Test(arguments: [ConfigNode.map([:]), .null, .scalar("x"), .list([])])
    func defaults(config: ConfigNode) {
        let theme = Theme(source: config, colorSchemeKey: "style/color_scheme")
        #expect(theme == Theme())
        #expect(theme.colorSchemeID == nil)
        #expect(theme.isNative)
        #expect(theme.colorSpace == .sRGB)
        #expect(theme.colors == .native)
        #expect(theme.layout == .stacked)
        #expect(theme.orientation == .horizontal)
        #expect(!theme.inlinePreedit)
        #expect(!theme.inlineCandidate)
        #expect(!theme.translucency)
        #expect(!theme.mutualExclusive)
        #expect(theme.memorizeSize)
        #expect(!theme.showPaging)
        #expect(theme.statusMessageType == .mix)
        #expect(theme.candidateFormat == .default)
        #expect(theme.alpha == 1)
        let lengths = [
            theme.cornerRadius, theme.hilitedCornerRadius, theme.surroundingExtraExpansion, theme.shadowSize,
            theme.borderWidth, theme.borderHeight, theme.lineSpacing, theme.spacing, theme.baseOffset,
        ]
        #expect(lengths.allSatisfy { $0 == 0 })
        for font in [theme.candidateFont, theme.labelFont, theme.commentFont, theme.preeditFont] {
            #expect(font.faces.isEmpty)
            #expect(font.pointSize == nil)
        }

        let settings = ScribeSettings(squirrel: config)
        #expect(settings.configVersion == nil)
        #expect(settings.keyboardLayout == .last)
        #expect(settings.chordDuration == 0.1)
        #expect(settings.notificationPolicy == .appropriate)
        #expect(settings.showsStatusIcon)
        #expect(!settings.reportsBundleID)
        #expect(settings.appOptions.byBundleID.isEmpty)
        #expect(settings.appearance == Appearance(light: Theme(), dark: nil))
    }

    @Test func nativeDefaultSnapshot() {
        #expect(snapshot(Theme()) == """
            alpha = 1.0
            baseOffset = 0.0
            borderHeight = 0.0
            borderWidth = 0.0
            candidateFont.faces = []
            candidateFont.pointSize = nil
            candidateFormat = "[label]. [candidate] [comment]"
            colorSchemeID = nil
            colorSpace = sRGB
            colors.accentText = nil
            colors.background = windowBackground
            colors.border = nil
            colors.candidateBackground = nil
            colors.candidateText = label
            colors.commentText = secondaryLabel
            colors.hilitedCandidateBackground = selectedTextBackground
            colors.hilitedCandidateLabel = secondaryLabel
            colors.hilitedCandidateText = label
            colors.hilitedCommentText = secondaryLabel
            colors.hilitedPreeditBackground = nil
            colors.hilitedText = label
            colors.label = secondaryLabel
            colors.preeditBackground = nil
            colors.text = secondaryLabel
            colors.warningText = nil
            commentFont.faces = []
            commentFont.pointSize = nil
            cornerRadius = 0.0
            hilitedCornerRadius = 0.0
            inlineCandidate = false
            inlinePreedit = false
            isNative = true
            labelFont.faces = []
            labelFont.pointSize = nil
            layout = stacked
            lineSpacing = 0.0
            memorizeSize = true
            mutualExclusive = false
            orientation = horizontal
            preeditFont.faces = []
            preeditFont.pointSize = nil
            shadowSize = 0.0
            showPaging = false
            spacing = 0.0
            statusMessageType = mix
            surroundingExtraExpansion = 0.0
            translucency = false

            """)
    }
}
