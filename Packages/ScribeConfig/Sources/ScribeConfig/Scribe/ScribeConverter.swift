/// The scribe.custom.yaml entries that carry a user's Squirrel settings over
/// to Scribe's format, leaving the Squirrel files as they are.
public struct ScribeConversion: Equatable, Sendable {
    /// One patch entry, at the granularity the Settings app writes: one per
    /// setting, one per app and one per theme.
    public struct Entry: Equatable, Sendable {
        /// A patch key such as "appearance/font/size", "app_options/com.foo"
        /// or "themes/aqua".
        public var key: String
        public var value: ConfigNode

        public init(key: String, value: ConfigNode) {
            self.key = key
            self.value = value
        }
    }

    /// A setting that still depends on the Squirrel files.
    public struct Unconverted: Equatable, Sendable {
        public enum Reason: Equatable, Sendable {
            /// Scribe's squirrel.yaml sets the key and the user's config does
            /// not, and Scribe's format cannot express "unset".
            case absentFromSquirrelConfig
        }

        public var squirrelPath: String
        public var scribePath: String
        public var reason: Reason

        public init(squirrelPath: String, scribePath: String, reason: Reason) {
            self.squirrelPath = squirrelPath
            self.scribePath = scribePath
            self.reason = reason
        }
    }

    /// Global keys, then appearance keys, then app options, then themes.
    public var entries: [Entry]
    /// The Scribe theme ID of each converted Squirrel preset.
    public var themeIDs: [String: String]
    public var unconverted: [Unconverted]

    public init(entries: [Entry] = [], themeIDs: [String: String] = [:], unconverted: [Unconverted] = []) {
        self.entries = entries
        self.themeIDs = themeIDs
        self.unconverted = unconverted
    }

    /// True when there is nothing to write.
    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// Sets every entry.
    public func apply(to editor: inout CustomPatchEditor) {
        for entry in entries {
            editor.set(entry.key, to: entry.value)
        }
    }
}

