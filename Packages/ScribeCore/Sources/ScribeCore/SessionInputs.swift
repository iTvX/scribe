import Foundation

/// Which way the candidate window asks to move the caret in the input.
public enum CaretMove: Equatable, Sendable {
    case towardStart
    case towardEnd
}

public enum PageDirection: Equatable, Sendable {
    case up
    case down
}

/// Schedules the release of chord keys. The app uses a run-loop timer; tests
/// fire it by hand.
@MainActor
public protocol ChordTimer: AnyObject {
    /// Replaces any pending firing.
    func start(after interval: TimeInterval, _ fire: @escaping @MainActor () -> Void)
    func cancel()
}

/// A chord timer that fires only when told to.
@MainActor
public final class ManualChordTimer: ChordTimer {
    private var pending: (@MainActor () -> Void)?

    public init() {}

    public var isPending: Bool {
        pending != nil
    }

    public func start(after interval: TimeInterval, _ fire: @escaping @MainActor () -> Void) {
        pending = fire
    }

    public func cancel() {
        pending = nil
    }

    /// Fires the pending timer, if any.
    public func fire() {
        let fire = pending
        pending = nil
        fire?()
    }
}
