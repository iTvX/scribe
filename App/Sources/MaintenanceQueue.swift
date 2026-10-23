/// What the queue needs from librime.
@MainActor
protocol MaintenanceEngine: AnyObject {
    var isInMaintenance: Bool { get }
    /// Restarts librime and starts a full deployment.
    func reload()
    /// Starts syncing user data; false if librime refused.
    func startSync() -> Bool
}

/// Runs reloads and syncs one at a time, in the order requested.
///
/// librime refuses to start maintenance while another is running, so a sync
/// that arrives during a deployment, as when the settings app asks for a
/// reload followed by a sync, waits here instead of being dropped. Call
/// `resume()` whenever maintenance may have finished.
@MainActor
final class MaintenanceQueue {
    enum Task: Equatable {
        case reload
        case sync
    }

    private(set) var pending: [Task] = []
    private let engine: MaintenanceEngine

    init(engine: MaintenanceEngine) {
        self.engine = engine
    }

    func enqueue(_ task: Task) {
        if !pending.contains(task) {
            pending.append(task)
        }
        resume()
    }

    /// Starts the next task if librime is idle.
    func resume() {
        guard !engine.isInMaintenance, !pending.isEmpty else { return }
        switch pending.removeFirst() {
        case .reload:
            engine.reload()
        case .sync:
            if !engine.startSync() {
                Log.app.error("Could not start syncing user data")
            }
        }
    }
}
