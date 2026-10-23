import Foundation

/// Release notes kept in CHANGELOG.md, one `## <version>` section per release.
public enum ReleaseNotes {
    /// The text under the line `## <version>`, up to the next line starting
    /// with `## `, trimmed. Nil when there is no such heading or nothing
    /// under it.
    public static func section(for version: String, in changelog: String) -> String? {
        // "\r\n" is a single Character, so split on any newline.
        var lines = changelog.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)[...]
        guard let heading = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## \(version)" }) else {
            return nil
        }
        lines = lines[(heading + 1)...]
        if let next = lines.firstIndex(where: { $0.hasPrefix("## ") }) {
            lines = lines[..<next]
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }
}
