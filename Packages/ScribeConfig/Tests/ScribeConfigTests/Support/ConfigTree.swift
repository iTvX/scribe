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

private func setting(_ value: ConfigNode, at keys: ArraySlice<String>, in node: ConfigNode) -> ConfigNode {
    guard let key = keys.first else { return value }
    var map: [String: ConfigNode] = if case .map(let map) = node { map } else { [:] }
    map[key] = setting(value, at: keys.dropFirst(), in: map[key] ?? .map([:]))
    return .map(map)
}
