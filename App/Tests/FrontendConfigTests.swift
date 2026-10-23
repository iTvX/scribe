import Foundation
import RimeKit
import ScribeConfig
import ScribeTestSupport
import Testing

@MainActor
@Suite struct FrontendConfigTests {
    /// Settings apps change a patch and ask only for a reload, which must
    /// deploy squirrel.yaml again.
    @Test func aPatchTakesEffectAfterAReload() throws {
        let engine = TestRime.engine
        let patch = TestRime.userDirectory.appending(path: "squirrel.custom.yaml")
        try "patch:\n  chord_duration: 0.25\n".write(to: patch, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: patch)
            FrontendConfig.startMaintenance(engine, fullCheck: true)
            engine.joinMaintenance()
        }

        #expect(FrontendConfig.startMaintenance(engine, fullCheck: true))
        engine.joinMaintenance()
        #expect(ScribeSettings.load(from: engine)?.chordDuration == 0.25)
    }
}
