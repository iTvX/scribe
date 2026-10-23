import ScribeConfig
import Testing

@Suite("Global settings")
struct ScribeSettingsTests {
    @Test(arguments: [
        (ConfigNode.null, KeyboardLayout.last),
        ("", .last),
        ("last", .last),
        ("default", .named("com.apple.keylayout.ABC")),
        ("com.apple.keylayout.USExtended", .named("com.apple.keylayout.USExtended")),
        ("USExtended", .named("com.apple.keylayout.USExtended")),
        ("Last", .named("com.apple.keylayout.Last")),
        ("com.apple.keylayout.", .named("com.apple.keylayout.")),
    ])
    func keyboardLayout(value: ConfigNode, expected: KeyboardLayout) {
        #expect(ScribeSettings(squirrel: ConfigNode.map(["keyboard_layout": value])).keyboardLayout == expected)
    }

    @Test(arguments: [
        (ConfigNode.null, 0.1),
        (0, 0.1),
        (-1, 0.1),
        ("abc", 0.1),
        (0.05, 0.05),
        ("0.3s", 0.3),
    ])
    func chordDuration(value: ConfigNode, expected: Double) {
        #expect(ScribeSettings(squirrel: ConfigNode.map(["chord_duration": value])).chordDuration == expected)
    }

    @Test(arguments: [
        (ConfigNode.null, NotificationPolicy.appropriate),
        ("appropriate", .appropriate),
        ("always", .always),
        ("never", .never),
        ("Never", .appropriate),
        ("sometimes", .appropriate),
    ])
    func notificationPolicy(value: ConfigNode, expected: NotificationPolicy) {
        let settings = ScribeSettings(squirrel: ConfigNode.map(["show_notifications_when": value]))
        #expect(settings.notificationPolicy == expected)
        #expect(settings.showsNotifications == (expected != .never))
    }

    @Test func statusIconAndBundleIDReport() {
        let defaults = ScribeSettings(squirrel: ConfigNode.map([:]))
        #expect(defaults.showsStatusIcon)
        #expect(!defaults.reportsBundleID)
        let set = ScribeSettings(squirrel: ConfigNode.map([
            "status_icon": ["show": false],
            "unsafe": ["report_bundleid": true],
        ]))
        #expect(!set.showsStatusIcon)
        #expect(set.reportsBundleID)
        let unparsable = ScribeSettings(squirrel: ConfigNode.map([
            "status_icon": ["show": "no"],
            "unsafe": ["report_bundleid": "yes"],
        ]))
        #expect(unparsable.showsStatusIcon)
        #expect(!unparsable.reportsBundleID)
    }

    @Test func appOptions() {
        let settings = ScribeSettings(squirrel: ConfigNode.map([
            "app_options": [
                "com.googlecode.iterm2": ["ascii_mode": false, "no_inline": true, "vim_mode": "maybe", "nested": ["x": true]],
                "com.apple.Terminal": ["ascii_mode": "TRUE"],
                "org.example.Scalar": "ascii_mode",
            ],
        ]))
        let options = settings.appOptions
        #expect(options.options(for: "com.googlecode.iterm2") == ["ascii_mode": false, "no_inline": true])
        #expect(options.options(for: "com.apple.Terminal") == ["ascii_mode": true])
        #expect(options.options(for: "com.googlecode.ITerm2") == [:])
        #expect(options.options(for: "org.example.Scalar") == [:])
        #expect(options.options(for: "org.example.Missing") == [:])
        #expect(options.byBundleID.keys.sorted() == ["com.apple.Terminal", "com.googlecode.iterm2", "org.example.Scalar"])
    }

    @Test func noAppOptions() {
        #expect(ScribeSettings(squirrel: ConfigNode.map([:])).appOptions == AppOptions())
        #expect(ScribeSettings(squirrel: ConfigNode.map(["app_options": nil])).appOptions == AppOptions())
    }

    @Test func versionAndAppearance() {
        let config: ConfigNode = ["config_version": "1.0", "style": ["color_scheme": "native", "font_point": 16]]
        let settings = ScribeSettings(squirrel: config)
        #expect(settings.configVersion == "1.0")
        #expect(settings.appearance == Appearance(squirrel: config))
        #expect(ScribeSettings(squirrel: ConfigNode.map([:])).configVersion == nil)
    }
}

@Suite("Preset colour schemes")
struct PresetColorSchemeTests {
    let config: ConfigNode = [
        "preset_color_schemes": [
            "solarized_light": [
                "name": "曬經・日／Solarized Light",
                "author": "雪齋 <lyc20041@gmail.com>",
                "color_space": "display_p3",
                "back_color": "0xF0E5F6FB",
                "hilited_candidate_back_color": "0x8EE3F9",
                "label_color": "not a colour",
            ],
            "aqua": ["text_color": "0x606060"],
            "broken": "not a map",
        ],
    ]

    @Test func ids() {
        #expect(PresetColorScheme.ids(in: config) == ["aqua", "solarized_light"])
        #expect(PresetColorScheme.ids(in: ConfigNode.map([:])) == [])
    }

    @Test func readsTheRawValues() throws {
        let scheme = try #require(PresetColorScheme(id: "solarized_light", source: config))
        #expect(scheme.id == "solarized_light")
        #expect(scheme.name == "曬經・日／Solarized Light")
        #expect(scheme.author == "雪齋 <lyc20041@gmail.com>")
        #expect(scheme.colorSpace == .displayP3)
        #expect(scheme.backColor == RGBAColor(red: 0xFB, green: 0xF6, blue: 0xE5, alpha: 0xF0, colorSpace: .displayP3))
        #expect(scheme.hilitedCandidateBackColor?.hex == "#F9E38EFF")
        #expect(scheme.labelColor == nil)
        #expect(scheme.textColor == nil)
        #expect(scheme.hilitedBackColor == nil)
    }

    @Test func onlyMaps() {
        #expect(PresetColorScheme(id: "broken", source: config) == nil)
        #expect(PresetColorScheme(id: "missing", source: config) == nil)
        #expect(PresetColorScheme(id: "aqua", source: config)?.name == nil)
    }
}
