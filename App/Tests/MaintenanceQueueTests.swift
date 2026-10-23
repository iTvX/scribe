import Testing

@MainActor
final class FakeMaintenanceEngine: MaintenanceEngine {
    var isInMaintenance = false
    var log: [String] = []

    func reload() {
        log.append("reload")
        isInMaintenance = true
    }

    func startSync() -> Bool {
        log.append("sync")
        isInMaintenance = true
        return true
    }
}

@MainActor
@Suite struct MaintenanceQueueTests {
    let engine = FakeMaintenanceEngine()
    let queue: MaintenanceQueue

    init() {
        queue = MaintenanceQueue(engine: engine)
    }

    @Test func runsAtOnceWhenIdle() {
        queue.enqueue(.sync)
        #expect(engine.log == ["sync"])
        #expect(queue.pending.isEmpty)
    }

    @Test func syncRightAfterReloadWaitsForTheDeploy() {
        queue.enqueue(.reload)
        queue.enqueue(.sync)
        #expect(engine.log == ["reload"])
        #expect(queue.pending == [.sync])

        queue.resume()  // still deploying
        #expect(engine.log == ["reload"])

        engine.isInMaintenance = false
        queue.resume()
        #expect(engine.log == ["reload", "sync"])
        #expect(queue.pending.isEmpty)
    }

    @Test func waitsForMaintenanceAlreadyRunning() {
        engine.isInMaintenance = true  // as during the deploy at launch
        queue.enqueue(.reload)
        #expect(engine.log.isEmpty)
        engine.isInMaintenance = false
        queue.resume()
        #expect(engine.log == ["reload"])
    }

    @Test func repeatedRequestsAreCoalesced() {
        engine.isInMaintenance = true
        queue.enqueue(.reload)
        queue.enqueue(.sync)
        queue.enqueue(.reload)
        queue.enqueue(.sync)
        #expect(queue.pending == [.reload, .sync])
    }

    @Test func runsOneTaskAtATime() {
        engine.isInMaintenance = true
        queue.enqueue(.reload)
        queue.enqueue(.sync)
        engine.isInMaintenance = false
        queue.resume()
        #expect(engine.log == ["reload"])
        #expect(queue.pending == [.sync])
        engine.isInMaintenance = false
        queue.resume()
        #expect(engine.log == ["reload", "sync"])
    }
}
