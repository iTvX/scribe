import Foundation
import RimeKit
import Testing

@testable import ScribeConfig

struct AppearanceCustomizationTests {
    static let settings = AppearanceSettings(
        squirrel: [
            "style": ["color_scheme": "light", "color_scheme_dark": "dark", "font_point": "16"],
            "preset_color_schemes": [
                "light": ["name": "浅色", "back_color": "0xeeeeee", "font_point": "18", "candidate_list_layout": "linear"],
                "dark": ["name": "深色", "back_color": "0x222222", "font_point": "20", "candidate_list_layout": "stacked"],
            ],
        ], scribe: [:])

    static func pending(_ changes: [PatchChange]) -> [String: ConfigNode?] {
        var pending: [String: ConfigNode?] = [:]
        for change in changes {
            switch change {
            case .set(let path, let value): pending[path] = value
            case .remove(let path): pending.updateValue(nil, forKey: path)
            }
        }
        return pending
    }

    @Test func copiesBothPalettesWithoutChangingTheirAppearanceOrTheOriginals() throws {
        let settings = Self.settings
        let pending = Self.pending(settings.personalThemeChanges())
        let before = settings.appearance()
        let after = settings.appearance(with: pending)
        #expect(after.light.colors == before.light.colors)
        #expect(after.dark?.colors == before.dark?.colors)
        #expect(after.light.candidateFont == before.light.candidateFont)
        #expect(after.dark?.candidateFont == before.dark?.candidateFont)
        #expect(after.light.layout == .linear)
        #expect(after.dark?.layout == .stacked)
        #expect(settings.isPersonalTheme(after.light.colorSchemeID, with: pending))
        #expect(settings.isPersonalTheme(after.dark?.colorSchemeID, with: pending))
        #expect(settings.personalThemeChanges(with: pending).isEmpty)
        #expect(settings.appearance() == before)
        #expect(!pending.keys.contains { $0.contains("themes/light/") || $0.contains("themes/dark/") })
    }

    @Test func styleEditsAffectBothPersonalPalettesAndPreserveTheirColors() {
        let settings = Self.settings
        var pending = Self.pending(settings.personalThemeChanges())
        let colors = settings.appearance(with: pending)
        for path in settings.editableStylePaths(for: "appearance/font/size", with: pending) { pending[path] = "25" }
        let preview = settings.appearance(with: pending)
        #expect(preview.light.candidateFont.pointSize == 25)
        #expect(preview.dark?.candidateFont.pointSize == 25)
        #expect(preview.light.colors == colors.light.colors)
        #expect(preview.dark?.colors == colors.dark?.colors)
        #expect(settings.editableStylePaths(for: "appearance/status_message", with: pending) == ["appearance/status_message"])
        #expect(settings.editableStylePaths(for: "appearance/theme", with: pending) == ["appearance/theme"])
    }

    @Test func avoidsExistingThemeNames() {
        var settings = Self.settings
        settings.scribe = ["themes": ["scribe_personal_light": ["name": "用户已有主题"]]]
        let pending = Self.pending(settings.personalThemeChanges())
        #expect(pending["themes/scribe_personal_light"] == nil)
        #expect(settings.appearance(with: pending).light.colorSchemeID == "scribe_personal_light_2")
    }

    @Test func nativeThemesRemainSystemThemes() {
        let settings = AppearanceSettings(squirrel: ["style": ["color_scheme": "native"]], scribe: [:])
        #expect(settings.personalThemeChanges().isEmpty)
        #expect(settings.editableStylePaths(for: "appearance/font/size") == ["appearance/font/size"])
    }

    @Test func mixedNativeAndCustomPalettesBothReceiveStyleEdits() {
        var settings = Self.settings
        settings.scribe = ["appearance": ["theme": "native", "dark_theme": "dark"]]
        var pending = Self.pending(settings.personalThemeChanges())
        for path in settings.editableStylePaths(for: "appearance/font/size", with: pending) { pending[path] = "28" }
        let result = settings.appearance(with: pending)
        #expect(result.light.isNative)
        #expect(result.light.candidateFont.pointSize == 28)
        #expect(result.dark?.candidateFont.pointSize == 28)
    }

    @Test func doesNotPretendToOverrideASchemaSelectedTheme() {
        var settings = Self.settings
        settings.schemaStyle = ["color_scheme": "light"]
        #expect(settings.schemaChoosesTheme)
        #expect(settings.personalThemeChanges().isEmpty)
    }
}

extension AppearanceSettingsTests {
    @Test func personalThemeEditsSaveAndReloadExactlyAsPreviewed() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "scribe-personal-theme-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let (shared, user) = try Self.makeDirectories(in: root)
        let sample = try ConfigFixtures.text(ConfigFixtures.directory.appending(path: "max-sample/scribe.custom.yaml"))
        try sample.write(to: user.appending(path: "scribe.custom.yaml"), atomically: true, encoding: .utf8)
        let loaded = try AppearanceSettings.load(userDirectory: user, sharedDirectory: shared, schemaID: nil)
        var edits = AppearanceEdits()
        for change in loaded.personalThemeChanges() {
            if case .set(let path, let value) = change { edits.set(path, to: value, loaded: loaded) }
        }
        #expect(!edits.isEmpty)
        for path in loaded.editableStylePaths(for: "appearance/font/size", with: edits.pending) {
            edits.set(path, to: "24", loaded: loaded)
        }
        let expected = loaded.appearance(with: edits.pending)
        let writer = CustomPatchWriter(userDirectory: user, sharedDirectory: shared)
        _ = try writer.save("scribe", changes: edits.changes, expectedOriginal: loaded.customText)
        let result = try AppearanceSettings.load(userDirectory: user, sharedDirectory: shared, schemaID: nil)
        #expect(result.appearance() == expected)
        #expect(result.appearance().light.candidateFont.pointSize == 24)
        #expect(result.appearance().dark?.candidateFont.pointSize == 24)
        #expect(result.scribe.node(at: "themes/wechat") == loaded.scribe.node(at: "themes/wechat"))
    }
}
