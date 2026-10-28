import AppKit
import ScribeConfig
@testable import ScribeUI
import Testing

/// Scribe's panel against Squirrel's own code drawing the same case, from
/// the references Tools/squirrel-oracle renders into
/// Tests/Fixtures/snapshots/squirrel.
@MainActor
@Suite struct SquirrelReferenceTests {
    /// The screen the references were laid out for; line lengths depend
    /// on it.
    private nonisolated static let screen: CGRect = {
        struct Size: Decodable {
            var width: Double
            var height: Double
        }
        let url = Snapshot.referenceDirectory.appending(path: "screen.json")
        guard let data = try? Data(contentsOf: url), let size = try? JSONDecoder().decode(Size.self, from: data) else {
            return PanelRenderer.referenceScreen
        }
        return CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }()

    /// Pixels may differ by anti-aliasing: up to 32/255 per channel, or
    /// matching a neighbouring pixel. A few may still differ where curves
    /// meet straight edges.
    static let channelTolerance = 32
    static let maxDifferingFraction = 0.002
    static let maxDifferingPixels = 64
    /// Known difference: TextKit snaps Squirrel's text layers to the
    /// window's pixel grid, and a vertical panel sits a fraction of a point
    /// off that grid, so its glyphs land up to a third of a point from
    /// Scribe's (docs/decisions/0007).
    static let verticalMaxDifferingFraction = 0.03

    @Test(arguments: SnapshotCases.shared.suites.keys.sorted().flatMap { SnapshotCases.shared.cases(in: $0) })
    func matchesSquirrel(_ snapshot: SnapshotCase) throws {
        let reference = Snapshot.referenceDirectory.appending(path: "\(snapshot.suite)/\(snapshot.name).png")
        let expected = try #require(Snapshot.read(reference), "No Squirrel reference; run Tools/squirrel-oracle/render.sh")
        let theme = PanelTheme(snapshot.theme, palette: snapshot.dark ? Fixtures.darkPalette : Fixtures.lightPalette)
        let actual = try #require(PanelRenderer.render(snapshot.content, theme: theme, appearance: snapshot.dark ? Fixtures.dark : Fixtures.light, screen: Self.screen))
        Snapshot.compare(
            actual,
            with: expected,
            suite: "squirrel/\(snapshot.suite)",
            name: snapshot.name,
            channelTolerance: Self.channelTolerance,
            neighborhood: 1,
            maxDifferingFraction: theme.vertical ? Self.verticalMaxDifferingFraction : Self.maxDifferingFraction,
            maxDifferingPixels: Self.maxDifferingPixels
        )
    }
}
