import AppKit
import ScribeConfig
import ScribeCore
@testable import ScribeUI
import Testing

/// One rendered panel compared with its baseline.
struct SnapshotCase: Sendable, CustomTestStringConvertible {
    var name: String
    var theme: Theme
    var content: PanelContent
    var dark = false

    var testDescription: String {
        name
    }

    @MainActor
    func render() -> CGImage? {
        let theme = PanelTheme(theme, palette: dark ? Fixtures.darkPalette : Fixtures.lightPalette)
        return PanelRenderer.render(content, theme: theme, appearance: dark ? Fixtures.dark : Fixtures.light)
    }
}

/// Builds a case from the defaults with `change` applied.
private func variant(_ name: String, _ base: Theme = Fixtures.squirrelDefaults, content: PanelContent = Fixtures.content(Fixtures.pinyinPage), dark: Bool = false, _ change: (inout Theme) -> Void = { _ in }) -> SnapshotCase {
    var theme = base
    change(&theme)
    return SnapshotCase(name: name, theme: theme, content: content, dark: dark)
}

private let layoutCases: [SnapshotCase] = [CandidateListLayout.stacked, .linear].flatMap { layout in
    [TextOrientation.horizontal, .vertical].flatMap { orientation in
        [false, true].map { dark in
            variant("\(layout)-\(orientation)-\(dark ? "dark" : "light")", dark: dark) {
                $0.layout = layout
                $0.orientation = orientation
            }
        }
    }
}

private let schemeCases: [SnapshotCase] = [
    variant("aqua", Fixtures.aqua),
    variant("lost_temple", Fixtures.lostTemple),
    variant("wechat_light", Fixtures.wechatLight),
    variant("wechat_dark", Fixtures.wechatDark, dark: true),
]

/// A light scheme that draws every kind of background, for features that
/// need them.
private var backgrounds: Theme {
    var theme = Fixtures.aqua
    theme.inlinePreedit = false
    theme.colors.preeditBackground = Fixtures.color("0xf4f4f4")
    theme.colors.hilitedPreeditBackground = Fixtures.color("0xffd8c0")
    theme.colors.candidateBackground = Fixtures.color("0xffffff")
    return theme
}

private let preedit = Fixtures.content(Fixtures.pinyinPage, preedit: "zhong shu ji", selected: 6..<12)

private let longCandidate = String(repeating: "天地玄黄宇宙洪荒日月盈昃辰宿列张", count: 4)

