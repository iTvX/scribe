/// Writes `ConfigNode` values as block-style YAML lines, with map keys in
/// librime's order and scalars quoted only when they need it.
struct PatchRenderer {
    /// The indentation step for nested lines.
    var unit: Int

    /// The lines of a `key: value` entry at `indent`. `comment` follows the
    /// key line, spaces included.
    func entry(rawKey: String, value: ConfigNode, indent: Int, comment: String = "") -> [String] {
        let pad = String(repeating: " ", count: indent)
        if let inline = Self.inline(value) {
            return ["\(pad)\(rawKey): \(inline)\(comment)"]
        }
        return ["\(pad)\(rawKey):\(comment)"] + block(value, column: indent + unit)
    }

    /// A key as a new entry writes it.
    static func key(_ key: String) -> String {
        scalar(key)
    }

    /// A scalar, plain when that reads back as the same string, else double-quoted.
    static func scalar(_ value: String) -> String {
        isPlain(value) ? value : quoted(value)
    }

    /// The text of a value that fits on its key's line, or nil for a
    /// non-empty list or map.
    private static func inline(_ value: ConfigNode) -> String? {
        switch value {
        case .null: "~"
        case .scalar(let text): scalar(text)
        case .list(let items): items.isEmpty ? "[]" : nil
        case .map(let map): map.isEmpty ? "{}" : nil
        }
    }

    /// The lines of a non-empty list or map whose content starts at `column`.
    private func block(_ value: ConfigNode, column: Int) -> [String] {
        let pad = String(repeating: " ", count: column)
        switch value {
        case .list(let items):
            return items.flatMap { item -> [String] in
                if let inline = Self.inline(item) {
                    return ["\(pad)- \(inline)"]
                }
                // The item's first line goes after the dash; the rest line up under it.
                var lines = block(item, column: column + 2)
                lines[0] = pad + "- " + lines[0].dropFirst(column + 2)
                return lines
            }
        case .map(let map):
            return map.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.flatMap { key -> [String] in
                let value = map[key] ?? .null
                if let inline = Self.inline(value) {
                    return ["\(pad)\(Self.key(key)): \(inline)"]
                }
                return ["\(pad)\(Self.key(key)):"] + block(value, column: column + unit)
            }
        case .null, .scalar:
            return []
        }
    }

    /// Matches `[A-Za-z0-9_][A-Za-z0-9_+./@-]*` and is not a YAML null.
    private static func isPlain(_ value: String) -> Bool {
        guard !["null", "Null", "NULL", "~"].contains(value) else { return false }
        func isWordByte(_ byte: UInt8) -> Bool {
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || byte == UInt8(ascii: "_")
        }
        let bytes = Array(value.utf8)
        guard let first = bytes.first, isWordByte(first) else { return false }
        return bytes.dropFirst().allSatisfy { isWordByte($0) || "+./@-".utf8.contains($0) }
    }

    private static func quoted(_ value: String) -> String {
        var text = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "\n": text += "\\n"
            case "\t": text += "\\t"
            case "\r": text += "\\r"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                text += "\\x" + hex(scalar.value, digits: 2)
            case _ where (0x80...0x9F).contains(scalar.value) || scalar.value == 0x2028 || scalar.value == 0x2029:
                text += "\\u" + hex(scalar.value, digits: 4)
            default:
                text.unicodeScalars.append(scalar)
            }
        }
        return text + "\""
    }

    private static func hex(_ value: UInt32, digits: Int) -> String {
        let text = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(digits - text.count, 0)) + text
    }
}
