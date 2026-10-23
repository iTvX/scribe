import ScribeConfig
import Testing

/// A theme from `style` keys and, when given, a colour scheme "custom" with
/// its own keys.
private func makeTheme(style: [String: ConfigNode], scheme: [String: ConfigNode]? = nil) -> Theme {
    var style = style
    var root: [String: ConfigNode] = [:]
    if let scheme {
        style["color_scheme"] = "custom"
        root["preset_color_schemes"] = ["custom": .map(scheme)]
    }
    root["style"] = .map(style)
    return Theme(source: ConfigNode.map(root), colorSchemeKey: "style/color_scheme")
}

@Suite("Theme style keys")
struct ThemeStyleTests {
    static let boolKeys: [(String, KeyPath<Theme, Bool> & Sendable)] = [
        ("inline_preedit", \.inlinePreedit),
        ("inline_candidate", \.inlineCandidate),
        ("translucency", \.translucency),
        ("mutual_exclusive", \.mutualExclusive),
        ("show_paging", \.showPaging),
    ]

    static let doubleKeys: [(String, KeyPath<Theme, Double> & Sendable)] = [
        ("alpha", \.alpha),
        ("corner_radius", \.cornerRadius),
        ("hilited_corner_radius", \.hilitedCornerRadius),
        ("surrounding_extra_expansion", \.surroundingExtraExpansion),
        ("border_height", \.borderHeight),
        ("border_width", \.borderWidth),
        ("line_spacing", \.lineSpacing),
        ("spacing", \.spacing),
        ("base_offset", \.baseOffset),
        ("shadow_size", \.shadowSize),
    ]

    @Test(arguments: boolKeys)
    func boolFromStyleAndScheme(key: String, field: KeyPath<Theme, Bool> & Sendable) {
        let defaultValue = Theme()[keyPath: field]
        #expect(makeTheme(style: [key: .scalar("\(!defaultValue)")])[keyPath: field] == !defaultValue)
        #expect(makeTheme(style: [key: .scalar("\(!defaultValue)")], scheme: [key: .scalar("\(defaultValue)")])[keyPath: field] == defaultValue)
        // A scheme value that is not a bool keeps the style value.
        #expect(makeTheme(style: [key: .scalar("\(!defaultValue)")], scheme: [key: "yes"])[keyPath: field] == !defaultValue)
        #expect(makeTheme(style: [key: "yes"])[keyPath: field] == defaultValue)
    }

    @Test(arguments: doubleKeys)
    func doubleFromStyleAndScheme(key: String, field: KeyPath<Theme, Double> & Sendable) {
        #expect(makeTheme(style: [key: 0.5])[keyPath: field] == 0.5)
        #expect(makeTheme(style: [key: 0.5], scheme: [key: 0.25])[keyPath: field] == 0.25)
        #expect(makeTheme(style: [key: 0.5], scheme: [key: "abc"])[keyPath: field] == 0.5)
        #expect(makeTheme(style: [key: "abc"])[keyPath: field] == Theme()[keyPath: field])
    }

    @Test func lengthsMayBeNegative() {
        let theme = makeTheme(style: ["border_width": -2, "border_height": "-2", "base_offset": "-1.5"])
        #expect(theme.borderWidth == -2)
        #expect(theme.borderHeight == -2)
        #expect(theme.baseOffset == -1.5)
    }

    @Test func alphaIsClamped() {
        #expect(makeTheme(style: ["alpha": 1.5]).alpha == 1)
        #expect(makeTheme(style: ["alpha": -0.5]).alpha == 0)
        #expect(makeTheme(style: ["alpha": 0.5], scheme: ["alpha": 2]).alpha == 1)
        #expect(makeTheme(style: ["alpha": 0.5], scheme: ["alpha": -1]).alpha == 0)
        // Squirrel's clamps differ only for NaN.
        #expect(makeTheme(style: ["alpha": "nan"]).alpha == 0)
        #expect(makeTheme(style: [:], scheme: ["alpha": "nan"]).alpha == 1)
    }

