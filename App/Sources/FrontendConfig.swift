import RimeKit

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
}
