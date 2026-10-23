extension ConfigNode {
    /// A copy with `value` at a path of map keys, creating maps on the way and
    /// replacing anything else in the way.
    func setting(_ path: String, to value: ConfigNode) -> ConfigNode {
        setting(path.split(separator: "/").map(String.init)[...], to: value)
    }

    /// A copy without the value at a path of map keys.
    func removing(_ path: String) -> ConfigNode {
        removing(path.split(separator: "/").map(String.init)[...])
    }

    private func setting(_ keys: ArraySlice<String>, to value: ConfigNode) -> ConfigNode {
        guard let key = keys.first else { return value }
        var map: [String: ConfigNode] = if case .map(let map) = self { map } else { [:] }
        map[key] = (map[key] ?? .null).setting(keys.dropFirst(), to: value)
        return .map(map)
    }

    private func removing(_ keys: ArraySlice<String>) -> ConfigNode {
        guard let key = keys.first, case .map(var map) = self, let child = map[key] else { return self }
        if keys.count == 1 {
            map.removeValue(forKey: key)
        } else {
            map[key] = child.removing(keys.dropFirst())
        }
        return .map(map)
    }

    /// Equal as librime reads them: the same scalar text, or numbers of equal value.
    func sameValue(as other: ConfigNode?) -> Bool {
        guard let other else { return false }
        if case .scalar(let a) = self, case .scalar(let b) = other, a != b {
            guard let x = LibrimeScalar.double(a), let y = LibrimeScalar.double(b) else { return false }
            return x == y
        }
        return self == other
    }
}
