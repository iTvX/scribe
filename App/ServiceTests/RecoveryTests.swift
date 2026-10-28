import Foundation
import Testing

// Suppress only the menu bar UI. RimeService, LaunchGuard and the engine
// notification-handler binding are the production implementations.
@MainActor final class ModeStatusItem {
    var isEnabled = true
    var isScribeCurrent = false
    var title = ""
}

@MainActor @Suite(.serialized) struct RecoveryTests {
    @Test func crashGuardStillInstallsTheHandlerNeededByRedeploy() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "scribe-launch-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let guardState = LaunchGuard(file: file)
        let launchTime = Date(timeIntervalSince1970: 1_000)
        #expect(!guardState.isRelaunchTooSoon(now: launchTime))
        let service = RimeService.shared
        service.engine.notificationHandler = nil
        defer { service.engine.notificationHandler = nil }
        var warned = false
        service.start(launchGuard: guardState, logDirectory: nil, warning: { _ in warned = true }, now: launchTime.addingTimeInterval(1))
        #expect(warned)
        #expect(!service.engine.isRunning)
        #expect(service.engine.notificationHandler != nil)
    }
}
