import AppKit
import ScribeConfig
import ScribeCore
@testable import ScribeUI

/// Themes, palettes and content for rendering tests. Themes come from
/// `cases.json`, written as squirrel.yaml would write them and read by
/// ScribeConfig, so Squirrel's fallbacks come from the same code the app
/// uses.
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

    /// squirrel.yaml's `style` defaults, with the font pinned to faces every
    /// Mac has, as in `cases.json`.
    static var squirrelDefaults: Theme {
        SnapshotCases.shared.theme()
    }

    /// squirrel.yaml's aqua scheme.
    static var aqua: Theme {
        SnapshotCases.shared.theme(scheme: "aqua")
    }

    /// squirrel.yaml's lost_temple scheme.
    static var lostTemple: Theme {
        SnapshotCases.shared.theme(scheme: "lost_temple")
    }

    /// Max's WeChat-like schemes: linear, PingFang SC 16 with 12-point
    /// labels, a green highlight. Colours other than the highlight are
    /// stand-ins until the real configuration sample is in the fixtures.
    static var wechatLight: Theme {
        SnapshotCases.shared.theme(scheme: "wechat_light")
    }

    static var wechatDark: Theme {
        SnapshotCases.shared.theme(scheme: "wechat_dark")
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
