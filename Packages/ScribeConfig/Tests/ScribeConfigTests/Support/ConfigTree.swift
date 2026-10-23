import ScribeConfig

/// A config with each value at its path of map keys, creating maps on the
/// way; a later value at the same path wins.
func configTree(_ values: [(String, ConfigNode)]) -> ConfigNode {
    var root = ConfigNode.map([:])
    for (path, value) in values {
        root = setting(value, at: path.split(separator: "/").map(String.init)[...], in: root)
    }
    return root
}

fileprivate func setting(_ value: ConfigNode, at keys: ArraySlice<String>, in node: ConfigNode) -> ConfigNode {
    guard let key = keys.first else { return value }
    var map: [String: ConfigNode] = if case .map(let map) = node { map } else { [:] }
    map[key] = setting(value, at: keys.dropFirst(), in: map[key] ?? .map([:]))
    return .map(map)
}

extension ConfigNode {
    /// This config with `value` at `path`, creating maps on the way.
    func setting(_ value: ConfigNode, at path: String) -> ConfigNode {
        ScribeConfigTests.setting(value, at: path.split(separator: "/").map(String.init)[...], in: self)
    }

    /// This config without the key at `path`.
    func removing(_ path: String) -> ConfigNode {
        var keys = path.split(separator: "/").map(String.init)
        let last = keys.removeLast()
        guard case .map(var map) = self else { return self }
        if let first = keys.first {
            map[first] = map[first]?.removing((keys.dropFirst() + [last]).joined(separator: "/"))
        } else {
            map[last] = nil
        }
        return .map(map)
    }
}
