/// Read-only access to a Rime config by librime path: "/" separates map keys,
/// "@N" or "@last" index a list.
///
/// The getters follow librime's `config_get_*` functions: each returns nil
/// when the node is missing, is not a scalar, or does not convert.
public protocol ConfigSource {
    /// The scalar at `path`; nil for a map, a list or a null.
    func string(at path: String) -> String?
    /// "true" or "false" in any case.
    func bool(at path: String) -> Bool?
    func int(at path: String) -> Int?
    func double(at path: String) -> Double?
    /// The keys of the map at `path` in librime's order, or nil unless the
    /// node is a map.
    func mapKeys(at path: String) -> [String]?
    /// Nil unless the node is a list.
    func listCount(at path: String) -> Int?
    /// The scalar at `path` run through `parse`. FallbackConfigSource overrides
    /// this so an unparsable primary value falls back, like SquirrelConfig.getColor.
    func parsed<T>(at path: String, _ parse: (String) -> T?) -> T?
}

extension ConfigSource {
    public func parsed<T>(at path: String, _ parse: (String) -> T?) -> T? {
        string(at: path).flatMap(parse)
    }
}
