import RimeKit

extension RimeConfigReader: ConfigSource {}

extension ScribeSettings {
    /// The settings from the deployed squirrel.yaml, or nil if librime cannot
    /// open it (for instance while the engine is stopped).
    @MainActor
    public static func load(from engine: LibrimeEngine) -> ScribeSettings? {
        engine.withConfig(.deployed("squirrel")) { ScribeSettings(squirrel: $0) }
    }
}

extension Appearance {
    /// The themes for a schema, from the deployed squirrel.yaml and the
    /// schema's `style`. An empty schema ID or one starting with "." (which
    /// Squirrel skips) gives the themes of squirrel.yaml alone.
    @MainActor
    public static func load(from engine: LibrimeEngine, schemaID: String) -> Appearance? {
        engine.withConfig(.deployed("squirrel")) { squirrel in
            guard !schemaID.isEmpty, !schemaID.hasPrefix(".") else {
                return Appearance(squirrel: squirrel)
            }
            return engine.withConfig(.schema(schemaID)) { schema in
                Appearance(squirrel: squirrel, schema: schema)
            } ?? Appearance(squirrel: squirrel)
        }
    }
}

extension ScribeCompatibility {
    /// The compatibility settings from the deployed scribe.yaml, or nil if
    /// librime cannot open it.
    @MainActor
    public static func load(from engine: LibrimeEngine) -> ScribeCompatibility? {
        engine.withConfig(.deployed("scribe")) { ScribeCompatibility(scribe: $0) }
    }
}
