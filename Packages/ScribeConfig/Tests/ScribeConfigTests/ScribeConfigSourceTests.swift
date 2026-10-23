import ScribeConfig
import Testing

@Suite("Scribe config as Squirrel")
struct ScribeConfigSourceTests {
    @Test func everyNonThemeKeyReadsItsScribePath() {
        let entries = ScribeKeyMap.entries.filter { entry in
            !entry.scribePath.hasPrefix("themes/") && !entry.scribePath.hasPrefix("appearance/theme")
                && !entry.scribePath.hasPrefix("appearance/dark_theme")
        }
        let values = entries.enumerated().map { index, entry in
            (ScribeKeyMapTests.instance(entry.scribePath), ConfigNode.scalar("value \(index)"))
        }
        let source = ScribeConfigSource(scribe: configTree(values))
        for (index, entry) in entries.enumerated() {
            #expect(source.string(at: ScribeKeyMapTests.instance(entry.squirrelPath)) == "value \(index)", "\(entry.scribePath)")
        }
    }

    @Test func everyThemeKeyReadsItsScribePath() {
        var values: [(String, ConfigNode)] = [
            ("themes/wechat/name", "微信键盘"),
            ("themes/wechat/author", "Max"),
            ("themes/wechat/color_space", "display_p3"),
        ]
        let styleEntries = ScribeKeyMap.entries.filter { $0.scribePath.hasPrefix("themes/{id}/style/") }
        for (index, entry) in styleEntries.enumerated() {
            values.append((ScribeKeyMapTests.instance(entry.scribePath), .scalar("style \(index)")))
        }
        let colorEntries = ScribeKeyMap.entries.filter { $0.kind == .color }
        for (index, entry) in colorEntries.enumerated() {
            values.append((ScribeKeyMapTests.instance(entry.scribePath), .scalar("#0000\(index + 10)")))
        }
        let source = ScribeConfigSource(scribe: configTree(values))
        #expect(source.servedPresetIDs == ["wechat", "wechat:dark"])

        for (index, entry) in styleEntries.enumerated() {
            let squirrel = ScribeKeyMapTests.instance(entry.squirrelPath)
            #expect(source.string(at: squirrel) == "style \(index)")
            // The dark palette has no style of its own, so the theme's applies.
            #expect(source.string(at: squirrel.replacing("/wechat/", with: "/wechat:dark/")) == "style \(index)")
        }
        for (index, entry) in colorEntries.enumerated() {
            let expected = RGBAColor(scribe: "#0000\(index + 10)", colorSpace: .sRGB)!.squirrelLiteral
            #expect(source.string(at: ScribeKeyMapTests.instance(entry.squirrelPath)) == expected, "\(entry.scribePath)")
        }
        for preset in ["wechat", "wechat:dark"] {
            #expect(source.string(at: "preset_color_schemes/\(preset)/name") == "微信键盘")
            #expect(source.string(at: "preset_color_schemes/\(preset)/author") == "Max")
            #expect(source.string(at: "preset_color_schemes/\(preset)/color_space") == "display_p3")
        }
    }

    @Test func colorsBecomeSquirrelLiterals() {
        let source = ScribeConfigSource(scribe: configTree([
            ("themes/t/light/highlight_background", "#00B175"),
            ("themes/t/light/background", "#FFFFFF80"),
            ("themes/t/light/border", "0x75B100"),
            ("themes/t/light/label", ["not": "a colour"]),
        ]))
        #expect(source.string(at: "preset_color_schemes/t/hilited_candidate_back_color") == "0xFF75B100")
        #expect(source.string(at: "preset_color_schemes/t/back_color") == "0x80FFFFFF")
        #expect(source.string(at: "preset_color_schemes/t/border_color") == nil)
        #expect(source.string(at: "preset_color_schemes/t/label_color") == nil)
        #expect(source.mapKeys(at: "preset_color_schemes/t") == ["back_color", "hilited_candidate_back_color"])
    }

    @Test func paletteStyleBeatsThemeStyle() {
        let source = ScribeConfigSource(scribe: configTree([
            ("themes/t/style/corner_radius", 5),
            ("themes/t/style/layout", "linear"),
            ("themes/t/light/style/corner_radius", 6),
            ("themes/t/dark/style/layout", "stacked"),
        ]))
        #expect(source.int(at: "preset_color_schemes/t/corner_radius") == 6)
        #expect(source.string(at: "preset_color_schemes/t/candidate_list_layout") == "linear")
        #expect(source.int(at: "preset_color_schemes/t:dark/corner_radius") == 5)
        #expect(source.string(at: "preset_color_schemes/t:dark/candidate_list_layout") == "stacked")
    }

