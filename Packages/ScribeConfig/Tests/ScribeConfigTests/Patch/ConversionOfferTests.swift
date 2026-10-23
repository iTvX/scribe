import Foundation
import ScribeConfig
import Testing

struct ConversionOfferTests {
    static let conversion = ScribeConversion(
        entries: [
            .init(key: "keyboard_layout", value: "default"),
            .init(key: "notifications", value: "never"),
            .init(key: "appearance/theme", value: "wechat_light"),
            .init(key: "appearance/dark_theme", value: "aqua"),
            .init(key: "appearance/font/size", value: "16"),
            .init(key: "app_options/com.googlecode.iterm2", value: ["ascii_mode": "true", "no_inline": "false", "vim_mode": "yes"]),
            .init(key: "app_options/com.apple.Terminal", value: [:]),
            .init(key: "themes/wechat_light", value: [
                "name": "微信浅色",
                "light": ["background": "#FFFFFF", "candidate_text": "#000000"],
                "dark": ["background": "#000000"],
            ]),
            .init(key: "themes/x_y", value: ["light": ["background": "#123456"]]),
        ],
        themeIDs: ["wechat_light": "wechat_light", "x-y": "x_y"],
        unconverted: [.init(squirrelPath: "status_icon/show", scribePath: "status_icon", reason: .absentFromSquirrelConfig)]
    )

    @Test func groupsEntriesInTheConvertersOrder() {
        let offer = ConversionOffer(conversion: Self.conversion,
                                    themes: [ThemeInfo(id: "aqua", name: "碧水", author: nil, hasDark: false, origin: .squirrel)])
        #expect(offer.sections.map(\.group) == [.general, .appearance, .apps, .themes])
        #expect(offer.sections.map(\.group.title) == ["通用", "外观", "应用", "主题"])
        #expect(offer.sections.map { $0.rows.map(\.path) } == [
            ["keyboard_layout", "notifications"],
            ["appearance/theme", "appearance/dark_theme", "appearance/font/size"],
            ["app_options/com.googlecode.iterm2", "app_options/com.apple.Terminal"],
            ["themes/wechat_light", "themes/x_y"],
        ])
        #expect(offer.sections.flatMap(\.rows).map(\.value) == [
            "default", "never",
            "微信浅色（wechat_light）", "碧水（aqua）", "16",
            "ascii_mode 开、no_inline 关、vim_mode yes", "不再使用中书默认给这个应用的设置",
            "微信浅色 · 3 种颜色", "x_y · 1 种颜色",
        ])
        #expect([ConversionOffer.Group.general, .appearance, .apps, .themes].map(offer.count) == [2, 3, 2, 2])
        #expect(offer.unconverted == ["status_icon/show"])
    }

    @Test func notesRenamedThemes() {
        let rows = ConversionOffer(conversion: Self.conversion).sections.flatMap(\.rows)
        #expect(rows.first { $0.path == "themes/x_y" }?.note == "鼠须管里叫 x-y")
        #expect(rows.first { $0.path == "themes/wechat_light" }?.note == nil)
        #expect(rows.filter { $0.note != nil }.count == 1)
    }

    @Test func leavesOutEmptyGroups() {
        let offer = ConversionOffer(conversion: ScribeConversion(entries: [.init(key: "themes/a", value: ["name": "A"])]))
        #expect(offer.sections.map(\.group) == [.themes])
        #expect(offer.sections[0].rows[0].value == "A · 0 种颜色")
    }

    @Test func refusesWhileEditsArePending() {
        #expect(ConversionOffer.unavailableReason(conversion: Self.conversion, hasEdits: false, readOnlyReason: nil) == nil)
        #expect(ConversionOffer.unavailableReason(conversion: Self.conversion, hasEdits: true, readOnlyReason: nil)
                == "先保存或还原未保存的修改")
        #expect(ConversionOffer.unavailableReason(conversion: Self.conversion, hasEdits: true, readOnlyReason: "找不到中书")
                == "找不到中书")
        #expect(ConversionOffer.unavailableReason(conversion: ScribeConversion(), hasEdits: false, readOnlyReason: nil) != nil)
        #expect(ConversionOffer.unavailableReason(conversion: nil, hasEdits: false, readOnlyReason: nil) != nil)
    }
}
