import Foundation
import ScribeCore

/// Releases chord keys from the main run loop.
@MainActor
final class RunLoopChordTimer: ChordTimer {
    private var timer: Timer?

    func start(after interval: TimeInterval, _ fire: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            MainActor.assumeIsolated {
                fire()
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
