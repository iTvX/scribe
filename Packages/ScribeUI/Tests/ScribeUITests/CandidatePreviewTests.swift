import AppKit
import ScribeConfig
import ScribeCore
import Testing

@testable import ScribeUI

@MainActor struct CandidatePreviewTests {
    @Test func preservesRetinaPointSizeAndThemeColors() throws {
        let image = try #require(CandidatePreview.render(Fixtures.pinyinPage, theme: Fixtures.wechatLight, isDark: false))
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(CGFloat(cg.width) == image.size.width * 2)
        #expect(CGFloat(cg.height) == image.size.height * 2)
        #expect(Snapshot.pixel(of: cg, x: 6, y: 4) == [0x00, 0xB1, 0x75, 0xFF])
    }

    @Test func supportsVerticalPreviewWithoutAWindow() throws {
        var theme = Fixtures.wechatLight
        theme.orientation = .vertical
        let image = try #require(CandidatePreview.render(Fixtures.pinyinPage, theme: theme, isDark: false))
        #expect(image.size.height > image.size.width)
    }

    @Test func ignoresEmptyContentAndInvalidScale() {
        #expect(CandidatePreview.render(.init(entries: []), theme: Theme(), isDark: false) == nil)
        #expect(CandidatePreview.render(Fixtures.pinyinPage, theme: Theme(), isDark: false, scale: 0) == nil)
    }
}
