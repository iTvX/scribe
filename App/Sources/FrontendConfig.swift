import RimeKit
import ScribeConfig

/// The frontend's own config files, which librime's workspace deploy leaves
/// out.
@MainActor
enum FrontendConfig {
    static let files = ["squirrel.yaml", "scribe.yaml"]

    /// Starts maintenance and, as Squirrel does, deploys the frontend's config
    /// files with the user's patches while it runs. Settings apps change
    /// scribe.custom.yaml and ask only for a reload, so every deploy goes
    /// through here. Returns whether maintenance started.
    @discardableResult
    static func startMaintenance(_ engine: LibrimeEngine, fullCheck: Bool) -> Bool {
        guard engine.startMaintenance(fullCheck: fullCheck) else { return false }
        for file in files {
            _ = engine.deployConfigFile(file, versionKey: "config_version")
        }
        return true
    }

    /// The candidate window's themes and the sessions' configuration while
    /// `schemaID` is in use: squirrel.yaml and scribe.yaml, with the schema's
    /// style on top, as Squirrel loads them on a schema change. Nil if
    /// librime cannot open the configs.
    static func load(
        _ engine: LibrimeEngine,
        settings: ScribeSettings,
        schemaID: String,
        isDark: Bool
    ) -> (appearance: Appearance, configuration: SessionConfiguration)? {
        guard let appearance = Appearance.load(from: engine, schemaID: schemaID) else { return nil }
        return (appearance, SessionConfiguration(settings: settings, theme: appearance.theme(isDark: isDark)))
    }
}
