import ScribeConfig
import Testing

private let presets: ConfigNode = [
    "native": ["name": "系統配色"],
    "aqua": [
        "name": "碧水／Aqua",
        "text_color": "0x606060",
        "back_color": "0xeeeceeee",
        "hilited_candidate_back_color": "0xeefa3a0a",
    ],
    "solarized_dark": ["color_space": "display_p3", "back_color": "0xF0352A0A", "corner_radius": 5],
]

private func squirrel(style: [String: ConfigNode]) -> ConfigNode {
    ["style": .map(style), "preset_color_schemes": presets]
}

@Suite("Light and dark themes")
struct AppearanceTests {
    @Test func lightOnly() {
        let appearance = Appearance(squirrel: squirrel(style: ["color_scheme": "aqua"]))
        #expect(appearance.light.colorSchemeID == "aqua")
        #expect(appearance.dark == nil)
        #expect(appearance.forcesLightAppearance)
        #expect(appearance.theme(isDark: true) == appearance.light)
        #expect(appearance.theme(isDark: false) == appearance.light)
    }

    @Test func nativeLightOnly() {
        let appearance = Appearance(squirrel: squirrel(style: ["color_scheme": "native"]))
        #expect(appearance.light.isNative)
        #expect(appearance.dark == nil)
        #expect(!appearance.forcesLightAppearance)
    }

    @Test func lightAndDark() {
        let appearance = Appearance(squirrel: squirrel(style: ["color_scheme": "aqua", "color_scheme_dark": "solarized_dark"]))
        let dark = appearance.dark
        #expect(dark?.colorSchemeID == "solarized_dark")
        #expect(dark?.colorSpace == .displayP3)
        #expect(dark?.cornerRadius == 5)
        #expect(appearance.light.cornerRadius == 0)
        #expect(!appearance.forcesLightAppearance)
        #expect(appearance.theme(isDark: true) == dark)
        #expect(appearance.theme(isDark: false).colorSchemeID == "aqua")
    }

    @Test func darkNative() {
        let appearance = Appearance(squirrel: squirrel(style: ["color_scheme": "aqua", "color_scheme_dark": "native"]))
        #expect(appearance.dark?.isNative == true)
        #expect(appearance.dark?.colorSchemeID == "native")
        #expect(appearance.dark?.colors == .native)
        #expect(!appearance.forcesLightAppearance)
    }

    @Test func nothingSet() {
        let appearance = Appearance(squirrel: squirrel(style: [:]))
        #expect(appearance.light == Theme())
        #expect(appearance.dark == nil)
        #expect(!appearance.forcesLightAppearance)
    }

    @Test func darkThemeSharesTheStyleKeys() {
        let appearance = Appearance(squirrel: squirrel(style: [
            "color_scheme": "aqua", "color_scheme_dark": "solarized_dark", "font_point": 18, "inline_preedit": true,
        ]))
        #expect(appearance.light.candidateFont.pointSize == 18)
        #expect(appearance.dark?.candidateFont.pointSize == 18)
        #expect(appearance.dark?.inlinePreedit == true)
    }
}

@Suite("Schema style")
struct SchemaStyleTests {
    let base = squirrel(style: ["color_scheme": "aqua", "font_point": 16, "inline_preedit": true])

    @Test func schemaWithoutStyleIsIgnored() {
        let schema: ConfigNode = [
            "schema": ["schema_id": "luna_pinyin"],
            "preset_color_schemes": ["aqua": ["back_color": "0x000000"]],
            "color_scheme": "native",
        ]
        #expect(Appearance(squirrel: base, schema: schema) == Appearance(squirrel: base))
    }

    @Test func styleThatIsNotAMapIsIgnored() {
        let schema: ConfigNode = ["style": "linear", "preset_color_schemes": ["aqua": ["back_color": "0x000000"]]]
        #expect(Appearance(squirrel: base, schema: schema) == Appearance(squirrel: base))
    }

    @Test func emptyStyleMapStillCounts() {
        let schema: ConfigNode = ["style": [:], "preset_color_schemes": ["aqua": ["back_color": "0x000000"]]]
        let appearance = Appearance(squirrel: base, schema: schema)
        #expect(appearance.light.colors.background == .rgba(RGBAColor(red: 0, green: 0, blue: 0)))
        #expect(appearance.light.candidateFont.pointSize == 16)
    }

    @Test func styleKeysFallBackOneByOne() {
        let schema: ConfigNode = ["style": ["font_point": 20, "inline_preedit": "maybe", "candidate_list_layout": "linear"]]
        let light = Appearance(squirrel: base, schema: schema).light
        #expect(light.candidateFont.pointSize == 20)
        #expect(light.inlinePreedit)
        #expect(light.layout == .linear)
        #expect(light.colorSchemeID == "aqua")
    }

    @Test func schemaPicksAPresetFromSquirrel() {
        let schema: ConfigNode = ["style": ["color_scheme": "solarized_dark"]]
        let appearance = Appearance(squirrel: base, schema: schema)
        #expect(appearance.light.colorSchemeID == "solarized_dark")
        #expect(appearance.light.colorSpace == .displayP3)
        #expect(appearance.light.cornerRadius == 5)
        #expect(appearance.dark == nil)
    }

    @Test func schemaPresetKeyOverridesOneKey() {
        let schema: ConfigNode = [
            "style": ["color_scheme": "aqua"],
            "preset_color_schemes": ["aqua": ["back_color": "0x000000", "text_color": "not a colour"]],
        ]
        let colors = Appearance(squirrel: base, schema: schema).light.colors
        #expect(colors.background == .rgba(RGBAColor(red: 0, green: 0, blue: 0)))
        #expect(colors.text == .rgba(RGBAColor(red: 0x60, green: 0x60, blue: 0x60)))
        #expect(colors.hilitedCandidateBackground == .rgba(RGBAColor(red: 0x0A, green: 0x3A, blue: 0xFA, alpha: 0xEE)))
    }

    @Test func schemaCanAddADarkTheme() {
        let schema: ConfigNode = ["style": ["color_scheme_dark": "native"]]
        let appearance = Appearance(squirrel: base, schema: schema)
        #expect(appearance.light.colorSchemeID == "aqua")
        #expect(appearance.dark?.isNative == true)
    }
}
