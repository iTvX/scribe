/// A problem in scribe.yaml that loading silently ignores.
public struct ConfigDiagnostic: Equatable, Sendable {
    public enum Problem: Equatable, Sendable {
        /// The key has no value, as when an unquoted "#RRGGBB" is read as a
        /// YAML comment.
        case missingColor
        /// The value is not "#RRGGBB" or "#RRGGBBAA"; nil for a map or list.
        case invalidColor(String?)
        /// `appearance/theme` or `appearance/dark_theme` names neither native,
        /// a Scribe theme nor a Squirrel preset.
        case unknownTheme(String)
        /// A theme ID under `themes` that contains "/" or ":" or starts with "@".
        case invalidThemeID
    }

    /// The Scribe path of the problem.
    public var path: String
    public var problem: Problem

    public init(path: String, problem: Problem) {
        self.path = path
        self.problem = problem
    }
}

public enum ConfigDiagnostics {
    /// The problems in a Scribe config, given the Squirrel config whose
    /// presets a theme may name.
    public static func check(scribe: some ConfigSource, squirrel: some ConfigSource) -> [ConfigDiagnostic] {
        var diagnostics: [ConfigDiagnostic] = []
        let themes = ScribeConfigSource.themes(in: scribe)
        let colorKeys = Set(ScribeKeyMap.paletteColorKeys.map(\.scribe))

        for id in scribe.mapKeys(at: "themes") ?? [] {
            guard ThemeID.isServable(id) else {
                diagnostics.append(ConfigDiagnostic(path: "themes/\(id)", problem: .invalidThemeID))
                continue
            }
            for palette in ["light", "dark"] {
                for key in scribe.mapKeys(at: "themes/\(id)/\(palette)") ?? [] where colorKeys.contains(key) {
                    let path = "themes/\(id)/\(palette)/\(key)"
                    if let value = scribe.string(at: path) {
                        if RGBAColor(scribe: value, colorSpace: .sRGB) == nil {
                            diagnostics.append(ConfigDiagnostic(path: path, problem: .invalidColor(value)))
                        }
                    } else if scribe.mapKeys(at: path) != nil || scribe.listCount(at: path) != nil {
                        diagnostics.append(ConfigDiagnostic(path: path, problem: .invalidColor(nil)))
                    } else {
                        diagnostics.append(ConfigDiagnostic(path: path, problem: .missingColor))
                    }
                }
            }
        }

        let presets = Set(PresetColorScheme.ids(in: squirrel))
        for key in ["appearance/theme", "appearance/dark_theme"] {
            guard let id = scribe.string(at: key) else { continue }
            if id != "native" && themes[id] == nil && !presets.contains(id) {
                diagnostics.append(ConfigDiagnostic(path: key, problem: .unknownTheme(id)))
            }
        }
        return diagnostics
    }
}
