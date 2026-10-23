import ScribeConfig
import Testing

@Suite("Max's sample")
struct MaxSampleTests {
    let appearance = ScribeSettings(squirrel: maxSample).appearance

    private static func color(_ hex: UInt32) -> ThemeColor {
        .rgba(RGBAColor(red: UInt8(hex >> 16), green: UInt8(hex >> 8 & 0xFF), blue: UInt8(hex & 0xFF)))
    }

    private static let pingFang = [FontFace(name: "PingFangSC-Regular", family: "PingFangSC", style: "Regular")]

    /// What both skins share.
    private func expectWeChatLayout(_ theme: Theme) {
        #expect(!theme.isNative)
        #expect(theme.colorSpace == .sRGB)
        #expect(theme.layout == .linear)
        #expect(theme.orientation == .horizontal)
        #expect(theme.inlinePreedit)
        #expect(!theme.inlineCandidate)
        #expect(!theme.translucency)
        #expect(!theme.mutualExclusive)
        #expect(theme.memorizeSize)
        #expect(!theme.showPaging)
        #expect(theme.statusMessageType == .mix)
        #expect(theme.candidateFormat.template == "[label] [candidate] [comment] ")
        #expect(theme.candidateFormat.segments == [.label, .text(" "), .candidate, .text(" "), .comment, .text(" ")])
        #expect(theme.alpha == 1)
        #expect(theme.cornerRadius == 5)
        #expect(theme.hilitedCornerRadius == 0)
        #expect(theme.surroundingExtraExpansion == 0)
        #expect(theme.shadowSize == 0)
        #expect(theme.borderWidth == 8)
        #expect(theme.borderHeight == 0)
        #expect(theme.lineSpacing == 5)
        #expect(theme.spacing == 8)
        #expect(theme.baseOffset == 0)
        #expect(theme.candidateFont == ThemeFont(faces: Self.pingFang, pointSize: 16))
        #expect(theme.labelFont == ThemeFont(faces: Self.pingFang, pointSize: 12))
        #expect(theme.commentFont == ThemeFont(faces: Self.pingFang, pointSize: 16))
        #expect(theme.preeditFont == ThemeFont(faces: Self.pingFang, pointSize: 16))
        #expect(theme.colors.hilitedCandidateBackground == .rgba(RGBAColor(red: 0x00, green: 0xB1, blue: 0x75)))
        if case .rgba(let green) = theme.colors.hilitedCandidateBackground {
            #expect(green.hex == "#00B175FF")
        } else {
            Issue.record("hilitedCandidateBackground is not an RGBA colour")
        }
    }

    @Test func lightTheme() {
        let light = appearance.light
        #expect(light.colorSchemeID == "wechat_light")
        expectWeChatLayout(light)
        let colors = light.colors
        let white = Self.color(0xFFFFFF), green = Self.color(0x00B175), text = Self.color(0x424242)
        #expect(colors.background == white)
        #expect(colors.hilitedPreeditBackground == nil)
        #expect(colors.preeditBackground == nil)
        #expect(colors.candidateBackground == nil)
        #expect(colors.border == nil)
        #expect(colors.text == text)
        #expect(colors.hilitedText == text)
        #expect(colors.candidateText == text)
        #expect(colors.hilitedCandidateText == white)
        #expect(colors.label == .blend(foreground: text, background: white))
        #expect(colors.hilitedCandidateLabel == .blend(foreground: white, background: green))
        #expect(colors.commentText == Self.color(0x999999))
        #expect(colors.hilitedCommentText == white)
        #expect(colors.accentText == nil)
        #expect(colors.warningText == nil)
    }

    @Test func darkTheme() throws {
        let dark = try #require(appearance.dark)
        #expect(dark.colorSchemeID == "wechat_dark")
        expectWeChatLayout(dark)
        let colors = dark.colors
        let white = Self.color(0xFFFFFF), green = Self.color(0x00B175)
        #expect(colors.background == Self.color(0x2D2D2D))
        #expect(colors.hilitedPreeditBackground == nil)
        #expect(colors.text == Self.color(0xBDBDBD))
        #expect(colors.hilitedText == Self.color(0xBDBDBD))
        #expect(colors.candidateText == Self.color(0xE0E0E0))
        #expect(colors.hilitedCandidateText == white)
        #expect(colors.label == Self.color(0x8C8C8C))
        #expect(colors.hilitedCandidateLabel == .blend(foreground: white, background: green))
        #expect(colors.commentText == Self.color(0x8C8C8C))
        #expect(colors.hilitedCommentText == white)
        #expect(!appearance.forcesLightAppearance)
    }

    @Test func darkThemeSnapshot() throws {
        let dark = try #require(appearance.dark)
        #expect(snapshot(dark) == """
            alpha = 1.0
            baseOffset = 0.0
            borderHeight = 0.0
            borderWidth = 8.0
            candidateFont.faces = ["PingFangSC-Regular" ("PingFangSC" "Regular")]
            candidateFont.pointSize = 16.0
            candidateFormat = "[label] [candidate] [comment] "
            colorSchemeID = "wechat_dark"
            colorSpace = sRGB
            colors.accentText = nil
            colors.background = #2D2D2DFF
            colors.border = nil
            colors.candidateBackground = nil
            colors.candidateText = #E0E0E0FF
            colors.commentText = #8C8C8CFF
            colors.hilitedCandidateBackground = #00B175FF
            colors.hilitedCandidateLabel = blend(#FFFFFFFF, #00B175FF)
            colors.hilitedCandidateText = #FFFFFFFF
            colors.hilitedCommentText = #FFFFFFFF
            colors.hilitedPreeditBackground = nil
            colors.hilitedText = #BDBDBDFF
            colors.label = #8C8C8CFF
            colors.preeditBackground = nil
            colors.text = #BDBDBDFF
            colors.warningText = nil
            commentFont.faces = ["PingFangSC-Regular" ("PingFangSC" "Regular")]
            commentFont.pointSize = 16.0
            cornerRadius = 5.0
            hilitedCornerRadius = 0.0
            inlineCandidate = false
            inlinePreedit = true
            isNative = false
            labelFont.faces = ["PingFangSC-Regular" ("PingFangSC" "Regular")]
            labelFont.pointSize = 12.0
            layout = linear
            lineSpacing = 5.0
            memorizeSize = true
            mutualExclusive = false
            orientation = horizontal
            preeditFont.faces = ["PingFangSC-Regular" ("PingFangSC" "Regular")]
            preeditFont.pointSize = 16.0
            shadowSize = 0.0
            showPaging = false
            spacing = 8.0
            statusMessageType = mix
            surroundingExtraExpansion = 0.0
            translucency = false

            """)
    }

    @Test func settings() {
        let settings = ScribeSettings(squirrel: maxSample)
        #expect(settings.configVersion == "1.0")
        #expect(settings.keyboardLayout == .last)
        #expect(settings.chordDuration == 0.1)
        #expect(settings.notificationPolicy == .appropriate)
        #expect(settings.showsStatusIcon)
        #expect(settings.appOptions.options(for: "com.googlecode.iterm2") == ["ascii_mode": false])
        #expect(settings.appOptions.options(for: "com.apple.Terminal") == [:])
        #expect(PresetColorScheme.ids(in: maxSample) == ["native", "wechat_dark", "wechat_light"])
    }
}
