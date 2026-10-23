import Foundation

/// librime 1.17.0's conversions of a scalar (`ConfigValue::GetBool`, `GetInt`
/// and `GetDouble`), built on the same C library calls so edge cases match.
enum LibrimeScalar {
    /// "true" or "false" after ASCII lowercasing, like `boost::to_lower`.
    static func bool(_ value: String) -> Bool? {
        let lowered = value.utf8.map { byte in
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
        }
        if lowered.elementsEqual("true".utf8) {
            return true
        }
        if lowered.elementsEqual("false".utf8) {
            return false
        }
        return nil
    }

    /// A "0x" value that `strtoul` reads to the end becomes its low 32 bits as
    /// an `int`; anything else goes through `std::stoi`.
    static func int(_ value: String) -> Int? {
        guard !value.isEmpty else { return nil }
        return value.withCString { start -> Int? in
            if value.utf8.starts(with: "0x".utf8) {
                var end: UnsafeMutablePointer<CChar>?
                let hex = strtoul(start, &end, 16)
                if let end, end.pointee == 0 {
                    return Int(Int32(bitPattern: UInt32(truncatingIfNeeded: hex)))
                }
            }
            return stoi(start)
        }
    }

    /// `std::stod`: `strtod` on the longest prefix it accepts, failing when it
    /// converts nothing or reports ERANGE.
    static func double(_ value: String) -> Double? {
        guard !value.isEmpty else { return nil }
        return value.withCString { start -> Double? in
            var end: UnsafeMutablePointer<CChar>?
            let saved = errno
            errno = 0
            let result = strtod(start, &end)
            let failed = errno == ERANGE || end == UnsafeMutablePointer(mutating: start)
            errno = saved
            return failed ? nil : result
        }
    }

    /// `std::stoi`: `strtol` in base 10, failing when it converts nothing,
    /// reports ERANGE, or the result does not fit an `int`.
    private static func stoi(_ start: UnsafePointer<CChar>) -> Int? {
        var end: UnsafeMutablePointer<CChar>?
        let saved = errno
        errno = 0
        let result = strtol(start, &end, 10)
        let failed = errno == ERANGE || end == UnsafeMutablePointer(mutating: start)
        errno = saved
        guard !failed, let int = Int32(exactly: result) else { return nil }
        return Int(int)
    }
}
