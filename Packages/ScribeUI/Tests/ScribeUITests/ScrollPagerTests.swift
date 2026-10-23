import AppKit
import ScribeCore
@testable import ScribeUI
import Testing

@Suite struct ScrollPagerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func wheel(_ deltaY: CGFloat, at seconds: Double) -> ScrollPager.Event {
        ScrollPager.Event(phase: [], momentumPhase: [], deltaX: 0, deltaY: deltaY, time: start.addingTimeInterval(seconds))
    }

    private func gesture(_ phase: NSEvent.Phase, _ deltaX: CGFloat = 0, _ deltaY: CGFloat = 0, momentum: NSEvent.Phase = []) -> ScrollPager.Event {
        ScrollPager.Event(phase: phase, momentumPhase: momentum, deltaX: deltaX, deltaY: deltaY, time: start)
    }

    @Test func wheelClicksAddUpToAPage() {
        var pager = ScrollPager()
        #expect(pager.page(for: wheel(4, at: 0), vertical: false) == nil)
        #expect(pager.page(for: wheel(4, at: 0.1), vertical: false) == nil)
        #expect(pager.page(for: wheel(4, at: 0.2), vertical: false) == .up)
        #expect(pager.page(for: wheel(4, at: 0.3), vertical: false) == nil)
        // A click the other way only starts the count over.
        #expect(pager.page(for: wheel(-11, at: 0.4), vertical: false) == nil)
        #expect(pager.page(for: wheel(-11, at: 0.5), vertical: false) == .down)
    }

    @Test func wheelStartsOverAfterAPauseOrAReversal() {
        var pager = ScrollPager()
        _ = pager.page(for: wheel(8, at: 0), vertical: false)
        #expect(pager.page(for: wheel(8, at: 1.5), vertical: false) == nil)
        #expect(pager.page(for: wheel(-6, at: 1.6), vertical: false) == nil)
        #expect(pager.page(for: wheel(-6, at: 1.7), vertical: false) == nil)
        #expect(pager.page(for: wheel(-6, at: 1.8), vertical: false) == .down)
    }

    @Test func trackpadPagesWhenTheGestureEnds() {
        var pager = ScrollPager()
        #expect(pager.page(for: gesture(.began), vertical: false) == nil)
        #expect(pager.page(for: gesture(.changed, 1, -8), vertical: false) == nil)
        #expect(pager.page(for: gesture(.changed, 1, -8), vertical: false) == nil)
        #expect(pager.page(for: gesture(.ended), vertical: false) == .down)
        // The momentum that follows starts from nothing.
        #expect(pager.page(for: gesture([], 0, -30, momentum: .changed), vertical: false) == nil)
    }

    @Test func swipesPageBySideAndOrientation() {
        for (vertical, expected) in [(false, PageDirection.up), (true, .down)] {
            var pager = ScrollPager()
            _ = pager.page(for: gesture(.began), vertical: vertical)
            _ = pager.page(for: gesture(.changed, 20, 3), vertical: vertical)
            #expect(pager.page(for: gesture(.ended), vertical: vertical) == expected)
        }
    }

    @Test func shortGesturesDoNotPage() {
        var pager = ScrollPager()
        _ = pager.page(for: gesture(.began), vertical: false)
        _ = pager.page(for: gesture(.changed, 0, 9), vertical: false)
        #expect(pager.page(for: gesture(.ended), vertical: false) == nil)
    }
}
