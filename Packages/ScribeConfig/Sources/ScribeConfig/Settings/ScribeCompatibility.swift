/// Scribe's compatibility settings from its own scribe.yaml, which deploys
/// like squirrel.yaml and is patched by scribe.custom.yaml.
public struct ScribeCompatibility: Equatable, Sendable {
    /// Whether to tell librime the frontend is Squirrel, for Lua scripts that
    /// check which frontend runs (`compatibility/report_as_squirrel`).
    public var reportsAsSquirrel: Bool

    /// librime's `distribution_code_name`.
    public var distributionCodeName: String {
        reportsAsSquirrel ? "Squirrel" : "Scribe"
    }

    /// librime's `distribution_name`.
    public var distributionName: String {
        reportsAsSquirrel ? "鼠鬚管" : "Scribe"
    }

    public init(reportsAsSquirrel: Bool = false) {
        self.reportsAsSquirrel = reportsAsSquirrel
    }

    /// A missing or non-bool value does not report as Squirrel.
    public init(scribe: some ConfigSource) {
        reportsAsSquirrel = scribe.bool(at: "compatibility/report_as_squirrel") ?? false
    }
}
