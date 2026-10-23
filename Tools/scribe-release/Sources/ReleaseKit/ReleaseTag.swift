import Foundation

/// A tag that publishes a release: `v<major>.<minor>.<patch>`, or a
/// prerelease `v<major>.<minor>.<patch>-(alpha|beta|rc).<n>`. Numbers have no
/// leading zeros.
public struct ReleaseTag: Equatable, Sendable {
    /// The tag without the leading "v", as in CFBundleShortVersionString.
    public let version: String
    public let isPrerelease: Bool

    /// The Sparkle channel the release goes to: "beta" for any prerelease,
    /// nil (the default channel) otherwise.
    public var channel: String? {
        isPrerelease ? "beta" : nil
    }

    public init?(_ tag: String) {
        let number = "(?:0|[1-9][0-9]*)"
        // \z rather than $, which would also match before a final newline.
        let pattern = "\\Av(\(number)\\.\(number)\\.\(number)(-(?:alpha|beta|rc)\\.\(number))?)\\z"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let version = Range(match.range(at: 1), in: tag)
        else { return nil }
        self.version = String(tag[version])
        isPrerelease = match.range(at: 2).location != NSNotFound
    }
}
