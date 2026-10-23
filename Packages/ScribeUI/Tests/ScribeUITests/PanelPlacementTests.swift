import CoreGraphics
@testable import ScribeUI
import Testing

@Suite struct PanelPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let inset = CGSize(width: 5, height: 6)

    private func input(caret: CGRect, size: CGSize = CGSize(width: 220, height: 112), vertical: Bool = false) -> PanelPlacement.Input {
        PanelPlacement.Input(
            caret: caret,
            screen: screen,
            size: size,
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            isOversized: false,
            preeditHeight: nil,
            vertical: vertical,
            memorizeSize: true,
            edgeInset: inset,
            pagingOffset: 10
        )
    }

    @Test func linesGetLongerWithTheFont() {
        let horizontal = PanelPlacement.maxTextWidth(fontSize: 16, vertical: false, edgeInset: inset, screen: screen)
        #expect(abs(horizontal - (1440 * 4 / 9 - 10)) < 1e-9)
        let vertical = PanelPlacement.maxTextWidth(fontSize: 16, vertical: true, edgeInset: inset, screen: screen)
        #expect(abs(vertical - (900 * (1.0 / 4 + 1.0 / 9) - 12)) < 1e-9)
        #expect(PanelPlacement.maxTextWidth(fontSize: 120, vertical: false, edgeInset: inset, screen: screen) == 1430)
    }

    @Test func naturalSizeAddsInsetsAndPaging() {
        let content = CGRect(x: 0, y: 0, width: 200, height: 100)
        #expect(PanelPlacement.naturalSize(contentRect: content, edgeInset: inset, pagingOffset: 10, vertical: false) == CGSize(width: 220, height: 112))
        #expect(PanelPlacement.naturalSize(contentRect: content, edgeInset: inset, pagingOffset: 10, vertical: true) == CGSize(width: 112, height: 220))
    }

    @Test func belowTheCaretWithLabelsAligned() {
        let placement = PanelPlacement.place(input(caret: CGRect(x: 100, y: 500, width: 2, height: 18)))
        #expect(placement.frame == CGRect(x: 90, y: 383, width: 220, height: 112))
        #expect(placement.size == CGSize(width: 220, height: 112))
    }

    @Test func aboveTheCaretAtTheBottomOfTheScreen() {
        let placement = PanelPlacement.place(input(caret: CGRect(x: 100, y: 50, width: 2, height: 18)))
        #expect(placement.frame.origin.y == 73)
    }

    @Test func keptInsideTheScreenSideways() {
        #expect(PanelPlacement.place(input(caret: CGRect(x: 1400, y: 500, width: 2, height: 18))).frame.origin.x == 1220)
        #expect(PanelPlacement.place(input(caret: CGRect(x: 5, y: 500, width: 2, height: 18))).frame.origin.x == 0)
        #expect(PanelPlacement.place(input(caret: CGRect(x: 100, y: 1000, width: 2, height: 18))).frame.maxY == 900)
    }

    @Test func verticalPanelsGoLeftOfTheCaret() {
        let size = CGSize(width: 112, height: 220)
        var upper = input(caret: CGRect(x: 700, y: 600, width: 2, height: 18), size: size, vertical: true)
        #expect(PanelPlacement.place(upper).frame == CGRect(x: 583, y: 385, width: 112, height: 220))
        upper.preeditHeight = 20
        #expect(PanelPlacement.place(upper).frame.origin.x == 608)

        let lower = input(caret: CGRect(x: 700, y: 100, width: 2, height: 18), size: size, vertical: true)
        #expect(PanelPlacement.place(lower).frame.origin.y == 123)
    }

    @Test func verticalPanelsKeepTheirLongestLength() {
        var lower = input(caret: CGRect(x: 700, y: 100, width: 2, height: 18), size: CGSize(width: 112, height: 220), vertical: true)
        let first = PanelPlacement.place(lower)
        #expect(first.memorizedLength == 200)

        lower.contentRect.size.width = 150
        lower.size.height = 170
        lower.memorizedLength = first.memorizedLength
        let second = PanelPlacement.place(lower)
        #expect(second.size == CGSize(width: 112, height: 220))
        #expect(second.memorizedLength == 200)

        lower.memorizeSize = false
        #expect(PanelPlacement.place(lower).size.height == 170)
    }

    @Test func oversizedPanelsShrinkToTheScreenCentre() {
        let size = CGSize(width: 2000, height: 100)
        #expect(PanelPlacement.isOversized(size, screen: screen))
        #expect(!PanelPlacement.isOversized(CGSize(width: 1368, height: 855), screen: screen))
        var oversized = input(caret: CGRect(x: 100, y: 500, width: 2, height: 18), size: size)
        oversized.isOversized = true
        oversized.memorizedLength = 300
        let placement = PanelPlacement.place(oversized)
        #expect(abs(placement.frame.width - 1368) < 1e-9)
        #expect(abs(placement.frame.height - 68.4) < 1e-9)
        #expect(abs(placement.frame.midX - 720) < 1e-9)
        #expect(abs(placement.frame.midY - 450) < 1e-9)
        #expect(placement.size == size)
        #expect(placement.memorizedLength == 0)
    }

    @Test func oversizedTextTakesTheScreenProportions() {
        let content = CGRect(x: 0, y: 0, width: 400, height: 1000)
        let width = PanelPlacement.oversizedTextWidth(contentRect: content, vertical: false, screen: screen)
        #expect(abs(width - (400_000 * 1.6).squareRoot()) < 1e-9)
        let vertical = PanelPlacement.oversizedTextWidth(contentRect: content, vertical: true, screen: screen)
        #expect(abs(vertical - (400_000 / 1.6).squareRoot()) < 1e-9)
    }
}
