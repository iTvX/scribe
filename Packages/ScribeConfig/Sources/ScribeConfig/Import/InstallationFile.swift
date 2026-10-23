import Foundation

/// librime's `installation.yaml`, reduced to its top-level scalar values.
///
/// librime writes this file itself, so a full YAML parser is not needed:
/// nested values, flow collections and block scalars are ignored.
struct InstallationFile: Equatable {
    var values: [String: String] = [:]

    var installationID: String? { values["installation_id"] }
    var syncDirectory: String? { values["sync_dir"] }

    init(parsing text: String) {
        for line in text.split(whereSeparator: \.isNewline) {
            guard let first = line.first, first != " ", first != "\t", first != "#",
                  !line.hasPrefix("---"), !line.hasPrefix("..."),
                  let (key, rest) = Self.splitKey(line),
                  let value = Self.scalar(rest)
            else { continue }
            values[key] = value
        }
    }

    /// The `installation.yaml` an import writes; librime adds the rest on the
    /// first deploy.
    static func contents(installationID: String, syncDirectory: String?) -> String {
        var text = "installation_id: \(quoted(installationID))\n"
        if let syncDirectory {
            text += "sync_dir: \(quoted(syncDirectory))\n"
        }
        return text
    }

    /// Splits `key: value` at the first colon followed by a space or the end of the line.
    private static func splitKey(_ line: Substring) -> (String, Substring)? {
        var index = line.startIndex
        while let colon = line[index...].firstIndex(of: ":") {
            let next = line.index(after: colon)
            if next == line.endIndex || line[next] == " " || line[next] == "\t" {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                return key.isEmpty ? nil : (key, line[next...])
            }
            index = next
        }
        return nil
    }

    /// A plain, single-quoted or double-quoted scalar; nil for null, empty
    /// values (a nested mapping follows) and anything else.
    private static func scalar(_ text: Substring) -> String? {
        let value = text.drop { $0 == " " || $0 == "\t" }
        switch value.first {
        case nil, "#", "[", "{", "|", ">":
            return nil
        case "\"":
            return doubleQuoted(value.dropFirst())
        case "'":
            return singleQuoted(value.dropFirst())
        default:
            var plain = value
            if let comment = plain.firstRange(of: " #") ?? plain.firstRange(of: "\t#") {
                plain = plain[..<comment.lowerBound]
            }
            let result = plain.trimmingCharacters(in: .whitespaces)
            return ["~", "null", "Null", "NULL"].contains(result) ? nil : result
        }
    }

    private static func singleQuoted(_ text: Substring) -> String? {
        var result = ""
        var characters = text[...]
        while let character = characters.popFirst() {
            if character == "'" {
                guard characters.first == "'" else { return result }
                characters.removeFirst()
            }
            result.append(character)
        }
        return nil
    }

    private static func doubleQuoted(_ text: Substring) -> String? {
        var result = String.UnicodeScalarView()
        var scalars = text.unicodeScalars[...]
        while let scalar = scalars.popFirst() {
            switch scalar {
            case "\"":
                return String(result)
            case "\\":
                guard let escape = scalars.popFirst() else { return nil }
                switch escape {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "0": result.append("\0")
                case "x", "u", "U":
                    let length = escape == "x" ? 2 : escape == "u" ? 4 : 8
                    guard var code = hexValue(&scalars, length: length) else { return nil }
                    // A UTF-16 surrogate pair written as two \u escapes.
                    if (0xD800..<0xDC00).contains(code), scalars.starts(with: "\\u".unicodeScalars) {
                        var lookahead = scalars.dropFirst(2)
                        if let low = hexValue(&lookahead, length: 4), (0xDC00..<0xE000).contains(low) {
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                            scalars = lookahead
                        }
                    }
                    guard let decoded = Unicode.Scalar(code) else { return nil }
                    result.append(decoded)
                default:
                    // \\, \", \/ and anything librime would not write.
                    result.append(escape)
                }
            default:
                result.append(scalar)
            }
        }
        return nil
    }

    private static func hexValue(_ scalars: inout Substring.UnicodeScalarView, length: Int) -> UInt32? {
        let digits = scalars.prefix(length)
        guard digits.count == length, let value = UInt32(String(Substring(digits)), radix: 16) else { return nil }
        scalars.removeFirst(length)
        return value
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
            case _ where scalar.value < 0x20:
                text += "\\x" + (scalar.value < 0x10 ? "0" : "") + String(scalar.value, radix: 16, uppercase: true)
            default:
                text.unicodeScalars.append(scalar)
            }
        }
        return text + "\""
    }
}
