/// A Scribe config (scribe.yaml) presented as the Squirrel config it stands
/// for, so the Squirrel loaders apply every compatibility rule.
///
/// It is built once from the Scribe config, so it outlives the source it was
/// read from. Every Squirrel path in `ScribeKeyMap` reads its Scribe path;
/// colours come back as Squirrel literals and values that do not parse are
/// left out. Each valid theme under `themes` becomes the preset "{id}" (its
/// light palette) and, when it has a dark palette, "{id}:dark".
/// `style/color_scheme` and `style/color_scheme_dark` follow
/// `appearance/theme` and `appearance/dark_theme`; see `MergedConfigSource`
/// for how it combines with squirrel.yaml.
public struct ScribeConfigSource: ConfigSource, Equatable, Sendable {
    /// The Squirrel config the Scribe config stands for.
    public let squirrelConfig: ConfigNode
    /// The preset IDs served from Scribe themes, "{id}" and "{id}:dark".
    public let servedPresetIDs: [String]

    public init(scribe: some ConfigSource) {
        var root: [String: ConfigNode] = [:]
        func copy(_ scribePath: String, to squirrelPath: String, in map: inout [String: ConfigNode]) {
            if let value = scribe.string(at: scribePath) {
                map.set(.scalar(value), at: squirrelPath)
            }
        }

        for key in ScribeKeyMap.globalKeys where key.scribe != "app_options/{app}/{option}" {
            copy(key.scribe, to: key.squirrel, in: &root)
        }
        if scribe.mapKeys(at: "app_options") != nil {
            root["app_options"] = ConfigNode(snapshotOf: scribe, at: "app_options")
        }

        let themes = Self.themes(in: scribe)
        var style: [String: ConfigNode] = [:]
        for key in ScribeKeyMap.schemeStyleKeys + ScribeKeyMap.globalStyleKeys {
            copy("appearance/\(key.scribe)", to: key.squirrel, in: &style)
        }
        let light = scribe.string(at: "appearance/theme")
        if let light {
            style["color_scheme"] = .scalar(light)
        }
        if let dark = scribe.string(at: "appearance/dark_theme") {
            style["color_scheme_dark"] = .scalar(themes[dark] == true ? "\(dark):dark" : dark)
        } else if let light, themes[light] == true {
            style["color_scheme_dark"] = .scalar("\(light):dark")
        }
        if !style.isEmpty {
            root["style"] = .map(style)
        }

        var presets: [String: ConfigNode] = [:]
        var served: [String] = []
        for id in scribe.mapKeys(at: "themes") ?? [] {
            guard let hasDark = themes[id] else { continue }
            presets[id] = Self.preset(theme: id, palette: "light", in: scribe)
            served.append(id)
            if hasDark {
                presets["\(id):dark"] = Self.preset(theme: id, palette: "dark", in: scribe)
                served.append("\(id):dark")
            }
        }
        if !presets.isEmpty {
            root["preset_color_schemes"] = .map(presets)
        }
        squirrelConfig = .map(root)
        servedPresetIDs = served
    }

    /// True for `preset_color_schemes/<id>` and everything under it when the
    /// preset is served from a Scribe theme, which replaces a Squirrel
    /// preset with the same ID as a whole.
    public func owns(_ squirrelPath: String) -> Bool {
        let segments = squirrelPath.drop { $0 == "/" }.split(separator: "/", omittingEmptySubsequences: false)
        return segments.count >= 2 && segments[0] == "preset_color_schemes"
            && servedPresetIDs.contains(String(segments[1]))
    }

    public func string(at path: String) -> String? { squirrelConfig.string(at: path) }
    public func bool(at path: String) -> Bool? { squirrelConfig.bool(at: path) }
    public func int(at path: String) -> Int? { squirrelConfig.int(at: path) }
    public func double(at path: String) -> Double? { squirrelConfig.double(at: path) }
    public func mapKeys(at path: String) -> [String]? { squirrelConfig.mapKeys(at: path) }
    public func listCount(at path: String) -> Int? { squirrelConfig.listCount(at: path) }

