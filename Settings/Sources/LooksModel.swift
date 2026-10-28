import Foundation
import Observation
import ScribeConfig

/// 外观: the candidate window settings in scribe.custom.yaml. Never writes
/// squirrel.custom.yaml.
@MainActor @Observable
final class LooksModel {
    let directories: SettingsDirectories
    /// Nil until loaded, or when loading failed.
    private(set) var settings: AppearanceSettings?
    private(set) var loadError: String?
    /// Why changes cannot be saved, or nil.
    private(set) var readOnlyReason: String?
    private(set) var schemaID: String?
    private(set) var schemaName: String?
    private(set) var status: SaveStatus?
    private(set) var edits = AppearanceEdits()
    /// Set when a conversion found the file changed: the page reloads when it opens again.
    private(set) var needsReload = false

    init(directories: SettingsDirectories) {
        self.directories = directories
    }

    /// The themes with the pending edits applied.
    var preview: Appearance? {
        settings?.appearance(with: edits.pending)
    }

    var hasEdits: Bool { !edits.isEmpty }

    func load(activeSchema: String?, schemaName: String?) {
        schemaID = activeSchema
        self.schemaName = schemaName
        status = nil
        edits.discard()
        guard let shared = directories.shared else {
            settings = nil
            loadError = "找不到中书，没法读取和校验外观"
            readOnlyReason = loadError
            emit("Appearance load failed: Scribe not found")
            return
        }
        do {
            let settings = try AppearanceSettings.load(userDirectory: directories.user, sharedDirectory: shared, schemaID: activeSchema)
            self.settings = settings
            loadError = nil
            readOnlyReason = settings.editProblem.map { DefaultsModel.message(for: $0, file: "scribe.custom.yaml") }
            let appearance = settings.appearance()
            emit(
                "Appearance loaded: \(settings.themes.count) themes; light \(appearance.light.colorSchemeID ?? "native")"
                    + "; dark \(appearance.dark?.colorSchemeID ?? "none"); diagnostics \(settings.diagnostics.count)"
                    + "; schema \(activeSchema ?? "none")\(settings.schemaStyle == nil ? "" : " with style")"
                    + "; scribe.custom.yaml \(settings.customText == nil ? "absent" : "\(settings.customKeys.count) entries")"
                    + "; conversion \(settings.conversion.map { $0.isEmpty ? "none" : "\($0.entries.count) entries" } ?? "unavailable")"
                    + (readOnlyReason.map { "; read-only: \($0)" } ?? "")
                    + "; live \(directories.isLive)")
        } catch {
            settings = nil
            loadError = DefaultsModel.message(for: error, file: "scribe.custom.yaml")
            readOnlyReason = loadError
            emit("Appearance load failed: \(error)")
        }
    }

    // MARK: - Edits

    func set(_ path: String, _ value: ConfigNode) {
        guard let settings, readOnlyReason == nil else { return }
        let previous = edits
        for target in settings.editableStylePaths(for: path, with: edits.pending) {
            edits.set(target, to: value, loaded: settings)
        }
        if edits != previous { status = nil }
    }

    /// 恢复默认, or 跟随浅色主题 for the dark theme.
    func reset(_ path: String) {
        guard let settings, readOnlyReason == nil else { return }
        for target in settings.editableStylePaths(for: path, with: edits.pending) {
            edits.reset(target, loaded: settings)
        }
        status = nil
    }

    func isEdited(_ path: String) -> Bool {
        settings?.editableStylePaths(for: path, with: edits.pending).contains { edits.pending.keys.contains($0) } ?? false
    }

    /// The raw value at a Scribe path, edits included, such as a theme ID.
    func value(at path: String) -> String? {
        guard let settings, case .scalar(let value) = settings.effectiveValue(at: path, with: edits.pending) else { return nil }
        return value
    }

    /// Why a control may not show what is set, or where it is set.
    func notes(for path: String) -> [String] {
        guard let settings else { return [] }
        var notes: [String] = []
        if case .insideEntry(let entry) = settings.provenance(of: path) {
            notes.append("在 scribe.custom.yaml 的 \(entry) 里设置")
        }
        let targets = settings.editableStylePaths(for: path, with: edits.pending)
        if targets != [path] { return notes }
        if settings.isOverriddenBySchema(path) {
            notes.append("当前方案（\(schemaName ?? schemaID ?? "")）自带这一项，修改不会在这个方案里生效")
        }
        let themes = settings.themesSetting(path, with: edits.pending).map { id in
            let base = id.hasSuffix(":dark") ? String(id.dropLast(":dark".count)) : id
            return settings.themes.first { $0.id == base }?.name ?? base
        }
        let names = themes.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        if !names.isEmpty {
            notes.append("当前主题（\(names.joined(separator: "、"))）自带这一项，修改只在别的主题里生效")
        }
        return notes
    }

    /// Whether 恢复默认 applies: scribe.custom.yaml has exactly this entry.
    func canReset(_ path: String) -> Bool {
        guard let settings, readOnlyReason == nil else { return false }
        return settings.editableStylePaths(for: path, with: edits.pending).contains {
            settings.provenance(of: $0) == .ownEntry || edits.pending.keys.contains($0)
        }
    }

    var availableThemes: [ThemeInfo] {
        guard let settings else { return [] }
        return AppearanceSettings(squirrel: settings.squirrel, scribe: settings.scribe(with: edits.pending)).themes
    }

    var canPersonalize: Bool {
        guard let settings, readOnlyReason == nil else { return false }
        return !settings.personalThemeChanges(with: edits.pending).isEmpty
    }

