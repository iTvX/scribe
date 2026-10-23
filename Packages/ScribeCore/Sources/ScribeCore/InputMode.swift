/// The input modes Scribe registers with the system.
public enum InputMode: String, CaseIterable, Sendable {
    case hans = "Hans"
    case hant = "Hant"

    /// The text input source ID of this mode, such as
    /// `io.github.itvx.inputmethod.Scribe.Hans`.
    public func inputSourceID(bundleIdentifier: String) -> String {
        "\(bundleIdentifier).\(rawValue)"
    }

    /// The mode a text input source ID refers to, or nil if it is not one of
    /// this bundle's modes.
    public init?(inputSourceID: String, bundleIdentifier: String) {
        let prefix = bundleIdentifier + "."
        guard inputSourceID.hasPrefix(prefix) else { return nil }
        self.init(rawValue: String(inputSourceID.dropFirst(prefix.count)))
    }
}
