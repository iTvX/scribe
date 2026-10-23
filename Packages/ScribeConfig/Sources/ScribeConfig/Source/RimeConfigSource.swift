import RimeKit

extension RimeConfigReader: ConfigSource {}

extension LibrimeEngine {
    /// Runs `body` with the deployed squirrel.yaml and scribe.yaml, using an
    /// empty Scribe config when scribe.yaml cannot be opened. Nil when
    /// squirrel.yaml cannot be opened.
    fileprivate func withSquirrelAndScribe<T>(_ body: (RimeConfigReader, any ConfigSource) -> T) -> T? {
        withConfig(.deployed("squirrel")) { squirrel in
            withConfig(.deployed("scribe")) { body(squirrel, $0) } ?? body(squirrel, ConfigNode.null)
        }
    }
}

extension ScribeSettings {
    /// The settings from the deployed squirrel.yaml and scribe.yaml, or nil
    /// if librime cannot open squirrel.yaml (for instance while the engine is
    /// stopped).
    @MainActor
    public static func load(from engine: LibrimeEngine) -> ScribeSettings? {
        engine.withSquirrelAndScribe { ScribeSettings(squirrel: $0, scribe: $1) }
    }
}

extension Appearance {
    /// The themes for a schema, from the deployed squirrel.yaml, scribe.yaml
    /// and the schema's `style`. An empty schema ID or one starting with "."
    /// (which Squirrel skips) leaves the schema out.
    @MainActor
    public static func load(from engine: LibrimeEngine, schemaID: String) -> Appearance? {
        engine.withSquirrelAndScribe { squirrel, scribe in
            guard !schemaID.isEmpty, !schemaID.hasPrefix(".") else {
                return Appearance(squirrel: squirrel, scribe: scribe)
            }
            return engine.withConfig(.schema(schemaID)) { schema in
                Appearance(squirrel: squirrel, scribe: scribe, schema: schema)
            } ?? Appearance(squirrel: squirrel, scribe: scribe)
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

extension ScribeConversion {
    /// The conversion of the deployed squirrel.yaml against `baselineYAML`
    /// (Scribe's own squirrel.yaml), keeping what the deployed scribe.yaml
    /// already sets. Nil if librime cannot open squirrel.yaml or parse the
    /// baseline.
    @MainActor
    public static func load(from engine: LibrimeEngine, baselineYAML: String) -> ScribeConversion? {
        engine.withSquirrelAndScribe { user, scribe in
            engine.withConfig(.yaml(baselineYAML)) { baseline in
                ScribeConverter.convert(user: user, baseline: baseline, scribe: scribe)
            }
        } ?? nil
    }
}
