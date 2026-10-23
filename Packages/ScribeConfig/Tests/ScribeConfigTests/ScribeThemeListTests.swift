import ScribeConfig
import Testing

@Suite("Theme list and diagnostics")
struct ScribeThemeListTests {
    let squirrel = configTree([
        ("preset_color_schemes/native/name", "系統配色"),
        ("preset_color_schemes/aqua/name", "碧水／Aqua"),
        ("preset_color_schemes/aqua/author", "佛振"),
        ("preset_color_schemes/luna/name", "明月／Luna"),
        ("preset_color_schemes/broken", "not a map"),
    ])
    let scribe = configTree([
        ("themes/wechat/name", "微信键盘"),
        ("themes/wechat/light/background", "#FFFFFF"),
        ("themes/wechat/dark/background", "#000000"),
        ("themes/aqua/name", "Scribe Aqua"),
        ("themes/aqua/light/background", "#FFFFFF"),
        ("themes/native/light/background", "#FFFFFF"),
        ("themes/bad:id/light/background", "#FFFFFF"),
    ])

    @Test func availableThemesInOrder() {
        #expect(availableThemes(scribe: scribe, squirrel: squirrel) == [
            ThemeInfo(id: "native", name: "系統配色", author: nil, hasDark: true, origin: .native),
            ThemeInfo(id: "aqua", name: "Scribe Aqua", author: nil, hasDark: false, origin: .scribe),
            ThemeInfo(id: "wechat", name: "微信键盘", author: nil, hasDark: true, origin: .scribe),
            ThemeInfo(id: "luna", name: "明月／Luna", author: nil, hasDark: false, origin: .squirrel),
        ])
    }

    @Test func darkPresetsAreNeverListed() {
        let merged = MergedConfigSource(squirrel: squirrel, scribe: scribe)
        #expect(PresetColorScheme.ids(in: merged).contains("wechat:dark"))
        let ids = availableThemes(scribe: scribe, squirrel: merged).map(\.id)
        #expect(ids == ["native", "aqua", "wechat", "luna"])
    }

    @Test func withoutScribeThemes() {
        let themes = availableThemes(scribe: ConfigNode.null, squirrel: squirrel)
        #expect(themes.map(\.id) == ["native", "aqua", "luna"])
        #expect(themes[1] == ThemeInfo(id: "aqua", name: "碧水／Aqua", author: "佛振", hasDark: false, origin: .squirrel))
    }

    @Test(arguments: [
        ("wechat", true), ("a_1", true), ("x", true), ("2026", true),
        ("native", false), ("", false), ("WeChat", false), ("we-chat", false), ("微信", false),
        ("a:b", false), ("a/b", false), ("@x", false), ("a b", false),
    ])
    func themeIDsForSettings(id: String, valid: Bool) {
        #expect(ThemeID.isValidForSettings(id) == valid)
    }

    @Test func diagnostics() {
        let scribe = configTree([
            ("appearance/theme", "wechat"),
            ("appearance/dark_theme", "missing"),
            ("themes/wechat/light/background", nil),
            ("themes/wechat/light/border", ["not": "a colour"]),
            ("themes/wechat/light/preedit_text", "#FFF"),
            ("themes/wechat/light/highlight_background", "#00B175"),
            ("themes/wechat/light/not_a_colour_key", "whatever"),
            ("themes/wechat/dark/comment", "0x808080"),
            ("themes/bad:id/light/background", "#FFFFFF"),
            ("themes/@x/light/background", "#FFFFFF"),
        ])
        #expect(ConfigDiagnostics.check(scribe: scribe, squirrel: squirrel) == [
            ConfigDiagnostic(path: "themes/@x", problem: .invalidThemeID),
            ConfigDiagnostic(path: "themes/bad:id", problem: .invalidThemeID),
            ConfigDiagnostic(path: "themes/wechat/light/background", problem: .missingColor),
            ConfigDiagnostic(path: "themes/wechat/light/border", problem: .invalidColor(nil)),
            ConfigDiagnostic(path: "themes/wechat/light/preedit_text", problem: .invalidColor("#FFF")),
            ConfigDiagnostic(path: "themes/wechat/dark/comment", problem: .invalidColor("0x808080")),
            ConfigDiagnostic(path: "appearance/dark_theme", problem: .unknownTheme("missing")),
        ])
    }

    @Test(arguments: ["native", "aqua", "wechat"])
    func knownThemes(id: String) {
        let scribe = configTree([
            ("appearance/theme", .scalar(id)),
            ("appearance/dark_theme", .scalar(id)),
            ("themes/wechat/light/background", "#FFFFFF"),
        ])
        #expect(ConfigDiagnostics.check(scribe: scribe, squirrel: squirrel) == [])
    }
}

@Suite("Scribe value helpers")
struct ScribeValueTests {
    @Test(arguments: [
        ("#00B175", "#00B175FF"),
        ("#00b175", "#00B175FF"),
        ("#00B17580", "#00B17580"),
        ("#ffffffff", "#FFFFFFFF"),
    ])
    func scribeLiteral(literal: String, hex: String) {
        #expect(RGBAColor(scribe: literal, colorSpace: .sRGB)?.hex == hex)
    }

    @Test(arguments: ["", "#", "00B175", "#00B17", "#00B1755", "#00B175FF0", "0x75B100", " #00B175", "#00B175 ", "#GGGGGG", "##00B175"])
    func notScribeLiteral(literal: String) {
        #expect(RGBAColor(scribe: literal, colorSpace: .sRGB) == nil)
    }

    @Test(arguments: [
        RGBAColor(red: 0x00, green: 0xB1, blue: 0x75),
        RGBAColor(red: 0x12, green: 0x34, blue: 0x56, alpha: 0x78),
        RGBAColor(red: 0, green: 0, blue: 0, alpha: 0),
        RGBAColor(red: 0xFF, green: 0xFF, blue: 0xFF, alpha: 0xFE, colorSpace: .displayP3),
    ])
    func literalsRoundTrip(color: RGBAColor) {
        #expect(RGBAColor(squirrel: color.squirrelLiteral, colorSpace: color.colorSpace) == color)
        #expect(RGBAColor(scribe: color.scribeLiteral, colorSpace: color.colorSpace) == color)
    }

    @Test func literalForms() {
        let green = RGBAColor(red: 0x00, green: 0xB1, blue: 0x75)
        #expect(green.squirrelLiteral == "0xFF75B100")
        #expect(green.scribeLiteral == "#00B175")
        let translucent = RGBAColor(red: 0x00, green: 0xB1, blue: 0x75, alpha: 0x80)
        #expect(translucent.squirrelLiteral == "0x8075B100")
        #expect(translucent.scribeLiteral == "#00B17580")
    }

    @Test func fontStringRoundTrip() {
        let string = "PingFangSC-Regular,HanaMinB,Avenir"
        let faces = FontFace.list(squirrel: string)
        #expect(FontFace.squirrelString(faces) == string)
        #expect(FontFace.list(squirrel: FontFace.squirrelString(faces)) == faces)
        #expect(FontFace.squirrelString([]) == "")
    }

    @Test func caseIterable() {
        #expect(CandidateListLayout.allCases == [.stacked, .linear])
        #expect(TextOrientation.allCases == [.horizontal, .vertical])
        #expect(StatusMessageType.allCases == [.long, .short, .mix])
        #expect(NotificationPolicy.allCases == [.always, .appropriate, .never])
        #expect(ColorSpace.allCases == [.sRGB, .displayP3])
    }
}
