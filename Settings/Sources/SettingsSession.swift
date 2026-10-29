import Foundation
import Observation
import ScribeConfig

@MainActor @Observable
final class SettingsSession {
    var selection: SettingsPage = .schemas
    var recipe = ""
    var isRecordingShortcut = false
    var isFrozen = false
    var updateMessage: String?
    var canRetryUpdate = false
    var legacyPIDs: [Int32] = []
}

struct DefaultsDraft: Codable, Equatable {
    struct Schemas: Codable, Equatable { var nodes: [ConfigNode]; var pageSize: Int }
    struct Shortcuts: Codable, Equatable { var hotkeys: [String]; var switchKey: [String: String] }
    var original: String?
    var schemas: Schemas?
    var shortcuts: Shortcuts?
}

struct SettingsFieldDraft: Codable, Equatable {
    var text: String
    var minimum: Double?
    var maximum: Double?

    static func parseNumber(_ text: String) -> Double? {
        let scanner = Scanner(string: text)
        scanner.locale = Locale.current
        guard let value = scanner.scanDouble(), scanner.isAtEnd, value.isFinite else { return nil }
        return value
    }

    var isValid: Bool {
        guard let minimum, let maximum else { return true }
        guard let value = Self.parseNumber(text) else { return false }
        return (minimum...maximum).contains(value)
    }
}

struct LooksDraft: Codable, Equatable {
    var original: String?
    var edits: AppearanceEdits
    var fields: [String: SettingsFieldDraft]
}

/// Private recovery data, never a configuration patch and never auto-saved to YAML.
struct SettingsDraft: Codable, Equatable {
    var userDirectory: URL
    var defaults: DefaultsDraft?
    var looks: LooksDraft?
    var page: SettingsPage
    var recipe: String
    var importSource: URL
    var importFailure: String?
    var legacyPIDs: [Int32]?

    var hasPendingChanges: Bool { defaults != nil || looks != nil || !recipe.isEmpty || importFailure != nil }

    @MainActor
    init(defaults: DefaultsModel, looks: LooksModel, importer: ImportModel, session: SettingsSession) {
        userDirectory = defaults.directories.user.standardizedFileURL
        self.defaults = defaults.draft()
        self.looks = looks.draft()
        page = session.selection
        recipe = session.recipe
        importSource = importer.source
        importFailure = importer.failureMessage
        legacyPIDs = session.legacyPIDs
    }

    @MainActor
    func restore(defaults: DefaultsModel, looks: LooksModel, importer: ImportModel, session: SettingsSession) throws {
        guard userDirectory == defaults.directories.user.standardizedFileURL else { throw SettingsHandoffError.wrongDirectory }
        guard (self.defaults == nil || defaults.loaded != nil), (self.looks == nil || looks.settings != nil) else {
            throw SettingsHandoffError.cannotRestore
        }
        if let draft = self.defaults { try defaults.restore(draft) }
        if let draft = self.looks { try looks.restore(draft) }
        session.selection = page
        session.recipe = recipe
        session.legacyPIDs = legacyPIDs ?? []
        importer.source = importSource
        importer.restoreFailure(importFailure)
    }
}
