import AppKit
import ScribeConfig
@testable import ScribeUI
import Testing

/// One case of `cases.json`, resolved for rendering.
struct SnapshotCase: Sendable, CustomTestStringConvertible {
    var suite: String
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

@MainActor
@Suite struct PanelSnapshotTests {
    @Test(arguments: SnapshotCases.shared.cases(in: "layout"))
    func layout(_ snapshot: SnapshotCase) {
        Snapshot.check(snapshot.render(), suite: snapshot.suite, name: snapshot.name)
    }

    @Test(arguments: SnapshotCases.shared.cases(in: "schemes"))
    func scheme(_ snapshot: SnapshotCase) {
        Snapshot.check(snapshot.render(), suite: snapshot.suite, name: snapshot.name)
    }

    @Test(arguments: SnapshotCases.shared.cases(in: "features"))
    func feature(_ snapshot: SnapshotCase) {
        Snapshot.check(snapshot.render(), suite: snapshot.suite, name: snapshot.name)
    }

    /// Every preset of SharedSupport/squirrel.yaml.
    @Test(arguments: SnapshotCases.shared.cases(in: "presets"))
    func preset(_ snapshot: SnapshotCase) {
        Snapshot.check(snapshot.render(), suite: snapshot.suite, name: snapshot.name)
    }

    /// A deployed configuration in Max's style.
    @Test(arguments: SnapshotCases.shared.cases(in: "max-sample"))
    func maxSample(_ snapshot: SnapshotCase) {
        Snapshot.check(snapshot.render(), suite: snapshot.suite, name: snapshot.name)
    }
}
