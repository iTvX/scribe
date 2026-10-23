/// The light and dark themes, as Squirrel loads them into its panel.
public struct Appearance: Equatable, Sendable {
    /// From `style/color_scheme`; also used in dark mode when there is no dark theme.
    public var light: Theme
    /// From `style/color_scheme_dark`; nil when that key is absent.
    public var dark: Theme?

    public init(light: Theme, dark: Theme?) {
        self.light = light
        self.dark = dark
    }

    /// With only a non-native light theme, Squirrel draws the panel in the
    /// light (aqua) appearance even in dark mode.
    public var forcesLightAppearance: Bool {
        dark == nil && !light.isNative
    }

    public func theme(isDark: Bool) -> Theme {
        isDark ? dark ?? light : light
    }

    /// The themes of squirrel.yaml.
    public init(squirrel: some ConfigSource) {
        light = Theme(source: squirrel, colorSchemeKey: "style/color_scheme")
        dark = squirrel.string(at: "style/color_scheme_dark") == nil
            ? nil
            : Theme(source: squirrel, colorSchemeKey: "style/color_scheme_dark")
    }

    /// The themes for a schema, following Squirrel's loadSettings(for:): when
    /// the schema has a `style` map (even an empty one), each key is read from
    /// the schema first and squirrel.yaml second, colour schemes included.
    /// Otherwise the schema is ignored.
    public init(squirrel: some ConfigSource, schema: some ConfigSource) {
        if schema.mapKeys(at: "style") != nil {
            self.init(squirrel: FallbackConfigSource(primary: schema, fallback: squirrel))
        } else {
            self.init(squirrel: squirrel)
        }
    }
}