public enum ScribeConverter {
    /// The entries that make Scribe's format reproduce `user` on top of
    /// `baseline`, without overwriting anything `scribe` already sets.
    ///
    /// - Parameters:
    ///   - user: The deployed squirrel.yaml, with the user's patches.
    ///   - baseline: Scribe's own squirrel.yaml, which applies with no
    ///     Squirrel customization.
    ///   - scribe: The deployed scribe.yaml. A key it sets is never written;
    ///     an existing theme is kept (and still named in `themeIDs`).
    public static func convert(
        user: some ConfigSource,
        baseline: some ConfigSource,
        scribe: some ConfigSource
    ) -> ScribeConversion {
        var conversion = ScribeConversion()
        func emit(_ key: String, _ value: ConfigNode) {
            if !sets(scribe, key) {
                conversion.entries.append(ScribeConversion.Entry(key: key, value: value))
            }
        }
        func unconverted(_ entry: ScribeKeyMap.Entry) {
            if !sets(scribe, entry.scribePath) {
                conversion.unconverted.append(ScribeConversion.Unconverted(
                    squirrelPath: entry.squirrelPath,
                    scribePath: entry.scribePath,
                    reason: .absentFromSquirrelConfig
                ))
            }
        }

        let presets = convertedPresets(user: user, baseline: baseline)
        conversion.themeIDs = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0.themeID) })

        let themeKeys: Set = ["appearance/theme", "appearance/dark_theme"]
        let settingsEntries = ScribeKeyMap.entries.filter { entry in
            !entry.scribePath.hasPrefix("themes/") && !entry.scribePath.hasPrefix("app_options/")
        }
        let setsThemes = themeKeys.contains { sets(scribe, $0) }
        for entry in settingsEntries {
            let value = user.string(at: entry.squirrelPath)
            let base = baseline.string(at: entry.squirrelPath)
            if themeKeys.contains(entry.scribePath) {
                guard !setsThemes else { continue }
                let renamed = value.flatMap { conversion.themeIDs[$0] }.map { $0 != value } ?? false
                if let value, value != base || renamed {
                    conversion.entries.append(ScribeConversion.Entry(
                        key: entry.scribePath,
                        value: .scalar(conversion.themeIDs[value] ?? value)
                    ))
                } else if value == nil, base != nil {
                    unconverted(entry)
                }
            } else if let value {
                if value != base {
                    emit(entry.scribePath, .scalar(value))
                }
            } else if base != nil {
                unconverted(entry)
            }
        }

        let userOptions = AppOptions(source: user)
        let baselineOptions = AppOptions(source: baseline)
        let apps = Set(userOptions.byBundleID.keys).union(baselineOptions.byBundleID.keys)
        for app in apps.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
            let options = userOptions.byBundleID[app]
            guard options != baselineOptions.byBundleID[app] else { continue }
            emit("app_options/\(app)", .map((options ?? [:]).mapValues { .scalar($0 ? "true" : "false") }))
        }

        for preset in presets {
            emit("themes/\(preset.themeID)", theme(fromPreset: preset.id, in: user))
        }
        return conversion
    }

    /// Whether `source` has a value (not a null) at `path`.
    private static func sets(_ source: some ConfigSource, _ path: String) -> Bool {
        source.string(at: path) != nil || source.mapKeys(at: path) != nil || source.listCount(at: path) != nil
    }

    /// The user's presets that are new or differ from the baseline's, other
    /// than native, each with its Scribe theme ID, in librime's order. A
    /// preset whose ID a path cannot reach (such as "@x") converts to an
    /// empty theme, as librime reads nothing from it either.
    private static func convertedPresets(
        user: some ConfigSource,
        baseline: some ConfigSource
    ) -> [(id: String, themeID: String)] {
        func presetIDs(in source: some ConfigSource) -> [String] {
            (source.mapKeys(at: "preset_color_schemes") ?? []).filter { id in
                let path = "preset_color_schemes/\(id)"
                return source.string(at: path) == nil && source.listCount(at: path) == nil
            }
        }
        let userIDs = presetIDs(in: user)
        let baselineIDs = Set(presetIDs(in: baseline))
        var taken = Set(userIDs).union(["native"])
        var presets: [(id: String, themeID: String)] = []
        for id in userIDs where id != "native" {
            let path = "preset_color_schemes/\(id)"
            if baselineIDs.contains(id), ConfigNode(snapshotOf: user, at: path) == ConfigNode(snapshotOf: baseline, at: path) {
                continue
            }
            if ThemeID.isServable(id) {
                presets.append((id, id))
                continue
            }
            let base = derivedThemeID(id)
            var themeID = base
            var suffix = 2
            while taken.contains(themeID) {
                themeID = "\(base)_\(suffix)"
                suffix += 1
            }
            taken.insert(themeID)
            presets.append((id, themeID))
        }
        return presets
    }

    /// Lowercased, with every character outside [a-z0-9_] replaced by "_".
    private static func derivedThemeID(_ id: String) -> String {
        let derived = String(id.lowercased().map { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_") ? character : "_"
        })
        return derived.isEmpty ? "_" : derived
    }

    /// A Squirrel preset as a Scribe theme with a light palette: metadata and
    /// scheme-level style keys as written, and the colours that parse.
    private static func theme(fromPreset id: String, in user: some ConfigSource) -> ConfigNode {
        let prefix = "preset_color_schemes/\(id)"
        var theme: [String: ConfigNode] = [:]
        for key in ScribeKeyMap.themeMetadataKeys {
            if let value = user.string(at: "\(prefix)/\(key.squirrel)") {
                theme[key.scribe] = .scalar(value)
            }
        }
        var style = ConfigNode.map([:])
        for key in ScribeKeyMap.schemeStyleKeys {
            if let value = user.string(at: "\(prefix)/\(key.squirrel)") {
                style = style.setting(.scalar(value), at: key.scribe)
            }
        }
        if style != .map([:]) {
            theme["style"] = style
        }
        let colorSpace = ColorSpace(squirrel: user.string(at: "\(prefix)/color_space"))
        var light: [String: ConfigNode] = [:]
        for key in ScribeKeyMap.paletteColorKeys {
            let color = user.parsed(at: "\(prefix)/\(key.squirrel)") { RGBAColor(squirrel: $0, colorSpace: colorSpace) }
            if let color {
                light[key.scribe] = .scalar(color.scribeLiteral)
            }
        }
        if !light.isEmpty {
            theme["light"] = .map(light)
        }
        return .map(theme)
    }
}

extension ConfigNode {
    /// This node with `value` at a path of map keys, creating maps on the way.
    func setting(_ value: ConfigNode, at path: String) -> ConfigNode {
        let keys = path.split(separator: "/", maxSplits: 1).map(String.init)
        guard let key = keys.first else { return value }
        var map: [String: ConfigNode] = if case .map(let map) = self { map } else { [:] }
        let child = map[key] ?? .map([:])
        map[key] = keys.count == 2 ? child.setting(value, at: keys[1]) : value
        return .map(map)
    }
}
