/// Rules for the IDs of themes under `themes` in scribe.yaml.
public enum ThemeID {
    /// An ID the Settings app may create: lowercase ASCII letters, digits
    /// and "_", and not "native".
    public static func isValidForSettings(_ id: String) -> Bool {
        id != "native" && !id.isEmpty && id.utf8.allSatisfy { byte in
            (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || byte == UInt8(ascii: "_")
        }
    }

    /// An ID Scribe can serve as a Squirrel preset: not empty, without "/"
    /// (a path separator) or ":" (which marks the dark preset), and not
    /// starting with "@" (a list reference in a path).
    static func isServable(_ id: String) -> Bool {
        !id.isEmpty && !id.contains("/") && !id.contains(":") && !id.hasPrefix("@")
    }
}
