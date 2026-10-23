import Foundation
import RimeKit
@testable import ScribeConfig
import Testing

/// Loads through real librime. Everything that runs the engine happens in
/// one synchronous main-actor test, which leaves it stopped.
@MainActor
@Suite("appearance settings", .serialized)
struct AppearanceSettingsTests {
    /// A temporary shared directory with Scribe's squirrel.yaml and
    /// scribe.yaml, and a user directory with rime-ice's squirrel.yaml.
    static func makeDirectories(in root: URL) throws -> (shared: URL, user: URL) {
        let fileManager = FileManager.default
        let shared = root.appending(path: "shared", directoryHint: .isDirectory)
        let user = root.appending(path: "Scribe", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: shared, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: user.appending(path: "build"), withIntermediateDirectories: true)
        try fileManager.copyItem(at: ConfigFixtures.squirrelYAML, to: shared.appending(path: "squirrel.yaml"))
        try fileManager.copyItem(at: ConfigFixtures.scribeYAML, to: shared.appending(path: "scribe.yaml"))
        try fileManager.copyItem(at: ConfigFixtures.rimeIceYAML, to: user.appending(path: "squirrel.yaml"))
        return (shared, user)
    }

    @Test func loadsPreviewsAndExplains() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "ScribeConfigTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: root) }
        let (shared, user) = try Self.makeDirectories(in: root)
        let customFile = user.appending(path: "scribe.custom.yaml")
        let sample = try ConfigFixtures.text(ConfigFixtures.directory.appending(path: "max-sample/scribe.custom.yaml"))
        try Data(sample.utf8).write(to: customFile)
        let engine = LibrimeEngine.shared
        #expect(!engine.isRunning)
        defer { engine.stop() }
        func load(_ schemaID: String? = nil) throws -> AppearanceSettings {
            try AppearanceSettings.load(userDirectory: user, sharedDirectory: shared, schemaID: schemaID)
        }

        // Max's sample: one Scribe theme with light and dark palettes.
        let before = try snapshot(of: user)
        let settings = try load()
        #expect(try snapshot(of: user) == before)
        #expect(!engine.isRunning)
        #expect(settings.customText == sample)
        #expect(settings.customKeys == ["appearance/theme", "app_options/com.googlecode.iterm2", "themes/wechat"])
        #expect(settings.editProblem == nil)
        #expect(settings.diagnostics.isEmpty)
        #expect(settings.themes.prefix(2).map(\.id) == ["native", "wechat"])
        #expect(settings.themes.contains { $0.id == "lost_temple" })
        let appearance = settings.appearance()
        #expect(appearance.light.colorSchemeID == "wechat")
        #expect(appearance.dark?.colorSchemeID == "wechat:dark")

        #expect(settings.provenance(of: "appearance/theme") == .ownEntry)
        #expect(settings.provenance(of: "themes/wechat/style/font/size") == .insideEntry("themes/wechat"))
        #expect(settings.provenance(of: "appearance/font/size") == .squirrelOrDefault)
        // The wechat theme sets its own font size and layout; status messages are not per theme.
        #expect(settings.themesSetting("appearance/font/size") == ["wechat", "wechat:dark"])
        #expect(settings.themesSetting("appearance/layout") == ["wechat", "wechat:dark"])
        #expect(settings.themesSetting("appearance/status_message").isEmpty)
        #expect(settings.themesSetting("appearance/font/size", with: ["appearance/theme": "lost_temple", "appearance/dark_theme": "lost_temple"]).isEmpty)

        // The preview matches what librime deploys once the same entries are written.
        let pending: [String: ConfigNode?] = [
            "appearance/theme": "lost_temple",
            "appearance/dark_theme": "mojave_dark",
            "appearance/status_message": "short",
            "appearance/memorize_size": "false",
            "appearance/font/size": "20",
            "appearance/corner_radius": "9",
        ]
        var editor = try CustomPatchEditor(text: sample)
        for (path, value) in pending {
            editor.set(path, to: try #require(value))
        }
        try Data(editor.text.utf8).write(to: customFile)
        let written = try load()
        #expect(written.appearance() == settings.appearance(with: pending))
        #expect(written.loadedValue(at: "appearance/font/size") == "20")

        // So does removing an entry.
        editor = try CustomPatchEditor(text: sample)
        editor.remove("appearance/theme")
        try Data(editor.text.utf8).write(to: customFile)
        let removed = try load()
        #expect(removed.appearance() == settings.appearance(with: ["appearance/theme": nil]))
        #expect(removed.provenance(of: "appearance/theme") == .squirrelOrDefault)

        // A schema's `style` wins over both.
        try Data(sample.utf8).write(to: customFile)
        try Data("schema:\n  schema_id: styled\nstyle:\n  font_point: 20\n  color_scheme: lost_temple\n".utf8)
            .write(to: user.appending(path: "build/styled.schema.yaml"))
        let styled = try load("styled")
        #expect(styled.schemaStyle == ["font_point": "20", "color_scheme": "lost_temple"])
        #expect(styled.isOverriddenBySchema("appearance/font/size"))
        #expect(styled.isOverriddenBySchema("appearance/theme"))
        #expect(!styled.isOverriddenBySchema("appearance/layout"))
        #expect(!settings.isOverriddenBySchema("appearance/font/size"))
        #expect(styled.appearance().light.colorSchemeID == "lost_temple")
        #expect(styled.appearance(with: ["appearance/theme": "native"]).light.colorSchemeID == "lost_temple")

        // Files the editor cannot change load read-only.
        let gbk = Data([0x23, 0x20, 0xB2, 0xE2, 0xCA, 0xD4, 0x0A]) + Data(sample.utf8)
        try gbk.write(to: customFile)
        let notUTF8 = try load()
        #expect(notUTF8.editProblem == .notUTF8)
        #expect(notUTF8.customText == nil)
        #expect(fileManager.contents(atPath: customFile.path(percentEncoded: false)) == gbk)
        try Data("patch: {appearance/theme: native}\n".utf8).write(to: customFile)
        let flow = try load()
        #expect(flow.editProblem == .unsupportedLayout(line: 1, reason: .flowPatch))
        #expect(flow.appearance().light.isNative)

        // Unquoted colours are reported.
        try Data("patch:\n  themes/plain:\n    light:\n      background: #FFFFFF\n".utf8).write(to: customFile)
        let diagnosed = try load()
        #expect(diagnosed.diagnostics == [ConfigDiagnostic(path: "themes/plain/light/background", problem: .missingColor)])
        #expect(!engine.isRunning)

        try checkConversions(in: root.appending(path: "conversions", directoryHint: .isDirectory))
    }

