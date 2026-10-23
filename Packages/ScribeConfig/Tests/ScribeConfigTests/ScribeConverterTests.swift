import RimeKit
import ScribeConfig
import Testing

/// Conversion from Squirrel's format to scribe.custom.yaml entries. Each
/// fixture F is converted against Scribe's squirrel.yaml (the baseline B)
/// into a Scribe config S, which must reproduce F (a) on top of F, (b) on top
/// of B when nothing is left unconverted, and (c) convert to nothing again.
@MainActor
@Suite("Squirrel to Scribe conversion")
struct ScribeConverterTests {
    /// SharedSupport/squirrel.yaml as librime parses it.
    static let baseline: ConfigNode = {
        let yaml = try! ConfigFixtures.text(ConfigFixtures.squirrelYAML)
        return LibrimeEngine.shared.withConfig(.yaml(yaml)) { ConfigNode(snapshotOf: $0) }!
    }()

    /// The schemas whose style the themes are also compared under: none, one
    /// with a style that names a preset, and one without a style.
    static let schemas: [ConfigNode] = [
        .null,
        configTree([("style/color_scheme", "starcraft"), ("style/font_point", 20)]),
        configTree([("schema/schema_id", "plain"), ("preset_color_schemes/native/back_color", "0x000000")]),
    ]

    let baseline = Self.baseline

    @discardableResult
    func checkEquivalence(
        _ user: ConfigNode,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> ScribeConversion {
        let conversion = ScribeConverter.convert(user: user, baseline: baseline, scribe: ConfigNode.null)
        let scribe = configTree(conversion.entries.map { ($0.key, $0.value) })
        let renamed = conversion.themeIDs

        // (a) Nothing changes while the Squirrel files stay.
        expectEqual(
            ScribeSettings(squirrel: user, scribe: scribe),
            ScribeSettings(squirrel: user),
            renamed: renamed,
            "(a)",
            sourceLocation: sourceLocation
        )
        for schema in Self.schemas {
            expectEqual(
                Appearance(squirrel: user, scribe: scribe, schema: schema),
                Appearance(squirrel: user, schema: schema),
                renamed: renamed,
                "(a) with a schema",
                sourceLocation: sourceLocation
            )
        }

        // (b) Scribe's format alone carries the setup.
        if conversion.unconverted.isEmpty {
            var expected = ScribeSettings(squirrel: user)
            expected.configVersion = baseline.string(at: "config_version")
            expectEqual(
                ScribeSettings(squirrel: baseline, scribe: scribe),
                expected,
                renamed: renamed,
                "(b)",
                sourceLocation: sourceLocation
            )
        }

        // (c) Converting again gives nothing.
        let again = ScribeConverter.convert(user: user, baseline: baseline, scribe: scribe)
        #expect(again.isEmpty, "(c) \(again.entries.map(\.key))", sourceLocation: sourceLocation)
        #expect(again.themeIDs == conversion.themeIDs, "(c) theme IDs", sourceLocation: sourceLocation)
        return conversion
    }

    private func expectEqual(
        _ actual: ScribeSettings,
        _ expected: ScribeSettings,
        renamed: [String: String],
        _ label: String,
        sourceLocation: SourceLocation
    ) {
        let bundleIDs = Set(actual.appOptions.byBundleID.keys).union(expected.appOptions.byBundleID.keys)
        for bundleID in bundleIDs.sorted() {
            #expect(
                actual.appOptions.options(for: bundleID) == expected.appOptions.options(for: bundleID),
                "\(label) app options for \(bundleID)",
                sourceLocation: sourceLocation
            )
        }
        var actual = actual
        var expected = expected
        actual.appOptions = AppOptions()
        expected.appOptions = AppOptions()
        expected.appearance = Self.renaming(expected.appearance, renamed)
        #expect(actual == expected, "\(label) settings", sourceLocation: sourceLocation)
    }

    private func expectEqual(
        _ actual: Appearance,
        _ expected: Appearance,
        renamed: [String: String],
        _ label: String,
        sourceLocation: SourceLocation
    ) {
        #expect(actual == Self.renaming(expected, renamed), "\(label) appearance", sourceLocation: sourceLocation)
    }

    /// The appearance with each renamed preset's scheme ID replaced by its theme ID.
    static func renaming(_ appearance: Appearance, _ themeIDs: [String: String]) -> Appearance {
        func rename(_ theme: Theme) -> Theme {
            var theme = theme
            theme.colorSchemeID = theme.colorSchemeID.map { themeIDs[$0] ?? $0 }
            return theme
        }
        return Appearance(light: rename(appearance.light), dark: appearance.dark.map(rename))
    }

