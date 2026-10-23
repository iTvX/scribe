import ScribeConfig

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

/// The keys both skins share.
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
        "candidate_format": "%c\u{2005}%@\u{2005}",
        "hilited_candidate_back_color": "0x75B100",
    ]
    return .map(shared.merging(extra) { _, extra in extra })
}