    /// The conversion offer, against Scribe's own squirrel.yaml as the baseline.
    private func checkConversions(in root: URL) throws {
        let fileManager = FileManager.default
        let engine = LibrimeEngine.shared
        func directories(_ name: String, shared sharedFiles: [URL], user userFiles: [(URL, String)]) throws -> (shared: URL, user: URL) {
            let shared = root.appending(path: "\(name)/shared", directoryHint: .isDirectory)
            let user = root.appending(path: "\(name)/Scribe", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: shared, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: user, withIntermediateDirectories: true)
            for file in sharedFiles {
                try fileManager.copyItem(at: file, to: shared.appending(path: file.lastPathComponent))
            }
            for (file, name) in userFiles {
                try fileManager.copyItem(at: file, to: user.appending(path: name))
            }
            return (shared, user)
        }
        let sharedFiles = [ConfigFixtures.squirrelYAML, ConfigFixtures.scribeYAML]
        let maxSampleCustom = ConfigFixtures.directory.appending(path: "max-sample/squirrel.custom.yaml")

        // Max's sample: the same as converting the deployed files directly.
        let sample = try directories("max-sample", shared: sharedFiles, user: [(maxSampleCustom, "squirrel.custom.yaml")])
        let before = try snapshot(of: sample.user)
        let settings = try AppearanceSettings.load(userDirectory: sample.user, sharedDirectory: sample.shared, schemaID: nil)
        #expect(try snapshot(of: sample.user) == before)
        let conversion = try #require(settings.conversion)
        #expect(!conversion.isEmpty)
        let copy = root.appending(path: "max-sample/copy", directoryHint: .isDirectory)
        try fileManager.copyItem(at: sample.user, to: copy)
        engine.start(RimeConfiguration(sharedDataDirectory: sample.shared, userDataDirectory: copy, minimumLogLevel: 2))
        #expect(engine.deployConfigFile("squirrel.yaml", versionKey: "config_version"))
        #expect(engine.deployConfigFile("scribe.yaml", versionKey: "config_version"))
        let direct = ScribeConversion.load(from: engine, baselineYAML: try ConfigFixtures.text(ConfigFixtures.squirrelYAML))
        engine.stop()
        #expect(conversion == direct)

        // rime-ice's squirrel.yaml: its status icon stays with the Squirrel files.
        let rimeIce = try directories("rime-ice", shared: sharedFiles, user: [(ConfigFixtures.rimeIceYAML, "squirrel.yaml")])
        let rimeIceConversion = try #require(try AppearanceSettings.load(userDirectory: rimeIce.user, sharedDirectory: rimeIce.shared,
                                                                         schemaID: nil).conversion)
        #expect(!rimeIceConversion.isEmpty)
        #expect(rimeIceConversion.unconverted == [
            ScribeConversion.Unconverted(squirrelPath: "status_icon/show", scribePath: "status_icon", reason: .absentFromSquirrelConfig),
        ])

        // Nothing customised: nothing to convert.
        let plain = try directories("plain", shared: sharedFiles, user: [])
        #expect(try AppearanceSettings.load(userDirectory: plain.user, sharedDirectory: plain.shared, schemaID: nil).conversion?.isEmpty == true)

        // Without Scribe's squirrel.yaml there is no baseline; the rest still loads.
        let noBaseline = try directories("no-baseline", shared: [ConfigFixtures.scribeYAML],
                                         user: [(ConfigFixtures.rimeIceYAML, "squirrel.yaml")])
        let unconvertible = try AppearanceSettings.load(userDirectory: noBaseline.user, sharedDirectory: noBaseline.shared, schemaID: nil)
        #expect(unconvertible.conversion == nil)
        #expect(unconvertible.appearance().light.colorSchemeID == "purity_of_form_custom")
        #expect(!engine.isRunning)
    }
}