    var isPersonalized: Bool {
        guard let settings, let preview else { return false }
        return settings.isPersonalTheme(preview.light.colorSchemeID, with: edits.pending)
            || settings.isPersonalTheme(preview.dark?.colorSchemeID, with: edits.pending)
    }

    func personalize() {
        guard let settings, readOnlyReason == nil else { return }
        for change in settings.personalThemeChanges(with: edits.pending) {
            if case .set(let path, let value) = change { edits.set(path, to: value, loaded: settings) }
        }
        status = nil
    }

    // MARK: - Saving

    func revert() {
        load(activeSchema: schemaID, schemaName: schemaName)
    }

    func save() {
        guard let settings, let shared = directories.shared, readOnlyReason == nil, hasEdits else { return }
        let changes = edits.changes
        let writer = CustomPatchWriter(userDirectory: directories.user, sharedDirectory: shared)
        do {
            let result = try writer.save("scribe", changes: changes, expectedOriginal: settings.customText)
            let (message, posted) = directories.announce(result)
            let summary = changes.map { change -> String in
                switch change {
                case .set(let key, _): "set \(key)"
                case .remove(let key): "remove \(key)"
                }
            }
            emit(
                "Appearance saved scribe.custom.yaml: \(summary.joined(separator: ", ")); file \(result.file.path(percentEncoded: false)); posted reload \(posted)"
            )
            load(activeSchema: schemaID, schemaName: schemaName)
            status = SaveStatus(message: message, isError: false)
        } catch {
            emit("Appearance save failed: \(error)")
            status = SaveStatus(
                message: DefaultsModel.message(for: error, file: "scribe.custom.yaml"), isError: true,
                file: directories.user.appending(path: "scribe.custom.yaml").resolvingSymlinksInPath())
        }
    }

    // MARK: - Converting

    /// The offer when Squirrel-format settings could move to scribe.custom.yaml.
    var conversionOffer: ConversionOffer? {
        guard let settings, let conversion = settings.conversion, !conversion.isEmpty else { return nil }
        return ConversionOffer(conversion: conversion, themes: settings.themes)
    }

    /// Why 查看并转换 is not available now, or nil.
    var conversionUnavailableReason: String? {
        ConversionOffer.unavailableReason(conversion: settings?.conversion, hasEdits: hasEdits, readOnlyReason: readOnlyReason)
    }

    /// Whether the user directory has its own squirrel.yaml besides squirrel.custom.yaml.
    var hasUserSquirrelYAML: Bool {
        FileManager.default.fileExists(atPath: directories.user.appending(path: "squirrel.yaml").path(percentEncoded: false))
    }

    /// Writes the conversion to scribe.custom.yaml. The Squirrel files stay as they are.
    func convert() {
        guard let settings, let shared = directories.shared, let offer = conversionOffer, conversionUnavailableReason == nil
        else { return }
        let writer = CustomPatchWriter(userDirectory: directories.user, sharedDirectory: shared)
        do {
            let result = try writer.save(
                "scribe", changes: offer.conversion.entries.map { .set($0.key, $0.value) },
                expectedOriginal: settings.customText)
            let (message, posted) = directories.announce(result)
            emit(
                "Appearance converted scribe.custom.yaml: \(offer.conversion.entries.count) entries"
                    + " (global \(offer.count(.general)), appearance \(offer.count(.appearance)), apps \(offer.count(.apps)), themes \(offer.count(.themes)))"
                    + "; unconverted \(offer.unconverted.count); file \(result.file.path(percentEncoded: false)); posted reload \(posted)")
            load(activeSchema: schemaID, schemaName: schemaName)
            status = SaveStatus(message: message, isError: false)
        } catch {
            emit("Appearance conversion failed: \(error)")
            var message = DefaultsModel.message(for: error, file: "scribe.custom.yaml")
            if error == .changedOnDisk {
                message = "scribe.custom.yaml 在读取之后被改过了，没有转换。请重新打开外观页再试。"
                needsReload = true
            }
            status = SaveStatus(
                message: message, isError: true,
                file: directories.user.appending(path: "scribe.custom.yaml").resolvingSymlinksInPath())
        }
    }

    /// -ScribeConvertOnLaunch: converts once without the sheet, only in an
    /// overridden user directory.
    func convertOnLaunch() {
        guard !directories.isLive else {
            emit("Convert on launch ignored: live directory")
            return
        }
        guard conversionOffer != nil else {
            emit("Convert on launch: nothing to convert")
            return
        }
        convert()
    }

    /// Reloads after a conversion found the file changed.
    func reloadIfNeeded() {
        guard needsReload else { return }
        needsReload = false
        load(activeSchema: schemaID, schemaName: schemaName)
    }

    // MARK: - Messages

    static func message(for diagnostic: ConfigDiagnostic) -> String {
        switch diagnostic.problem {
        case .missingColor:
            "\(diagnostic.path) 没有值：# 开头的颜色要加引号"
        case .invalidColor(let value):
            "\(diagnostic.path) 的 \(value ?? "（列表或映射）") 不是 #RRGGBB 或 #RRGGBBAA 颜色"
        case .unknownTheme(let id):
            "\(diagnostic.path) 指定的主题 \(id) 不存在"
        case .invalidThemeID:
            "\(diagnostic.path) 这个主题 ID 中书不会使用（native、含 / 或 :，或以 @ 开头）"
        }
    }

    private func emit(_ line: String) {
        Log.settings.notice("\(line, privacy: .public)")
        print(line)
        fflush(nil)
    }
}
