import ScribeConfig
import Testing

@Suite("Scribe key map")
struct ScribeKeyMapTests {
    static let bindings = ["{app}": "com.googlecode.iterm2", "{option}": "ascii_mode", "{id}": "wechat"]

    /// A pattern with its placeholders filled in.
    static func instance(_ pattern: String) -> String {
        bindings.reduce(pattern) { path, binding in path.replacing(binding.key, with: binding.value) }
    }

    @Test(arguments: ScribeKeyMap.entries)
    func roundTrip(entry: ScribeKeyMap.Entry) {
        let scribe = Self.instance(entry.scribePath)
        let squirrel = Self.instance(entry.squirrelPath)
        #expect(ScribeKeyMap.squirrelPath(forScribe: scribe) == squirrel)
        #expect(ScribeKeyMap.scribePath(forSquirrel: squirrel) == scribe)
        #expect(ScribeKeyMap.entry(forScribe: scribe) == entry)
    }

    @Test func noDuplicates() {
        let entries = ScribeKeyMap.entries
        #expect(Set(entries.map(\.scribePath)).count == entries.count)
        #expect(Set(entries.map(\.squirrelPath)).count == entries.count)
        // 6 global, 30 appearance, 3 theme metadata, 26 style keys for the
        // theme and the dark palette, 16 colours for each palette.
        #expect(entries.count == 6 + 30 + 3 + 26 * 2 + 16 * 2)
    }

    @Test(arguments: [
        ("notifications", "show_notifications_when"),
        ("status_icon", "status_icon/show"),
        ("report_bundle_id", "unsafe/report_bundleid"),
        ("appearance/layout", "style/candidate_list_layout"),
        ("appearance/status_message", "style/status_message_type"),
        ("appearance/label_font/size", "style/label_font_point"),
        ("appearance/padding/horizontal", "style/border_width"),
        ("appearance/padding/vertical", "style/border_height"),
        ("appearance/preedit_spacing", "style/spacing"),
        ("appearance/highlight_expansion", "style/surrounding_extra_expansion"),
        ("appearance/theme", "style/color_scheme"),
        ("appearance/dark_theme", "style/color_scheme_dark"),
        ("themes/wechat/color_space", "preset_color_schemes/wechat/color_space"),
        ("themes/wechat/style/highlight_corner_radius", "preset_color_schemes/wechat/hilited_corner_radius"),
        ("themes/wechat/dark/style/font/face", "preset_color_schemes/wechat:dark/font_face"),
        ("themes/wechat/light/highlight_background", "preset_color_schemes/wechat/hilited_candidate_back_color"),
        ("themes/wechat/dark/preedit_text", "preset_color_schemes/wechat:dark/text_color"),
        ("app_options/com.apple.Terminal/no_inline", "app_options/com.apple.Terminal/no_inline"),
    ])
    func examples(scribe: String, squirrel: String) {
        #expect(ScribeKeyMap.squirrelPath(forScribe: scribe) == squirrel)
        #expect(ScribeKeyMap.scribePath(forSquirrel: squirrel) == scribe)
    }

    @Test func lightPaletteStyleFeedsTheLightPreset() {
        #expect(ScribeKeyMap.squirrelPath(forScribe: "themes/wechat/light/style/layout")
            == "preset_color_schemes/wechat/candidate_list_layout")
        #expect(ScribeKeyMap.squirrelPath(forScribe: "themes/wechat/light/style/font/size")
            == "preset_color_schemes/wechat/font_point")
        #expect(ScribeKeyMap.squirrelPath(forScribe: "themes/wechat/light/style/memorize_size") == nil)
    }

    @Test func darkPresetMetadataIsTheTheme() {
        #expect(ScribeKeyMap.scribePath(forSquirrel: "preset_color_schemes/wechat:dark/name") == "themes/wechat/name")
        #expect(ScribeKeyMap.scribePath(forSquirrel: "preset_color_schemes/wechat:dark/color_space")
            == "themes/wechat/color_space")
    }

    @Test(arguments: [
        "config_version",
        "appearance",
        "appearance/font",
        "appearance/unknown",
        "style/color_scheme",
        "themes/wechat/style/memorize_size",
        "themes/wechat/style/theme",
        "themes/we:chat/light/background",
        "themes//light/background",
        "app_options/com.apple.Terminal",
    ])
    func noSquirrelPath(scribe: String) {
        #expect(ScribeKeyMap.squirrelPath(forScribe: scribe) == nil)
    }

    @Test(arguments: [
        "config_version",
        "style/memorize_size/x",
        "preset_color_schemes/wechat:dark:dark/back_color",
        "preset_color_schemes/wechat/unknown",
        "keyboard_layout/x",
    ])
    func noScribePath(squirrel: String) {
        #expect(ScribeKeyMap.scribePath(forSquirrel: squirrel) == nil)
    }

    @Test func kinds() {
        #expect(ScribeKeyMap.entry(forScribe: "notifications")?.kind == .enumeration(["always", "appropriate", "never"]))
        #expect(ScribeKeyMap.entry(forScribe: "appearance/layout")?.kind == .enumeration(["stacked", "linear"]))
        #expect(ScribeKeyMap.entry(forScribe: "themes/x/color_space")?.kind == .enumeration(["srgb", "display_p3"]))
        #expect(ScribeKeyMap.entry(forScribe: "themes/x/dark/border")?.kind == .color)
        #expect(ScribeKeyMap.entry(forScribe: "appearance/font/size")?.kind == .double)
        #expect(ScribeKeyMap.entry(forScribe: "app_options/a/b")?.kind == .bool)
        #expect(ScribeKeyMap.entries.filter { $0.kind == .color }.count == 32)
    }
}

extension ScribeKeyMap.Entry: CustomTestStringConvertible {
    public var testDescription: String { scribePath }
}
