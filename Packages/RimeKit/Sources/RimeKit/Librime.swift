internal import librime

/// The librime library linked into this process.
public enum Librime {
    /// The version librime reports, such as "1.17.0".
    ///
    /// Reading it does not set up or start the engine.
    public static var version: String? {
        guard let api = rime_get_api_stdbool(),
              let getVersion = api.pointee.get_version,
              let version = getVersion()
        else { return nil }
        return String(cString: version)
    }
}