    @Test func shadowSizeIsAtLeastZero() {
        #expect(makeTheme(style: ["shadow_size": -3]).shadowSize == 0)
        #expect(makeTheme(style: ["shadow_size": 2], scheme: ["shadow_size": -1]).shadowSize == 0)
        #expect(makeTheme(style: ["shadow_size": 2]).shadowSize == 2)
    }

    @Test(arguments: [
        ("linear", CandidateListLayout.linear),
        ("stacked", .stacked),
        ("horizontal", .stacked),
        ("Linear", .stacked),
        ("", .stacked),
    ])
    func layout(value: String, expected: CandidateListLayout) {
        #expect(makeTheme(style: ["candidate_list_layout": .scalar(value)]).layout == expected)
        #expect(makeTheme(style: ["candidate_list_layout": "linear"], scheme: ["candidate_list_layout": .scalar(value)]).layout == expected)
    }

    @Test func layoutNeedsAString() {
        #expect(makeTheme(style: ["candidate_list_layout": "linear"], scheme: ["candidate_list_layout": ["linear"]]).layout == .linear)
    }

    @Test(arguments: [
        ("vertical", TextOrientation.vertical),
        ("horizontal", .horizontal),
        ("Vertical", .horizontal),
        ("", .horizontal),
    ])
    func orientation(value: String, expected: TextOrientation) {
        #expect(makeTheme(style: ["text_orientation": .scalar(value)]).orientation == expected)
        #expect(makeTheme(style: ["text_orientation": "vertical"], scheme: ["text_orientation": .scalar(value)]).orientation == expected)
    }

    @Test(arguments: [
        ("long", StatusMessageType.long),
        ("short", .short),
        ("mix", .mix),
        ("medium", .mix),
        ("Long", .mix),
    ])
    func statusMessageType(value: String, expected: StatusMessageType) {
        #expect(makeTheme(style: ["status_message_type": .scalar(value)]).statusMessageType == expected)
    }

    @Test func schemeCannotSetMemorizeSizeOrStatusMessageType() {
        let theme = makeTheme(
            style: ["memorize_size": false, "status_message_type": "short"],
            scheme: ["memorize_size": true, "status_message_type": "long"]
        )
        #expect(theme.memorizeSize == false)
        #expect(theme.statusMessageType == .short)
        let defaults = makeTheme(style: [:], scheme: ["memorize_size": false, "status_message_type": "long"])
        #expect(defaults.memorizeSize == true)
        #expect(defaults.statusMessageType == .mix)
    }

    @Test func schemeCannotSetItsColorScheme() {
        let theme = makeTheme(style: [:], scheme: ["color_scheme": "other"])
        #expect(theme.colorSchemeID == "custom")
    }

    @Test func candidateFormat() {
        #expect(makeTheme(style: ["candidate_format": "%c %@"]).candidateFormat.template == "[label] [candidate] [comment]")
        #expect(makeTheme(style: ["candidate_format": "%c %@"], scheme: ["candidate_format": "[candidate]"]).candidateFormat.template == "[candidate]")
        #expect(makeTheme(style: [:]).candidateFormat == .default)
    }

    @Test func styleKeysStayWhenTheSchemeOmitsThem() {
        let theme = makeTheme(style: ["candidate_list_layout": "linear", "corner_radius": 7, "inline_preedit": true], scheme: [:])
        #expect(theme.layout == .linear)
        #expect(theme.cornerRadius == 7)
        #expect(theme.inlinePreedit)
        #expect(!theme.isNative)
    }

    @Test func nativeSchemeKeysAreIgnored() {
        let config: ConfigNode = [
            "style": ["color_scheme": "native", "corner_radius": 7],
            "preset_color_schemes": ["native": ["corner_radius": 3, "candidate_list_layout": "linear", "back_color": "0x000000"]],
        ]
        let theme = Theme(source: config, colorSchemeKey: "style/color_scheme")
        #expect(theme.isNative)
        #expect(theme.colorSchemeID == "native")
        #expect(theme.cornerRadius == 7)
        #expect(theme.layout == .stacked)
        #expect(theme.colors == .native)
    }
}
