import Foundation

/// An in-memory Rime config tree that reads exactly like librime 1.17.0
/// (`ConfigData::Traverse` and `ConfigValue`), for tests and snapshots.
///
/// `.null` stands for a YAML null: as a map value, the key exists (it is in
/// `mapKeys`) but every getter returns nil.
public indirect enum ConfigNode: Equatable, Sendable, Codable {
    case null
    case scalar(String)
    case list([ConfigNode])
    case map([String: ConfigNode])
}

extension ConfigNode: ConfigSource {
    public func string(at path: String) -> String? {
        guard case .scalar(let value) = node(at: path) else { return nil }
        return value
    }

    public func bool(at path: String) -> Bool? {
        string(at: path).flatMap(LibrimeScalar.bool)
    }

    public func int(at path: String) -> Int? {
        string(at: path).flatMap(LibrimeScalar.int)
    }

    public func double(at path: String) -> Double? {
        string(at: path).flatMap(LibrimeScalar.double)
    }

    /// Sorted by UTF-8 bytes, the order of librime's `std::map`.
    public func mapKeys(at path: String) -> [String]? {
        guard case .map(let map) = node(at: path) else { return nil }
        return map.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    public func listCount(at path: String) -> Int? {
        guard case .list(let list) = node(at: path) else { return nil }
        return list.count
    }

    /// The node at `path`, or nil where librime finds no item. A `.null` value
    /// is returned as nil too, since librime stores it as a null pointer.
    func node(at path: String) -> ConfigNode? {
        let bytes = Array(path.utf8)
        if bytes.isEmpty || bytes == [UInt8(ascii: "/")] {
            return nonNull(self)
        }
        let trimmed = bytes.drop { $0 == UInt8(ascii: "/") }
        var current: ConfigNode? = nonNull(self)
        for segment in trimmed.split(separator: UInt8(ascii: "/"), omittingEmptySubsequences: false) {
            let key = Array(segment)
            if Self.isListItemReference(key) {
                guard case .list(let list) = current else { return nil }
                let index = Self.resolveListIndex(key, count: list.count)
                current = index < list.count ? nonNull(list[index]) : nil
            } else {
                guard case .map(let map) = current else { return nil }
                current = Self.value(in: map, forKey: String(decoding: key, as: UTF8.self))
            }
        }
        return current
    }

    private func nonNull(_ node: ConfigNode) -> ConfigNode? {
        if case .null = node { nil } else { node }
    }

    /// librime compares keys byte for byte, while a Swift dictionary treats
    /// canonically equivalent strings as the same key.
    private static func value(in map: [String: ConfigNode], forKey key: String) -> ConfigNode? {
        guard let index = map.index(forKey: key), map[index].key.utf8.elementsEqual(key.utf8) else {
            return nil
        }
        let value = map[index].value
        if case .null = value { return nil }
        return value
    }

    /// `ConfigData::IsListItemReference`: "@" followed by a letter or digit.
    private static func isListItemReference(_ key: [UInt8]) -> Bool {
        guard key.count > 1, key[0] == UInt8(ascii: "@") else { return false }
        let next = key[1]
        return (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(next)
            || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(next)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(next)
    }

    /// `ConfigData::ResolveListIndex` with `read_only` true, including its
    /// `unsigned int` arithmetic: "@next" is one past the end, "@before N" is
    /// N and "@after N" is N + 1.
    private static func resolveListIndex(_ key: [UInt8], count: Int) -> Int {
        func matches(_ word: String, at cursor: Int) -> Bool {
            key[cursor...].starts(with: word.utf8)
        }
        var cursor = 1
        var index: UInt32 = 0
        if matches("next", at: cursor) {
            cursor += 4
            index = UInt32(truncatingIfNeeded: count)
        } else if matches("before", at: cursor) {
            cursor += 6
        } else if matches("after", at: cursor) {
            cursor += 5
            index &+= 1
        }
        if cursor < key.count, key[cursor] == UInt8(ascii: " ") {
            cursor += 1
        }
        if matches("last", at: cursor) {
            index &+= UInt32(truncatingIfNeeded: count)
            if index != 0 {
                index &-= 1
            }
        } else {
            let rest = Array(key[cursor...]) + [0]
            let number = rest.withUnsafeBufferPointer { buffer in
                buffer.withMemoryRebound(to: CChar.self) { strtoul($0.baseAddress!, nil, 10) }
            }
            index &+= UInt32(truncatingIfNeeded: number)
        }
        return Int(index)
    }
}

extension ConfigNode: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .scalar(value)
    }
}

extension ConfigNode: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .scalar(String(value))
    }
}

extension ConfigNode: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .scalar(String(value))
    }
}

extension ConfigNode: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .scalar(value ? "true" : "false")
    }
}

extension ConfigNode: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension ConfigNode: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: ConfigNode...) {
        self = .list(elements)
    }
}

extension ConfigNode: ExpressibleByDictionaryLiteral {
    /// A repeated key keeps its last value, as librime does when loading YAML.
    public init(dictionaryLiteral elements: (String, ConfigNode)...) {
        self = .map(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

extension ConfigNode {
    /// A copy of the tree at `path` in `source`, read through its getters:
    /// maps by `mapKeys`, lists by `listCount`, scalars by `string`, and
    /// anything else as `.null`. Keys that librime cannot address by path
    /// (containing "/", or "@" followed by a letter or digit) read as `.null`.
    public init(snapshotOf source: some ConfigSource, at path: String = "") {
        func child(_ key: String) -> String {
            path.isEmpty || path == "/" ? key : "\(path)/\(key)"
        }
        if let keys = source.mapKeys(at: path) {
            var map: [String: ConfigNode] = [:]
            for key in keys {
                map[key] = ConfigNode(snapshotOf: source, at: child(key))
            }
            self = .map(map)
        } else if let count = source.listCount(at: path) {
            self = .list((0..<count).map { ConfigNode(snapshotOf: source, at: child("@\($0)")) })
        } else if let value = source.string(at: path) {
            self = .scalar(value)
        } else {
            self = .null
        }
    }
}