    /// The valid theme IDs under `themes`, each with whether it has a dark palette.
    static func themes(in scribe: some ConfigSource) -> [String: Bool] {
        var themes: [String: Bool] = [:]
        for id in scribe.mapKeys(at: "themes") ?? [] where ThemeID.isServable(id) {
            guard scribe.mapKeys(at: "themes/\(id)") != nil else { continue }
            themes[id] = scribe.mapKeys(at: "themes/\(id)/dark") != nil
        }
        return themes
    }

    /// One palette of a theme as a Squirrel preset.
    private static func preset(theme id: String, palette: String, in scribe: some ConfigSource) -> ConfigNode {
        let theme = "themes/\(id)"
        var preset: [String: ConfigNode] = [:]
        for key in ScribeKeyMap.themeMetadataKeys {
            if let value = scribe.string(at: "\(theme)/\(key.scribe)") {
                preset[key.squirrel] = .scalar(value)
            }
        }
        for key in ScribeKeyMap.schemeStyleKeys {
            let value = scribe.string(at: "\(theme)/\(palette)/style/\(key.scribe)")
                ?? scribe.string(at: "\(theme)/style/\(key.scribe)")
            if let value {
                preset[key.squirrel] = .scalar(value)
            }
        }
        for key in ScribeKeyMap.paletteColorKeys {
            let color = scribe.parsed(at: "\(theme)/\(palette)/\(key.scribe)") {
                RGBAColor(scribe: $0, colorSpace: .sRGB)
            }
            if let color {
                preset[key.squirrel] = .scalar(color.squirrelLiteral)
            }
        }
        return .map(preset)
    }
}

/// squirrel.yaml with scribe.yaml on top, key by key: each getter returns the
/// Scribe value when there is one and Squirrel's otherwise, except under a
/// preset served from a Scribe theme, which never reads Squirrel's preset of
/// the same ID. Maps list the Scribe keys first, then Squirrel's others.
public struct MergedConfigSource<Squirrel: ConfigSource>: ConfigSource {
    public var scribe: ScribeConfigSource
    public var squirrel: Squirrel

    public init(scribe: ScribeConfigSource, squirrel: Squirrel) {
        self.scribe = scribe
        self.squirrel = squirrel
    }

    public init(squirrel: Squirrel, scribe: some ConfigSource) {
        self.init(scribe: ScribeConfigSource(scribe: scribe), squirrel: squirrel)
    }

    public func string(at path: String) -> String? {
        read(path) { $0.string(at: path) }
    }

    public func bool(at path: String) -> Bool? {
        read(path) { $0.bool(at: path) }
    }

    public func int(at path: String) -> Int? {
        read(path) { $0.int(at: path) }
    }

    public func double(at path: String) -> Double? {
        read(path) { $0.double(at: path) }
    }

    public func mapKeys(at path: String) -> [String]? {
        let scribeKeys = scribe.mapKeys(at: path)
        if scribe.owns(path) {
            return scribeKeys
        }
        guard let squirrelKeys = squirrel.mapKeys(at: path) else { return scribeKeys }
        guard let scribeKeys else { return squirrelKeys }
        return scribeKeys + squirrelKeys.filter { !scribeKeys.contains($0) }
    }

    public func listCount(at path: String) -> Int? {
        read(path) { $0.listCount(at: path) }
    }

    public func parsed<T>(at path: String, _ parse: (String) -> T?) -> T? {
        read(path) { $0.parsed(at: path, parse) }
    }

    private func read<T>(_ path: String, _ get: (any ConfigSource) -> T?) -> T? {
        if let value = get(scribe) {
            return value
        }
        return scribe.owns(path) ? nil : get(squirrel)
    }
}

extension MergedConfigSource: Equatable where Squirrel: Equatable {}
extension MergedConfigSource: Sendable where Squirrel: Sendable {}

private extension Dictionary where Key == String, Value == ConfigNode {
    /// Sets a value at a path of map keys, creating maps on the way.
    mutating func set(_ value: ConfigNode, at path: String) {
        var keys = path.split(separator: "/").map(String.init)
        let last = keys.removeLast()
        guard let first = keys.first else {
            self[last] = value
            return
        }
        var child: [String: ConfigNode] = if case .map(let map) = self[first] { map } else { [:] }
        child.set(value, at: (keys.dropFirst() + [last]).joined(separator: "/"))
        self[first] = .map(child)
    }
}
