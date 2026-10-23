import AppKit
import ScribeConfig
import ScribeCore
@testable import ScribeUI
import Testing

@MainActor
@Suite struct PanelRendererTests {
    private func render(_ theme: Theme, _ content: PanelContent = Fixtures.content(Fixtures.pinyinPage), screen: CGRect = PanelRenderer.referenceScreen) -> CGImage? {
        PanelRenderer.render(content, theme: PanelTheme(theme, palette: Fixtures.lightPalette), appearance: Fixtures.light, screen: screen)
    }

    @Test func nothingToShowRendersNothing() {
        #expect(render(Fixtures.squirrelDefaults, PanelContent(nil)) == nil)
        #expect(render(Fixtures.squirrelDefaults, PanelContent(CandidateSnapshot(entries: []))) == nil)
    }

    @Test func themeColoursKeepTheirValues() throws {
        let image = try #require(render(Fixtures.wechatLight))
        // Inside the green highlight, on the background, outside the panel.
        #expect(Snapshot.pixel(of: image, x: 6, y: 4) == [0x00, 0xB1, 0x75, 0xFF])
        #expect(Snapshot.pixel(of: image, x: CGFloat(image.width) / 4, y: 2) == [0xFF, 0xFF, 0xFF, 0xFF])
        let rounded = try #require(render(Fixtures.aqua))
        #expect(Snapshot.pixel(of: rounded, x: 0, y: 0)[3] == 0)
    }

    @Test func imagesAreTwicePointSize() throws {
        let theme = PanelTheme(Fixtures.squirrelDefaults, palette: Fixtures.lightPalette)
        let text = try #require(PanelText(Fixtures.content(Fixtures.pinyinPage), theme: theme))
        let sizing = PanelView().update(text, theme: theme, screen: PanelRenderer.referenceScreen)
        let image = try #require(render(Fixtures.squirrelDefaults))
        #expect(image.width == Int((sizing.size.width * 2).rounded(.up)))
        #expect(image.height == Int((sizing.size.height * 2).rounded(.up)))
    }

    @Test func verticalPanelsTurnClockwise() throws {
        var vertical = Fixtures.squirrelDefaults
        vertical.orientation = .vertical
        let image = try #require(render(vertical))
        // The highlighted first row runs down the right edge.
        let topRight = Snapshot.pixel(of: image, x: CGFloat(image.width) / 2 - 6, y: 12)
        #expect(topRight == [0xB3, 0xD7, 0xFF, 0xFF])
        let topLeft = Snapshot.pixel(of: image, x: 6, y: 12)
        #expect(topLeft == [0xFF, 0xFF, 0xFF, 0xFF])
    }

    @Test func rendersAreRepeatable() throws {
        let first = try #require(render(Fixtures.lostTemple))
        let second = try #require(render(Fixtures.lostTemple))
        #expect(Snapshot.pixels(of: first) == Snapshot.pixels(of: second))
    }

    @Test func oversizedPanelsAreScaledDown() throws {
        let entries = Fixtures.entries((1...9).map { String(repeating: "长", count: $0 * 6) })
        let screen = CGRect(x: 0, y: 0, width: 300, height: 200)
        let image = try #require(render(Fixtures.squirrelDefaults, Fixtures.content(CandidateSnapshot(entries: entries)), screen: screen))
        // 95% of the screen at 2×, give or take rounding up to whole pixels.
        #expect(image.width <= 571)
        #expect(image.height <= 381)
        #expect(image.width >= 569 || image.height >= 379)
    }

    @Test func rotationMovesTheTopRowToTheRight() throws {
        // A 3×2 image, rows top first: a b c / d e f.
        let context = try #require(CGContext(
            data: nil, width: 3, height: 2, bitsPerComponent: 8, bytesPerRow: 12,
            space: PanelRenderer.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for index in 0..<6 {
            pixels[index * 4] = UInt8(index + 1)
            pixels[index * 4 + 3] = 255
        }
        let rotated = try #require(PanelRenderer.rotatedClockwise(context))
        #expect((rotated.width, rotated.height) == (2, 3))
        // Now d a / e b / f c.
        let reds = stride(from: 0, to: 24, by: 4).map { Snapshot.pixels(of: rotated)[$0] }
        #expect(reds == [4, 1, 5, 2, 6, 3])
    }
}
