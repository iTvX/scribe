import Foundation
import RimeKit
import ScribeConfig
import ScribeCore
import ScribeTestSupport
import Testing

@MainActor
@Suite(.serialized) struct FrontendConfigTests {
    /// Settings apps change a patch and ask only for a reload, which must
    /// deploy squirrel.yaml and scribe.yaml again.
    @Test(arguments: ["squirrel.custom.yaml", "scribe.custom.yaml"])
    func aPatchTakesEffectAfterAReload(patchFile: String) throws {
        let engine = TestRime.engine
        let patch = TestRime.userDirectory.appending(path: patchFile)
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

    /// The window and the sessions follow the style of the schema in use.
    @Test func aSchemasStyleOverridesSquirrelYAML() throws {
        let engine = TestRime.engine
        FrontendConfig.startMaintenance(engine, fullCheck: true)
        engine.joinMaintenance()
        let settings = try #require(ScribeSettings.load(from: engine))

        let plain = try #require(FrontendConfig.load(engine, settings: settings, schemaID: "", isDark: false))
        #expect(plain.configuration.presentation == InputSession.Presentation(inlinePreedit: true))
        #expect(plain.appearance.light.layout == .stacked)

        let schema = try #require(FrontendConfig.load(engine, settings: settings, schemaID: "scribe_test", isDark: false))
        #expect(schema.configuration.presentation == InputSession.Presentation(inlinePreedit: false, linear: true))
        #expect(schema.appearance.light.layout == .linear)
    }
}
