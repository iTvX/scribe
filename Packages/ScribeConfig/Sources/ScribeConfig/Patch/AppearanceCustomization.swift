/// Creates editable copies of the selected palettes, so editing a style does
/// not silently lose to a preset. All changes remain ordinary Scribe patches.
extension AppearanceSettings {
    public var schemaChoosesTheme: Bool {
        schemaStyle?.string(at: "color_scheme") != nil || schemaStyle?.string(at: "color_scheme_dark") != nil
    }

    public func isPersonalTheme(_ id: String?, with pending: [String: ConfigNode?] = [:]) -> Bool {
        guard let id else { return false }
        return scribe(with: pending).bool(at: "themes/\(id)/settings_customized") == true
    }

    /// Copies only the selected non-native themes. Original themes, colours,
    /// globals and the source Squirrel files are never changed.
    public func personalThemeChanges(with pending: [String: ConfigNode?] = [:]) -> [PatchChange] {
        guard !schemaChoosesTheme else { return [] }
        let edited = scribe(with: pending)
        let source = MergedConfigSource(squirrel: squirrel, scribe: edited)
        let conversion = ScribeConverter.convert(user: source, baseline: ConfigNode.map([:]), scribe: ConfigNode.map([:]))
        let appearance = appearance(with: pending)
        var taken = Set((edited.mapKeys(at: "themes") ?? []) + (source.mapKeys(at: "preset_color_schemes") ?? []))
        var result: [PatchChange] = []
        for (mode, theme) in [("light", appearance.light), ("dark", appearance.dark)] {
            guard let theme, !theme.isNative, let original = theme.colorSchemeID,
                !isPersonalTheme(original, with: pending), let convertedID = conversion.themeIDs[original],
                let entry = conversion.entries.first(where: { $0.key == "themes/\(convertedID)" })
            else { continue }
            let base = "scribe_personal_\(mode)"
            var id = base
            var suffix = 2
            while taken.contains(id) {
                id = "\(base)_\(suffix)"
                suffix += 1
            }
            taken.insert(id)
            let name = source.string(at: "preset_color_schemes/\(original)/name") ?? original
            let label = mode == "light" ? "我的浅色" : "我的深色"
            let copy = entry.value.setting("name", to: .scalar("\(label) · \(name)"))
                .setting("settings_customized", to: "true")
            result.append(.set("themes/\(id)", copy))
            result.append(.set(mode == "light" ? "appearance/theme" : "appearance/dark_theme", .scalar(id)))
        }
        return result
    }

    /// Personal palette styles win over inherited preset styles. Global-only
    /// settings stay global. Both selected personal palettes receive an edit.
    public func editableStylePaths(for path: String, with pending: [String: ConfigNode?] = [:]) -> [String] {
        guard path.hasPrefix("appearance/") else { return [path] }
        let suffix = String(path.dropFirst("appearance/".count))
        guard ScribeKeyMap.squirrelPath(forScribe: "themes/x/style/\(suffix)") != nil else { return [path] }
        let appearance = appearance(with: pending)
        let ids = [appearance.light, appearance.dark].compactMap { $0?.colorSchemeID }
            .filter { isPersonalTheme($0, with: pending) }
        var paths = Array(Set(ids)).sorted().map { "themes/\($0)/style/\(suffix)" }
        if paths.isEmpty { return [path] }
        // A native light/dark counterpart still takes its style globally.
        if appearance.light.isNative || appearance.dark?.isNative == true { paths.insert(path, at: 0) }
        return paths
    }
}
