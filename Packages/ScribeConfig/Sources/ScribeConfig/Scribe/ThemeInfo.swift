/// A theme the Settings app can offer for `appearance/theme`.
public struct ThemeInfo: Equatable, Sendable {
    public enum Origin: Sendable {
        /// "native": system colours that follow the appearance.
        case native
        /// A theme under `themes` in scribe.yaml.
        case scribe
        /// A preset under `preset_color_schemes` in squirrel.yaml.
        case squirrel
    }

    public var id: String
    public var name: String?
    public var author: String?
    /// Whether choosing it also sets a dark theme: a Scribe theme with a dark
    /// palette, or native.
    public var hasDark: Bool
    public var origin: Origin

    public init(id: String, name: String?, author: String?, hasDark: Bool, origin: Origin) {
        self.id = id
        self.name = name
        self.author = author
        self.hasDark = hasDark
        self.origin = origin
    }
}

/// Native first, then the Scribe themes, then the Squirrel presets, each in
/// librime's key order. A Scribe theme replaces a Squirrel preset with the
/// same ID, and the dark presets Scribe serves ("{id}:dark") are not listed.
public func availableThemes(scribe: some ConfigSource, squirrel: some ConfigSource) -> [ThemeInfo] {
    var themes = [ThemeInfo(
        id: "native",
        name: squirrel.string(at: "preset_color_schemes/native/name"),
        author: nil,
        hasDark: true,
        origin: .native
    )]
    let scribeThemes = ScribeConfigSource.themes(in: scribe)
    for id in scribe.mapKeys(at: "themes") ?? [] {
        guard let hasDark = scribeThemes[id] else { continue }
        themes.append(ThemeInfo(
            id: id,
            name: scribe.string(at: "themes/\(id)/name"),
            author: scribe.string(at: "themes/\(id)/author"),
            hasDark: hasDark,
            origin: .scribe
        ))
    }
    func isServedByScribe(_ id: String) -> Bool {
        scribeThemes[id] != nil || id.hasSuffix(":dark") && scribeThemes[String(id.dropLast(5))] == true
    }
    for id in PresetColorScheme.ids(in: squirrel) where id != "native" && !isServedByScribe(id) {
        themes.append(ThemeInfo(
            id: id,
            name: squirrel.string(at: "preset_color_schemes/\(id)/name"),
            author: squirrel.string(at: "preset_color_schemes/\(id)/author"),
            hasDark: false,
            origin: .squirrel
        ))
    }
    return themes
}
