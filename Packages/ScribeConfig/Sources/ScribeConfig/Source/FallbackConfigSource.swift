/// Reads `primary` first and `fallback` where the primary has no usable
/// value: SquirrelConfig's chain from a schema config to squirrel.yaml.
///
/// The fallback applies per getter, so a primary "maybe" read as a bool falls
/// back to the fallback's bool, and a primary colour that does not parse
/// falls back to the fallback's colour.
public struct FallbackConfigSource<Primary: ConfigSource, Fallback: ConfigSource>: ConfigSource {
    public var primary: Primary
    public var fallback: Fallback

    public init(primary: Primary, fallback: Fallback) {
        self.primary = primary
        self.fallback = fallback
    }

    public func string(at path: String) -> String? {
        primary.string(at: path) ?? fallback.string(at: path)
    }

    public func bool(at path: String) -> Bool? {
        primary.bool(at: path) ?? fallback.bool(at: path)
    }

    public func int(at path: String) -> Int? {
        primary.int(at: path) ?? fallback.int(at: path)
    }

    public func double(at path: String) -> Double? {
        primary.double(at: path) ?? fallback.double(at: path)
    }

    public func mapKeys(at path: String) -> [String]? {
        primary.mapKeys(at: path) ?? fallback.mapKeys(at: path)
    }

    public func listCount(at path: String) -> Int? {
        primary.listCount(at: path) ?? fallback.listCount(at: path)
    }

    public func parsed<T>(at path: String, _ parse: (String) -> T?) -> T? {
        primary.parsed(at: path, parse) ?? fallback.parsed(at: path, parse)
    }
}

extension FallbackConfigSource: Equatable where Primary: Equatable, Fallback: Equatable {}
extension FallbackConfigSource: Sendable where Primary: Sendable, Fallback: Sendable {}