    @Test func invalidThemeIDsAreNotServed() {
        let source = ScribeConfigSource(scribe: configTree([
            ("themes/good/light/background", "#FFFFFF"),
            ("themes/bad:id/light/background", "#FFFFFF"),
            ("themes/@x/light/background", "#FFFFFF"),
            ("themes/scalar", "not a theme"),
        ]))
        #expect(source.servedPresetIDs == ["good"])
        #expect(source.mapKeys(at: "preset_color_schemes") == ["good"])
    }

    struct Selection: Sendable, CustomTestStringConvertible {
        var theme: String?
        var darkTheme: String?
        var colorScheme: String?
        var colorSchemeDark: String?
        var testDescription: String { "\(theme ?? "-") / \(darkTheme ?? "-")" }
    }

    @Test(arguments: [
        Selection(theme: nil, darkTheme: nil, colorScheme: nil, colorSchemeDark: nil),
        Selection(theme: "light_only", darkTheme: nil, colorScheme: "light_only", colorSchemeDark: nil),
        Selection(theme: "both", darkTheme: nil, colorScheme: "both", colorSchemeDark: "both:dark"),
        Selection(theme: "aqua", darkTheme: nil, colorScheme: "aqua", colorSchemeDark: nil),
        Selection(theme: "native", darkTheme: nil, colorScheme: "native", colorSchemeDark: nil),
        Selection(theme: "light_only", darkTheme: "both", colorScheme: "light_only", colorSchemeDark: "both:dark"),
        Selection(theme: "both", darkTheme: "light_only", colorScheme: "both", colorSchemeDark: "light_only"),
        Selection(theme: "both", darkTheme: "solarized_dark", colorScheme: "both", colorSchemeDark: "solarized_dark"),
        Selection(theme: "both", darkTheme: "native", colorScheme: "both", colorSchemeDark: "native"),
        Selection(theme: nil, darkTheme: "both", colorScheme: nil, colorSchemeDark: "both:dark"),
    ])
    func themeSelection(selection: Selection) {
        var values: [(String, ConfigNode)] = [
            ("themes/light_only/light/background", "#FFFFFF"),
            ("themes/both/light/background", "#FFFFFF"),
            ("themes/both/dark/background", "#000000"),
        ]
        if let theme = selection.theme {
            values.append(("appearance/theme", .scalar(theme)))
        }
        if let darkTheme = selection.darkTheme {
            values.append(("appearance/dark_theme", .scalar(darkTheme)))
        }
        let source = ScribeConfigSource(scribe: configTree(values))
        #expect(source.string(at: "style/color_scheme") == selection.colorScheme)
        #expect(source.string(at: "style/color_scheme_dark") == selection.colorSchemeDark)
    }

    @Test func squirrelDarkSchemeAppliesWhenScribeSetsNone() {
        let squirrel = configTree([("style/color_scheme", "aqua"), ("style/color_scheme_dark", "solarized_dark")])
        let lightOnly = configTree([("appearance/theme", "t"), ("themes/t/light/background", "#FFFFFF")])
        let merged = MergedConfigSource(squirrel: squirrel, scribe: lightOnly)
        #expect(merged.string(at: "style/color_scheme") == "t")
        #expect(merged.string(at: "style/color_scheme_dark") == "solarized_dark")
    }

    @Test func squirrelPresetsAndNative() {
        let squirrel = configTree([
            ("preset_color_schemes/aqua/text_color", "0x606060"),
            ("preset_color_schemes/native/name", "系統配色"),
        ])
        let aqua = Appearance(squirrel: squirrel, scribe: configTree([("appearance/theme", "aqua")]))
        #expect(aqua.light.colors.text == .rgba(RGBAColor(red: 0x60, green: 0x60, blue: 0x60)))
        let native = Appearance(squirrel: squirrel, scribe: configTree([("appearance/theme", "native")]))
        #expect(native.light.isNative)
        #expect(native.dark == nil)
    }

    @Test func scribeThemeShadowsASquirrelPreset() {
        let squirrel = configTree([
            ("style/color_scheme", "aqua"),
            ("preset_color_schemes/aqua/text_color", "0x606060"),
            ("preset_color_schemes/aqua/back_color", "0xeeeceeee"),
            ("preset_color_schemes/aqua/corner_radius", 9),
            ("preset_color_schemes/luna/text_color", "0x000000"),
        ])
        let scribe = configTree([("themes/aqua/light/background", "#000000")])
        let merged = MergedConfigSource(squirrel: squirrel, scribe: scribe)
        #expect(merged.scribe.owns("preset_color_schemes/aqua"))
        #expect(merged.scribe.owns("/preset_color_schemes/aqua/text_color"))
        #expect(!merged.scribe.owns("preset_color_schemes/luna/text_color"))
        #expect(!merged.scribe.owns("preset_color_schemes"))
        #expect(merged.string(at: "preset_color_schemes/aqua/text_color") == nil)
        #expect(merged.mapKeys(at: "preset_color_schemes/aqua") == ["back_color"])
        #expect(merged.mapKeys(at: "preset_color_schemes") == ["aqua", "luna"])

        let light = Appearance(squirrel: squirrel, scribe: scribe).light
        #expect(light.colors.background == .rgba(RGBAColor(red: 0, green: 0, blue: 0)))
        // Squirrel's in-palette fallback, not aqua's 0x606060.
        #expect(light.colors.text == .system(.secondaryLabel))
        #expect(light.cornerRadius == 0)
    }

