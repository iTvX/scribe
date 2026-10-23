internal import librime

/// Where a config comes from.
public enum RimeConfigOrigin: Sendable {
    /// A deployed config by ID (`config_open`), such as "squirrel" for
    /// build/squirrel.yaml after deploying.
    case deployed(String)
    /// A deployed schema by ID (`schema_open`).
    case schema(String)
    /// YAML text, parsed only (`config_init` and `config_load_string`):
    /// no `__include` or `__patch`, and the engine need not be running.
    case yaml(String)
}

/// A config opened read-only. Valid only inside `withConfig`'s body; not Sendable.
///
/// Paths use librime's syntax: "/" separates map keys, and "@N" or "@last"
/// index a list. Each getter returns nil when librime's does not succeed.
public struct RimeConfigReader {
    private let api: UnsafeMutablePointer<RimeApi_stdbool>
    private let config: UnsafeMutablePointer<RimeConfig>

    fileprivate init(api: UnsafeMutablePointer<RimeApi_stdbool>, config: UnsafeMutablePointer<RimeConfig>) {
        self.api = api
        self.config = config
    }

    /// The scalar at `path`; nil for a map, a list or a null.
    public func string(at path: String) -> String? {
        api.pointee.config_get_cstring(config, path).map { String(cString: $0) }
    }

    public func bool(at path: String) -> Bool? {
        var value = false
        return api.pointee.config_get_bool(config, path, &value) ? value : nil
    }

    public func int(at path: String) -> Int? {
        var value: Int32 = 0
        return api.pointee.config_get_int(config, path, &value) ? Int(value) : nil
    }

    public func double(at path: String) -> Double? {
        var value = 0.0
        return api.pointee.config_get_double(config, path, &value) ? value : nil
    }

    /// The keys of the map at `path` in `config_next` order, or nil unless the
    /// node is a map.
    public func mapKeys(at path: String) -> [String]? {
        var iterator = RimeConfigIterator()
        guard api.pointee.config_begin_map(&iterator, config, path) else { return nil }
        defer { api.pointee.config_end(&iterator) }
        var keys: [String] = []
        while api.pointee.config_next(&iterator) {
            keys.append(String(cString: iterator.key))
        }
        return keys
    }

    /// Nil unless the node is a list.
    public func listCount(at path: String) -> Int? {
        var iterator = RimeConfigIterator()
        guard api.pointee.config_begin_list(&iterator, config, path) else { return nil }
        defer { api.pointee.config_end(&iterator) }
        var count = 0
        while api.pointee.config_next(&iterator) {
            count += 1
        }
        return count
    }
}

extension LibrimeEngine {
    /// Opens a config, runs `body` with it and closes it. Returns nil if the
    /// config cannot be opened. librime opens a deployed config or schema that
    /// has no file as an empty config, but not while the engine is stopped.
    public func withConfig<T>(_ origin: RimeConfigOrigin, _ body: (RimeConfigReader) throws -> T) rethrows -> T? {
        let config = UnsafeMutablePointer<RimeConfig>.allocate(capacity: 1)
        config.initialize(to: RimeConfig())
        defer {
            if config.pointee.ptr != nil {
                _ = api.pointee.config_close(config)
            }
            config.deallocate()
        }
        let opened = switch origin {
        case .deployed(let id):
            api.pointee.config_open(id, config)
        case .schema(let id):
            api.pointee.schema_open(id, config)
        case .yaml(let yaml):
            api.pointee.config_init(config) && api.pointee.config_load_string(config, yaml)
        }
        guard opened else { return nil }
        return try body(RimeConfigReader(api: api, config: config))
    }

    /// Updates the deployed copy of a config file the way Squirrel does after
    /// `start_maintenance`: `deployConfigFile("squirrel.yaml", versionKey:
    /// "config_version")` trashes an outdated user copy and rebuilds
    /// build/squirrel.yaml with its patches. Runs synchronously.
    public func deployConfigFile(_ fileName: String, versionKey: String) -> Bool {
        // The task lives in librime's deployer modules, which start_maintenance
        // loads. Without traits, deployer_initialize only loads those modules
        // (again, harmlessly) and keeps the directories set by start.
        api.pointee.deployer_initialize(nil)
        return api.pointee.deploy_config_file(fileName, versionKey)
    }
}
