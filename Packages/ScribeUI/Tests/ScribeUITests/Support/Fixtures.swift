import AppKit
import ScribeConfig
import ScribeCore
@testable import ScribeUI

/// Themes, palettes and content for rendering tests. Themes are written as
/// squirrel.yaml would write them and read by ScribeConfig, so Squirrel's
/// fallbacks come from the same code the app uses.
enum Fixtures {
    // MARK: Palettes

    /// macOS 27's system colours in light mode with the default blue
    /// highlight, fixed so native themes render the same everywhere.
    static let lightPalette = SystemPalette(
        windowBackground: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        label: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.847),
        secondaryLabel: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.498),
        selectedTextBackground: NSColor(srgbRed: 0.702, green: 0.843, blue: 1, alpha: 1),
        gray: NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    )

    static let darkPalette = SystemPalette(
        windowBackground: NSColor(srgbRed: 0.118, green: 0.118, blue: 0.118, alpha: 1),
        label: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.847),
        secondaryLabel: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.549),
        selectedTextBackground: NSColor(srgbRed: 0.247, green: 0.388, blue: 0.545, alpha: 1),
        gray: NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    )

    static var light: NSAppearance {
        NSAppearance(named: .aqua)!
    }

    static var dark: NSAppearance {
        NSAppearance(named: .darkAqua)!
    }

    // MARK: Themes

    /// squirrel.yaml's `style` section, with the font pinned to faces every
    /// Mac has so text does not depend on the machine's fallback fonts.
    static let squirrelStyle: [String: ConfigNode] = [
        "color_scheme": "native",
        "candidate_list_layout": "stacked",
        "text_orientation": "horizontal",
        "inline_preedit": "true",
        "inline_candidate": "false",
        "memorize_size": "true",
        "mutual_exclusive": "false",
        "translucency": "false",
        "show_paging": "false",
        "corner_radius": "7",
        "hilited_corner_radius": "0",
        "border_height": "-2",
        "border_width": "-2",
        "line_spacing": "5",
        "spacing": "8",
        "shadow_size": "0",
        "candidate_format": "[label]. [candidate] [comment]",
        "font_face": "Avenir, PingFang SC",
        "font_point": "16",
    ]

    /// The theme squirrel.yaml gives with `color_scheme` set to `scheme`,
    /// defined in `preset_color_schemes` as `colors` plus any `style`
    /// overrides.
    static func theme(scheme: String = "native", colors: [String: ConfigNode] = [:], style: [String: ConfigNode] = [:]) -> Theme {
        var styleMap = squirrelStyle.merging(style) { $1 }
        styleMap["color_scheme"] = .scalar(scheme)
        let config: ConfigNode = .map([
            "style": .map(styleMap),
            "preset_color_schemes": .map([scheme: .map(colors)]),
        ])
        return Theme(source: config, colorSchemeKey: "style/color_scheme")
    }

    static var squirrelDefaults: Theme {
        theme()
    }

    /// squirrel.yaml's aqua scheme.
    static var aqua: Theme {
        theme(scheme: "aqua", colors: [
            "text_color": "0x606060",
            "back_color": "0xeeeceeee",
            "candidate_text_color": "0x000000",
            "hilited_text_color": "0x000000",
            "hilited_candidate_text_color": "0xffffff",
            "hilited_candidate_back_color": "0xeefa3a0a",
            "comment_text_color": "0x5a5a5a",
            "hilited_comment_text_color": "0xfcac9d",
        ])
    }

    /// squirrel.yaml's lost_temple scheme.
    static var lostTemple: Theme {
        theme(scheme: "lost_temple", colors: [
            "text_color": "0xe8f3f6",
            "back_color": "0xee303030",
            "hilited_text_color": "0x82e6ca",
            "hilited_candidate_text_color": "0x000000",
            "hilited_candidate_back_color": "0x82e6ca",
            "comment_text_color": "0xbb82e6ca",
            "hilited_comment_text_color": "0xbb203d34",
        ])
    }

    /// The layout of Max's WeChat-like schemes: linear, PingFang SC 16 with
    /// 12-point labels, a green highlight.
    private static let wechatStyle: [String: ConfigNode] = [
        "candidate_list_layout": "linear",
        "border_width": "8",
        "border_height": "0",
        "corner_radius": "5",
        "inline_preedit": "true",
        "font_face": "PingFang SC",
        "font_point": "16",
        "label_font_point": "12",
    ]

    /// Colours other than the highlight are stand-ins until Max's
    /// configuration sample is in the fixtures.
    static var wechatLight: Theme {
        theme(scheme: "wechat_light", colors: [
            "back_color": "0xffffff",
            "text_color": "0x424242",
            "candidate_text_color": "0x000000",
            "hilited_candidate_text_color": "0xffffff",
            "hilited_candidate_back_color": "0x75b100",
            "label_color": "0x999999",
            "hilited_candidate_label_color": "0xffffff",
            "comment_text_color": "0x999999",
            "hilited_comment_text_color": "0xdcdcdc",
            "border_color": "0xe5e5e5",
        ], style: wechatStyle)
    }

    static var wechatDark: Theme {
        theme(scheme: "wechat_dark", colors: [
            "back_color": "0x2e2e2e",
            "text_color": "0xdcdcdc",
            "candidate_text_color": "0xe6e6e6",
            "hilited_candidate_text_color": "0xffffff",
            "hilited_candidate_back_color": "0x75b100",
            "label_color": "0x8c8c8c",
            "hilited_candidate_label_color": "0xffffff",
            "comment_text_color": "0x8c8c8c",
            "hilited_comment_text_color": "0xdcdcdc",
            "border_color": "0x3c3c3c",
        ], style: wechatStyle)
    }

    /// A colour as squirrel.yaml writes it: 0xBBGGRR or 0xAABBGGRR.
    static func color(_ squirrel: String) -> ThemeColor {
        .rgba(RGBAColor(squirrel: squirrel, colorSpace: .sRGB)!)
    }

    static func font(_ list: String, _ size: Double? = nil) -> ThemeFont {
        ThemeFont(faces: FontFace.list(squirrel: list), pointSize: size)
    }

    // MARK: Content

    static func entries(_ texts: [String], comments: [String?] = []) -> [CandidateSnapshot.Entry] {
        texts.enumerated().map { index, text in
            CandidateSnapshot.Entry(label: "\(index + 1)", text: text, comment: index < comments.count ? comments[index] : nil)
        }
    }

    /// A typical page: five candidates, some with comments.
    static var pinyinPage: CandidateSnapshot {
        CandidateSnapshot(
            entries: entries(["中书", "中枢", "钟书", "忠恕", "中"], comments: [nil, "zhōng shū", nil, "~shu", nil]),
            highlightedIndex: 0
        )
    }

    static func content(_ snapshot: CandidateSnapshot, preedit: String? = nil, selected: Range<Int>? = nil) -> PanelContent {
        var snapshot = snapshot
        if let preedit {
            let length = (preedit as NSString).length
            snapshot.preedit = Preedit(text: preedit, selectedRange: selected ?? 0..<length, caret: length)
        }
        return PanelContent(snapshot)
    }
}
