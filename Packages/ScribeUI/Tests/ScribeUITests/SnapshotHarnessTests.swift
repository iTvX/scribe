import AppKit
import ScribeConfig
@testable import ScribeUI
import Testing

/// The comparison must be tight enough to catch real changes.
@MainActor
@Suite struct SnapshotHarnessTests {
    private func render(_ change: (inout Theme) -> Void = { _ in }) throws -> CGImage {
        var theme = Fixtures.wechatLight
        change(&theme)
        let panelTheme = PanelTheme(theme, palette: Fixtures.lightPalette)
        return try #require(PanelRenderer.render(Fixtures.content(Fixtures.pinyinPage), theme: panelTheme, appearance: Fixtures.light))
    }

    @Test func identicalRendersMatch() throws {
        #expect(Snapshot.Comparison(expected: try render(), actual: try render()).matches)
    }

    @Test func contentMovedOnePointFails() throws {
        let expected = try render()
        // Everything one point (two pixels) to the right.
        let pixels = Snapshot.pixels(of: expected)
        var moved = [UInt8](repeating: 0, count: pixels.count)
        for row in 0..<expected.height {
            let start = row * expected.width * 4
            moved[(start + 8)..<(start + expected.width * 4)] = pixels[start..<(start + expected.width * 4 - 8)]
        }
        let actual = try #require(Snapshot.image(from: moved, width: expected.width, height: expected.height))
        let comparison = Snapshot.Comparison(expected: expected, actual: actual)
        #expect(comparison.sizesMatch)
        #expect(!comparison.matches, "\(comparison)")
    }

    @Test func labelsOnePointSmallerFail() throws {
        let comparison = Snapshot.Comparison(expected: try render(), actual: try render { $0.labelFont.pointSize = 11 })
        #expect(!comparison.matches, "\(comparison)")
    }

    @Test func panelOnePointWiderFails() throws {
        let comparison = Snapshot.Comparison(expected: try render(), actual: try render { $0.borderWidth += 1 })
        #expect(!comparison.matches, "\(comparison)")
        #expect(!comparison.sizesMatch)
    }

    @Test func highlightOnePointRounderFails() throws {
        let comparison = Snapshot.Comparison(expected: try render(), actual: try render { $0.hilitedCornerRadius = 1 })
        #expect(comparison.sizesMatch)
        #expect(!comparison.matches, "\(comparison)")
    }

    @Test func wrongColourFails() throws {
        let comparison = Snapshot.Comparison(expected: try render(), actual: try render {
            $0.colors.hilitedCandidateBackground = Fixtures.color("0x75a800")
        })
        #expect(comparison.sizesMatch)
        #expect(!comparison.matches, "\(comparison)")
        #expect(comparison.largestChannelDifference == 9)
    }

    @Test func strayAntialiasingPasses() throws {
        let expected = try render()
        var pixels = Snapshot.pixels(of: expected)
        for pixel in stride(from: 0, to: 20 * 4, by: 4) {
            pixels[pixel] = pixels[pixel] &+ 60
        }
        let actual = try #require(Snapshot.image(from: pixels, width: expected.width, height: expected.height))
        let comparison = Snapshot.Comparison(expected: expected, actual: actual)
        #expect(comparison.matches, "\(comparison)")
    }
}
