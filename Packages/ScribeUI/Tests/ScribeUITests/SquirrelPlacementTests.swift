import AppKit
import ScribeConfig
@testable import ScribeUI
import Testing

/// Where Scribe's window goes, against where Squirrel's own SquirrelPanel
/// put it for the same steps, as Tools/squirrel-oracle recorded in
/// Tests/Fixtures/snapshots/squirrel/placements.json.
@MainActor
@Suite(.serialized) struct SquirrelPlacementTests {
    struct Inputs: Decodable {
        struct Step: Decodable {
            var caret: [Double]?
            var content: SnapshotCases.ContentReference?
            var hide: Bool?
        }

        struct Case: Decodable {
            var name: String
            var style: [String: String]
            var steps: [Step]
        }

        var screen: [Double]
        var contents: [String: SnapshotCases.Content]
        var cases: [Case]
    }

    struct Recorded: Decodable {
        struct Step: Decodable {
            var frame: [Double]
            var view: [Double]
            var rotation: Double
        }

        var screen: [Double]
        var cases: [String: [Step?]]
    }

    nonisolated static let inputs: Inputs = load("Tests/Fixtures/snapshots/placements.json")
    nonisolated static let recorded: Recorded = load(Snapshot.referenceDirectory.appending(path: "placements.json"))

    private nonisolated static func load<T: Decodable>(_ path: String) -> T {
        load(Snapshot.repositoryRoot.appending(path: path))
    }

    private nonisolated static func load<T: Decodable>(_ url: URL) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Cannot read \(url.path): \(error)")
        }
    }

    /// Text is laid out by the same TextKit with the same fonts, so frames
    /// and sizes should agree to rounding error.
    static let tolerance: CGFloat = 0.001

    @Test(arguments: inputs.cases.map(\.name))
    func placesLikeSquirrel(_ name: String) throws {
        let input = try #require(Self.inputs.cases.first { $0.name == name })
        let expected = try #require(Self.recorded.cases[name], "No Squirrel placement; run Tools/squirrel-oracle/render.sh")
        #expect(Self.recorded.screen == Self.inputs.screen)
        let screen = CGRect(x: Self.inputs.screen[0], y: Self.inputs.screen[1], width: Self.inputs.screen[2], height: Self.inputs.screen[3])

        let panel = CandidatePanel()
        panel.appearance = Appearance(light: SnapshotCases.shared.theme(style: input.style), dark: nil)
        panel.palette = { _ in Fixtures.lightPalette }
        panel.systemAppearance = { Fixtures.light }
        panel.screenFrame = { _ in screen }
        defer { panel.hide() }

        try #require(expected.count == input.steps.count)
        for (index, (step, squirrel)) in zip(input.steps, expected).enumerated() {
            if step.hide == true {
                panel.hide()
                #expect(squirrel == nil)
                continue
            }
            let caret = try #require(step.caret)
            let reference = try #require(step.content)
            let snapshot = try #require(SnapshotCases.shared.content(reference, extra: Self.inputs.contents).snapshot)
            panel.show(snapshot, near: CGRect(x: caret[0], y: caret[1], width: caret[2], height: caret[3]))
            let squirrel = try #require(squirrel)
            let placement = try #require(panel.placement)
            let frame = placement.frame
            let viewSize = panel.view.frame.size
            let rotation = panel.contentView?.boundsRotation ?? 0
            let actual = [frame.minX, frame.minY, frame.width, frame.height]
            let close = zip(actual, squirrel.frame).allSatisfy { abs($0 - $1) <= Self.tolerance }
            #expect(close, "step \(index): frame \(actual) instead of Squirrel's \(squirrel.frame)")
            let viewClose = abs(viewSize.width - squirrel.view[0]) <= Self.tolerance && abs(viewSize.height - squirrel.view[1]) <= Self.tolerance
            #expect(viewClose, "step \(index): view \(viewSize) instead of Squirrel's \(squirrel.view)")
            #expect(abs(Double(rotation) - squirrel.rotation) <= Self.tolerance, "step \(index): rotation \(rotation) instead of Squirrel's \(squirrel.rotation)")
        }
    }
}