    @Test func servedIDsComeFirstInPresetKeys() {
        let squirrel = configTree([("preset_color_schemes/aqua/text_color", "0x606060"), ("preset_color_schemes/zz/text_color", "0x000000")])
        let scribe = configTree([("themes/zz/light/background", "#000000"), ("themes/zz/dark/background", "#FFFFFF")])
        let merged = MergedConfigSource(squirrel: squirrel, scribe: scribe)
        #expect(merged.mapKeys(at: "preset_color_schemes") == ["zz", "zz:dark", "aqua"])
        #expect(PresetColorScheme.ids(in: merged) == ["zz", "zz:dark", "aqua"])
    }
}

@Suite("Scribe over Squirrel")
struct LayeringTests {
    let squirrel = configTree([
        ("style/corner_radius", 7),
        ("style/font_point", 16),
        ("style/inline_preedit", true),
        ("show_notifications_when", "appropriate"),
        ("app_options/com.googlecode.iterm2/ascii_mode", true),
        ("app_options/com.googlecode.iterm2/no_inline", true),
        ("app_options/com.apple.Terminal/ascii_mode", true),
    ])

    @Test func scribeKeyBeatsSquirrelKey() {
        let scribe = configTree([("appearance/corner_radius", 3), ("notifications", "never")])
        let settings = ScribeSettings(squirrel: squirrel, scribe: scribe)
        #expect(settings.appearance.light.cornerRadius == 3)
        #expect(settings.notificationPolicy == .never)
    }

    @Test func absentOrUnparsableScribeKeyFallsThrough() {
        let scribe = configTree([("appearance/inline_preedit", "maybe")])
        let light = Appearance(squirrel: squirrel, scribe: scribe).light
        #expect(light.candidateFont.pointSize == 16)
        #expect(light.inlinePreedit)
        #expect(light.cornerRadius == 7)
    }

    @Test func schemaStyleStillWins() {
        let scribe = configTree([("appearance/corner_radius", 3), ("appearance/font/size", 18)])
        let schema = configTree([("style/corner_radius", 9)])
        let light = Appearance(squirrel: squirrel, scribe: scribe, schema: schema).light
        #expect(light.cornerRadius == 9)
        #expect(light.candidateFont.pointSize == 18)
    }

    @Test func appOptionsReplacePerApp() {
        let scribe = configTree([("app_options/com.googlecode.iterm2/ascii_mode", false), ("app_options/org.example/inline", true)])
        let options = ScribeSettings(squirrel: squirrel, scribe: scribe).appOptions
        #expect(options.options(for: "com.googlecode.iterm2") == ["ascii_mode": false])
        #expect(options.options(for: "com.apple.Terminal") == ["ascii_mode": true])
        #expect(options.options(for: "org.example") == ["inline": true])
    }

    @Test func emptyScribeChangesNothing() {
        #expect(ScribeSettings(squirrel: maxSample, scribe: ConfigNode.null) == ScribeSettings(squirrel: maxSample))
        #expect(ScribeSettings(squirrel: squirrel, scribe: ConfigNode.map([:])) == ScribeSettings(squirrel: squirrel))
    }

    @Test func maxSampleInScribeFormat() throws {
        let scribe = Appearance(squirrel: squirrelDefaults, scribe: maxSampleScribe)
        let squirrel = ScribeSettings(squirrel: maxSample).appearance
        #expect(scribe.light.colorSchemeID == "wechat")
        #expect(scribe.dark?.colorSchemeID == "wechat:dark")
        #expect(withoutID(scribe.light) == withoutID(squirrel.light))
        #expect(try withoutID(#require(scribe.dark)) == withoutID(#require(squirrel.dark)))

        let settings = ScribeSettings(squirrel: squirrelDefaults, scribe: maxSampleScribe)
        #expect(settings.appOptions.options(for: "com.googlecode.iterm2") == ["ascii_mode": false])
    }
}

/// The theme with its colour scheme ID cleared, to compare schemes with different IDs.
func withoutID(_ theme: Theme) -> Theme {
    var theme = theme
    theme.colorSchemeID = nil
    return theme
}
