import AppKit
import ScribeCore

/// Turns scroll wheel and trackpad scrolling over the panel into page
/// requests, with Squirrel's thresholds.
///
/// A wheel pages once its clicks in one direction add up to more than 10
/// points; a pause of over a second starts the count again. A trackpad
/// gesture pages when it ends, by its dominant direction: vertical scrolling
/// up pages up, horizontal swiping right pages up for vertical text and
/// down otherwise.
struct ScrollPager {
    struct Event {
        var phase: NSEvent.Phase
        var momentumPhase: NSEvent.Phase
        var deltaX: CGFloat
        var deltaY: CGFloat
        var time: Date
    }

    private var distance = CGVector.zero
    private var lastWheelTime = Date.distantPast

    mutating func page(for event: Event, vertical: Bool) -> PageDirection? {
        if event.phase == .began {
            distance = .zero
            return nil
        }
        if event.phase == .ended || (event.phase.isEmpty && !event.momentumPhase.isEmpty) {
            defer { distance = .zero }
            if abs(distance.dx) > abs(distance.dy) && abs(distance.dx) > 10 {
                return (distance.dx < 0) == vertical ? .up : .down
            }
            if abs(distance.dx) < abs(distance.dy) && abs(distance.dy) > 10 {
                return distance.dy > 0 ? .up : .down
            }
            return nil
        }
        if event.phase.isEmpty && event.momentumPhase.isEmpty {
            // A mouse wheel, which reports no phases.
            if event.time.timeIntervalSince(lastWheelTime) > 1 {
                distance = .zero
            }
            lastWheelTime = event.time
            if (distance.dy >= 0 && event.deltaY > 0) || (distance.dy <= 0 && event.deltaY < 0) {
                distance.dy += event.deltaY
            } else {
                distance = .zero
            }
            if abs(distance.dy) > 10 {
                defer { distance = .zero }
                return distance.dy > 0 ? .up : .down
            }
            return nil
        }
        distance.dx += event.deltaX
        distance.dy += event.deltaY
        return nil
    }
}

extension ScrollPager.Event {
    init(_ event: NSEvent) {
        self.init(
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            time: Date()
        )
    }
}