    // MARK: - Fixtures

    @Test func baselineConvertsToNothing() {
        let conversion = checkEquivalence(baseline)
        #expect(conversion == ScribeConversion())
    }

    /// The presets in SharedSupport/squirrel.yaml.
    nonisolated static let builtInPresetIDs = [
        "apathy", "aqua", "azure", "clean_white", "dark_temple", "dust", "google", "ink", "lost_temple",
        "luna", "mojave_dark", "native", "psionics", "purity_of_essence", "purity_of_form", "retro_green",
        "retro_orange", "solarized_dark", "solarized_light", "solarized_rock", "starcraft",
    ]

    @Test func builtInPresetIDs() {
        #expect(PresetColorScheme.ids(in: baseline) == Self.builtInPresetIDs)
    }

    @Test(arguments: builtInPresetIDs)
    func builtInPresetSelected(id: String) {
        let conversion = checkEquivalence(baseline.setting(.scalar(id), at: "style/color_scheme"))
        let expected = id == "native" ? [] : [ScribeConversion.Entry(key: "appearance/theme", value: .scalar(id))]
        #expect(conversion.entries == expected)
        #expect(conversion.themeIDs == [:])
        #expect(conversion.unconverted == [])
    }

    @Test func modifiedBuiltInPreset() {
        let user = baseline
            .setting("aqua", at: "style/color_scheme")
            .setting("0x000000", at: "preset_color_schemes/aqua/back_color")
            .setting(9, at: "preset_color_schemes/aqua/corner_radius")
            .setting("0x123", at: "preset_color_schemes/aqua/border_color")
        let conversion = checkEquivalence(user)
        #expect(conversion.themeIDs == ["aqua": "aqua"])
        #expect(conversion.entries.map(\.key) == ["appearance/theme", "themes/aqua"])
        let theme = conversion.entries.last?.value
        #expect(theme?.string(at: "name") == "碧水／Aqua")
        #expect(theme?.string(at: "style/corner_radius") == "9")
        #expect(theme?.string(at: "light/background") == "#000000")
        #expect(theme?.string(at: "light/highlight_background") == "#0A3AFAEE")
        // An unparsable colour is left out, as Squirrel ignores it.
        #expect(theme?.string(at: "light/border") == nil)
        #expect(theme?.mapKeys(at: "dark") == nil)

        // The theme replaces the built-in preset as a whole.
        let light = Appearance(squirrel: baseline, scribe: configTree(conversion.entries.map { ($0.key, $0.value) })).light
        #expect(light.colors.background == .rgba(RGBAColor(red: 0, green: 0, blue: 0)))
        #expect(light.cornerRadius == 9)
    }