private let featureCases: [SnapshotCase] = [
    variant("preedit-stacked", backgrounds, content: preedit),
    variant("preedit-linear", backgrounds, content: preedit) { $0.layout = .linear },
    variant("preedit-vertical", backgrounds, content: preedit) { $0.orientation = .vertical },
    variant("preedit-only", backgrounds, content: Fixtures.content(CandidateSnapshot(entries: []), preedit: "zhong", selected: 0..<5)),
    variant("preedit-native", content: preedit) { $0.inlinePreedit = false },
    // An app with Squirrel's no_inline option on a theme with inline_preedit.
    variant("preedit-inline-theme", content: preedit),
    variant("wrap-stacked", content: Fixtures.content(CandidateSnapshot(entries: Fixtures.entries([longCandidate, "中书"]), highlightedIndex: 0))),
    variant(
        "wrap-linear",
        content: Fixtures.content(CandidateSnapshot(
            entries: Fixtures.entries(["千字文开篇", String(longCandidate.prefix(20)), "宇宙洪荒", String(longCandidate.prefix(30)), "辰宿列张"]),
            highlightedIndex: 3
        ))
    ) { $0.layout = .linear },
    variant("rare-characters", content: Fixtures.content(CandidateSnapshot(entries: Fixtures.entries(["𠀾", "𪚥", "𰻞𰻞面", "中"], comments: [nil, "zhé"]), highlightedIndex: 2))),
    variant(
        "nine-candidates",
        content: Fixtures.content(CandidateSnapshot(
            entries: Fixtures.entries(["是", "时", "事", "市", "使", "十", "式", "师", "试"], comments: ["shì", nil, nil, "shì", nil, "shí", nil, nil, "shì"]),
            highlightedIndex: 4
        ))
    ),
    variant("paging-stacked", content: Fixtures.content(CandidateSnapshot(entries: Fixtures.pinyinPage.entries, pageNumber: 1, isLastPage: false))) {
        $0.showPaging = true
    },
    variant("paging-linear-vertical", content: Fixtures.content(CandidateSnapshot(entries: Fixtures.pinyinPage.entries, pageNumber: 0, isLastPage: false))) {
        $0.showPaging = true
        $0.layout = .linear
        $0.orientation = .vertical
    },
    variant("border", Fixtures.aqua) {
        $0.borderWidth = 4
        $0.borderHeight = 4
        $0.colors.border = Fixtures.color("0xffa0a0a0")
    },
    variant("translucent", content: preedit) { $0 = translucent($0, mutualExclusive: false) },
    variant("mutual-exclusive", content: preedit) { $0 = translucent($0, mutualExclusive: true) },
    variant("shadow-stacked", Fixtures.aqua) {
        $0.shadowSize = 6
        $0.hilitedCornerRadius = 6
    },
    variant("shadow-linear", Fixtures.aqua) {
        $0.shadowSize = 6
        $0.hilitedCornerRadius = 6
        $0.layout = .linear
    },
    variant("expansion-stacked", backgrounds) {
        $0.surroundingExtraExpansion = 2
        $0.hilitedCornerRadius = 4
    },
    variant("expansion-linear", backgrounds) {
        $0.surroundingExtraExpansion = -2
        $0.hilitedCornerRadius = 4
        $0.layout = .linear
    },
    variant("hilited-corner-stacked", Fixtures.aqua) { $0.hilitedCornerRadius = 8 },
    variant("hilited-corner-linear", Fixtures.aqua) {
        $0.hilitedCornerRadius = 8
        $0.layout = .linear
    },
    variant("format-four-per-em-space") { $0.candidateFormat = CandidateFormat("[label]\u{2005}[candidate]\u{2005}[comment]") },
    variant("format-without-label") { $0.candidateFormat = CandidateFormat("[candidate] [comment]") },
    variant(
        "accent-warning-comments",
        Fixtures.lostTemple,
        content: PanelContent(Fixtures.pinyinPage, accentCommentIndices: [1, 3], warningCommentIndices: [3, 4])
    ) {
        $0.colors.accentText = Fixtures.color("0x3c9cff")
        $0.colors.warningText = Fixtures.color("0x3030ff")
    },
    variant("accent-without-colour", Fixtures.lostTemple, content: PanelContent(Fixtures.pinyinPage, accentCommentIndices: [1])),
    variant("base-offset", Fixtures.aqua) { $0.baseOffset = 3 },
    variant("alpha", Fixtures.aqua) { $0.alpha = 0.6 },
    variant("status-message", content: PanelContent(nil, statusMessage: "中文")),
    variant("status-message-vertical", content: PanelContent(nil, statusMessage: "ABC")) { $0.orientation = .vertical },
]

/// Translucent colours that overlap unless `mutual_exclusive` is on.
private func translucent(_ theme: Theme, mutualExclusive: Bool) -> Theme {
    var theme = theme
    theme.isNative = false
    theme.inlinePreedit = false
    theme.mutualExclusive = mutualExclusive
    theme.translucency = true
    theme.hilitedCornerRadius = 4
    theme.colors.background = Fixtures.color("0x80ffffff")
    theme.colors.preeditBackground = Fixtures.color("0x40ff0000")
    theme.colors.hilitedPreeditBackground = Fixtures.color("0x6000c0ff")
    theme.colors.candidateBackground = Fixtures.color("0x30000000")
    theme.colors.hilitedCandidateBackground = Fixtures.color("0x80fa3a0a")
    theme.surroundingExtraExpansion = 1
    return theme
}

@MainActor
@Suite struct PanelSnapshotTests {
    @Test(arguments: layoutCases)
    func layout(_ snapshot: SnapshotCase) {
        Snapshot.check(snapshot.render(), suite: "layout", name: snapshot.name)
    }

    @Test(arguments: schemeCases)
    func scheme(_ snapshot: SnapshotCase) {
        Snapshot.check(snapshot.render(), suite: "schemes", name: snapshot.name)
    }

    @Test(arguments: featureCases)
    func feature(_ snapshot: SnapshotCase) {
        Snapshot.check(snapshot.render(), suite: "features", name: snapshot.name)
    }
}
