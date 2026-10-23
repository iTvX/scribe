import ScribeConfig

/// squirrel.yaml's defaults as far as the tests need them: the global keys,
/// `style` with the native scheme, and the native preset.
let squirrelDefaults: ConfigNode = [
    "config_version": "1.0",
    "keyboard_layout": "last",
    "chord_duration": 0.1,
    "show_notifications_when": "appropriate",
    "status_icon": ["show": true],
    "style": .map(squirrelStyle.merging(["color_scheme": "native"]) { _, new in new }),
    "preset_color_schemes": ["native": ["name": "系統配色"]],
]

/// squirrel.yaml's `style`, without a colour scheme.
let squirrelStyle: [String: ConfigNode] = [
    "candidate_list_layout": "stacked",
    "text_orientation": "horizontal",
    "inline_preedit": true,
    "inline_candidate": false,
    "memorize_size": true,
    "mutual_exclusive": false,
    "translucency": false,
    "show_paging": false,
    "corner_radius": 7,
    "hilited_corner_radius": 0,
    "border_height": -2,
    "border_width": -2,
    "line_spacing": 5,
    "spacing": 8,
    "shadow_size": 0,
    "candidate_format": "[label]. [candidate] [comment]",
    "font_face": "Avenir",
    "font_point": 16,
]

/// Max's sample in Scribe's format, as Tests/Fixtures/config/max-sample/scribe.custom.yaml
/// sets it: one theme with both palettes, over `squirrelDefaults`.
let maxSampleScribe: ConfigNode = [
    "app_options": [
        "com.googlecode.iterm2": ["ascii_mode": false],
    ],
    "appearance": ["theme": "wechat"],
    "themes": [
        "wechat": [
            "name": "微信键盘",
            "style": [
                "layout": "linear",
                "padding": ["horizontal": 8, "vertical": 0],
                "corner_radius": 5,
                "font": ["face": "PingFangSC-Regular", "size": 16],
                "label_font": ["size": 12],
                "inline_preedit": true,
                "candidate_format": "%c %@ ",
            ],
            "light": [
                "background": "#FFFFFF",
                "preedit_text": "#424242",
                "highlight_background": "#00B175",
                "highlight_text": "#FFFFFF",
                "comment": "#999999",
            ],
            "dark": [
                "background": "#2D2D2D",
                "preedit_text": "#BDBDBD",
                "candidate_text": "#E0E0E0",
                "label": "#8C8C8C",
                "highlight_background": "#00B175",
                "highlight_text": "#FFFFFF",
                "comment": "#8C8C8C",
            ],
        ],
    ],
]

/// Max's configuration: squirrel.yaml's defaults plus two WeChat-style skins,
/// a light one and a dark one. Stage 2 turns the same values into a
/// squirrel.custom.yaml fixture.
let maxSample: ConfigNode = [
    "config_version": "1.0",
    "keyboard_layout": "last",
    "chord_duration": 0.1,
    "show_notifications_when": "appropriate",
    "status_icon": ["show": true],
    "app_options": [
        "com.googlecode.iterm2": ["ascii_mode": false],
    ],
    "style": [
        "color_scheme": "wechat_light",
        "color_scheme_dark": "wechat_dark",
        "candidate_list_layout": "stacked",
        "text_orientation": "horizontal",
        "inline_preedit": true,
        "inline_candidate": false,
        "memorize_size": true,
        "mutual_exclusive": false,
        "translucency": false,
        "show_paging": false,
        "corner_radius": 7,
        "hilited_corner_radius": 0,
        "border_height": -2,
        "border_width": -2,
        "line_spacing": 5,
        "spacing": 8,
        "shadow_size": 0,
        "candidate_format": "[label]. [candidate] [comment]",
        "font_face": "Avenir",
        "font_point": 16,
    ],
    "preset_color_schemes": [
        "native": ["name": "系統配色"],
        "wechat_light": wechatSkin(extra: [
            "name": "微信／WeChat Light",
            "back_color": "0xFFFFFF",
            "text_color": "0x424242",
            "hilited_candidate_text_color": "0xFFFFFF",
            "comment_text_color": "0x999999",
        ]),
        "wechat_dark": wechatSkin(extra: [
            "name": "微信／WeChat Dark",
            "back_color": "0x2D2D2D",
            "text_color": "0xBDBDBD",
            "candidate_text_color": "0xE0E0E0",
            "label_color": "0x8C8C8C",
            "hilited_candidate_text_color": "0xFFFFFF",
            "comment_text_color": "0x8C8C8C",
        ]),
    ],
]

/// The keys both skins share. Max's candidate_format has ASCII spaces,
/// though the comment next to it in his file says U+2005.
private func wechatSkin(extra: [String: ConfigNode]) -> ConfigNode {
    let shared: [String: ConfigNode] = [
        "candidate_list_layout": "linear",
        "border_width": 8,
        "border_height": 0,
        "corner_radius": 5,
        "font_face": "PingFangSC-Regular",
        "font_point": 16,
        "label_font_point": 12,
        "inline_preedit": true,
        "candidate_format": "%c %@ ",
        "hilited_candidate_back_color": "0x75B100",
    ]
    return .map(shared.merging(extra) { _, extra in extra })
}