    @Test func maxSample() throws {
        let user = baseline
            .setting(ConfigNode(snapshotOf: ScribeConfigTests.maxSample, at: "preset_color_schemes/wechat_light"),
                     at: "preset_color_schemes/wechat_light")
            .setting(ConfigNode(snapshotOf: ScribeConfigTests.maxSample, at: "preset_color_schemes/wechat_dark"),
                     at: "preset_color_schemes/wechat_dark")
            .setting("wechat_light", at: "style/color_scheme")
            .setting("wechat_dark", at: "style/color_scheme_dark")
            .setting(false, at: "app_options/com.googlecode.iterm2/ascii_mode")
            .removing("app_options/com.googlecode.iterm2/no_inline")
        let conversion = checkEquivalence(user)
        #expect(conversion.unconverted == [])
        #expect(conversion.themeIDs == ["wechat_dark": "wechat_dark", "wechat_light": "wechat_light"])
        #expect(conversion.entries.map(\.key) == [
            "appearance/theme", "appearance/dark_theme", "app_options/com.googlecode.iterm2",
            "themes/wechat_dark", "themes/wechat_light",
        ])

        // The same themes as PR D's sample written in Scribe's format by hand.
        let scribe = configTree(conversion.entries.map { ($0.key, $0.value) })
        let converted = Appearance(squirrel: baseline, scribe: scribe)
        let handWritten = Appearance(squirrel: baseline, scribe: ScribeConfigTests.maxSampleScribe)
        #expect(withoutID(converted.light) == withoutID(handWritten.light))
        #expect(try withoutID(#require(converted.dark)) == withoutID(#require(handWritten.dark)))
    }

    @Test func rimeIce() throws {
        let yaml = try ConfigFixtures.text(ConfigFixtures.rimeIceYAML)
        let user = try #require(LibrimeEngine.shared.withConfig(.yaml(yaml)) { ConfigNode(snapshotOf: $0) })
        let conversion = checkEquivalence(user)
        #expect(conversion.themeIDs == ["purity_of_form_custom": "purity_of_form_custom"])
        #expect(!conversion.unconverted.isEmpty)
        try ConfigFixtures.expectSnapshot(snapshot(conversion), named: "rime-ice-conversion")
    }

    @Test func everyKeyChanged() {
        var user = baseline
        let settings = ScribeKeyMap.entries.filter { entry in
            !entry.scribePath.hasPrefix("themes/") && !entry.scribePath.hasPrefix("app_options/")
                && entry.scribePath != "appearance/theme" && entry.scribePath != "appearance/dark_theme"
        }
        for entry in settings {
            user = user.setting(.scalar(Self.changedValue(entry, from: baseline.string(at: entry.squirrelPath))), at: entry.squirrelPath)
        }
        for key in ["name", "author"] {
            user = user.setting(.scalar("Custom \(key)"), at: "preset_color_schemes/custom/\(key)")
        }
        user = user.setting("display_p3", at: "preset_color_schemes/custom/color_space")
        let schemeEntries = ScribeKeyMap.entries.filter { $0.scribePath.hasPrefix("themes/{id}/style/") }
        for entry in schemeEntries {
            let path = entry.squirrelPath.replacing("{id}", with: "custom")
            user = user.setting(.scalar(Self.changedValue(entry, from: nil)), at: path)
        }
        let colorEntries = ScribeKeyMap.entries.filter { $0.scribePath.hasPrefix("themes/{id}/light/") }
        for (index, entry) in colorEntries.enumerated() {
            user = user.setting(.scalar("0x8000\(index + 10)FF"), at: entry.squirrelPath.replacing("{id}", with: "custom"))
        }
        user = user
            .setting("custom", at: "style/color_scheme")
            .setting("solarized_dark", at: "style/color_scheme_dark")
            .setting(true, at: "app_options/org.example.App/ascii_mode")

        let conversion = checkEquivalence(user)
        #expect(conversion.unconverted == [])
        let keys = Set(conversion.entries.map(\.key))
        for entry in settings + [ScribeKeyMap.entry(forScribe: "appearance/theme")!] {
            #expect(keys.contains(entry.scribePath), "\(entry.scribePath)")
        }
        #expect(keys.contains("appearance/dark_theme"))
        #expect(keys.contains("app_options/org.example.App"))
        let theme = conversion.entries.first { $0.key == "themes/custom" }?.value
        #expect(theme?.mapKeys(at: "light")?.count == 16)
        #expect(theme?.string(at: "style/padding/horizontal") != nil)
        #expect(theme?.string(at: "color_space") == "display_p3")
        #expect(theme?.string(at: "light/background") == "#FF100080")
    }

    /// A valid value for the entry's kind that differs from `base`.
    static func changedValue(_ entry: ScribeKeyMap.Entry, from base: String?) -> String {
        switch entry.kind {
        case .bool:
            base == "true" ? "false" : "true"
        case .int, .double:
            base == "0.5" ? "0.25" : "0.5"
        case .enumeration(let values):
            values.first { $0 != base }!
        case .string:
            base == "Menlo" ? "Courier" : "Menlo"
        case .color:
            "0xFF000000"
        }
    }

    @Test func presetIDsThatNeedRenaming() {
        let user = baseline
            .setting("0x000001", at: "preset_color_schemes/Foo:Bar/back_color")
            .setting("0x000002", at: "preset_color_schemes/foo_bar/back_color")
            .setting(["back_color": "0x000003"], at: "preset_color_schemes/@x")
            .setting("0x000004", at: "preset_color_schemes/Solar-Dark/back_color")
            .setting("0x000005", at: "preset_color_schemes/native/back_color")
            .setting("Foo:Bar", at: "style/color_scheme")
            .setting("@x", at: "style/color_scheme_dark")
        let conversion = checkEquivalence(user)
        #expect(conversion.themeIDs == [
            "@x": "_x",
            "Foo:Bar": "foo_bar_2",
            "Solar-Dark": "Solar-Dark",
            "foo_bar": "foo_bar",
        ])
        #expect(conversion.entries.map(\.key) == [
            "appearance/theme", "appearance/dark_theme",
            "themes/_x", "themes/foo_bar_2", "themes/Solar-Dark", "themes/foo_bar",
        ])
        #expect(conversion.entries[0].value == "foo_bar_2")
        #expect(conversion.entries[1].value == "_x")
        // librime cannot reach "@x" by path, so its theme is empty, as Squirrel reads it.
        #expect(conversion.entries[2].value == .map([:]))
    }

    @Test func servableIDsAreKeptAsWritten() {
        let user = baseline
            .setting("0x000001", at: "preset_color_schemes/My Theme/back_color")
            .setting("My Theme", at: "style/color_scheme")
        let conversion = checkEquivalence(user)
        #expect(conversion.themeIDs == ["My Theme": "My Theme"])
        #expect(conversion.entries.first == ScribeConversion.Entry(key: "appearance/theme", value: "My Theme"))
    }

    @Test func renamedPresetIsSelectedByItsThemeID() {
        // The baseline selects the same preset, so only the rename makes
        // appearance/theme differ.
        let baseline = baseline
            .setting("0x000001", at: "preset_color_schemes/Foo:Bar/back_color")
            .setting("Foo:Bar", at: "style/color_scheme")
        let user = baseline.setting("0x000002", at: "preset_color_schemes/Foo:Bar/back_color")
        let conversion = ScribeConverter.convert(user: user, baseline: baseline, scribe: ConfigNode.null)
        #expect(conversion.themeIDs == ["Foo:Bar": "foo_bar"])
        #expect(conversion.entries.map(\.key) == ["appearance/theme", "themes/foo_bar"])
        #expect(conversion.entries.first?.value == "foo_bar")
        let scribe = configTree(conversion.entries.map { ($0.key, $0.value) })
        #expect(
            Appearance(squirrel: baseline, scribe: scribe)
                == Self.renaming(Appearance(squirrel: user), conversion.themeIDs)
        )
    }

    @Test func appOptions() {
        let user = baseline
            .setting(false, at: "app_options/com.googlecode.iterm2/ascii_mode")
            .setting(true, at: "app_options/org.example.New/ascii_mode")
            .removing("app_options/com.apple.Terminal")
        let conversion = checkEquivalence(user)
        #expect(conversion.entries == [
            ScribeConversion.Entry(key: "app_options/com.apple.Terminal", value: .map([:])),
            ScribeConversion.Entry(key: "app_options/com.googlecode.iterm2", value: ["ascii_mode": false, "no_inline": true]),
            ScribeConversion.Entry(key: "app_options/org.example.New", value: ["ascii_mode": true]),
        ])
    }

    @Test func neverOverwrites() {
        let user = baseline
            .setting(20, at: "style/font_point")
            .setting(9, at: "style/corner_radius")
            .setting("aqua", at: "style/color_scheme")
            .setting("solarized_dark", at: "style/color_scheme_dark")
            .setting("0x000000", at: "preset_color_schemes/aqua/back_color")
            .setting(false, at: "app_options/com.googlecode.iterm2/ascii_mode")
            .setting(false, at: "app_options/com.apple.Terminal/ascii_mode")
        let scribe = configTree([
            ("appearance/font/size", 18),
            ("appearance/theme", "luna"),
            ("app_options/com.googlecode.iterm2/no_inline", false),
            ("themes/aqua/light/background", "#FFFFFF"),
        ])
        let conversion = ScribeConverter.convert(user: user, baseline: baseline, scribe: scribe)
        #expect(conversion.entries.map(\.key) == ["appearance/corner_radius", "app_options/com.apple.Terminal"])
        #expect(conversion.themeIDs == ["aqua": "aqua"])

        let unconverted = ScribeConverter.convert(
            user: baseline.removing("style/font_point").removing("style/spacing"),
            baseline: baseline,
            scribe: configTree([("appearance/font/size", 18)])
        )
        #expect(unconverted.unconverted == [
            ScribeConversion.Unconverted(squirrelPath: "style/spacing", scribePath: "appearance/preedit_spacing", reason: .absentFromSquirrelConfig),
        ])
        #expect(unconverted.isEmpty)
    }

    @Test func appliesWithThePatchEditor() throws {
        let user = baseline
            .setting("aqua", at: "style/color_scheme")
            .setting("0x000000", at: "preset_color_schemes/aqua/back_color")
            .removing("app_options/com.apple.Terminal")
        let conversion = ScribeConverter.convert(user: user, baseline: baseline, scribe: ConfigNode.null)
        var editor = try CustomPatchEditor(text: "")
        conversion.apply(to: &editor)
        #expect(editor.keys == conversion.entries.map(\.key))
        #expect(editor.text.contains("app_options/com.apple.Terminal: {}"))
    }
}
