import Foundation

/// plum's `rime-install`, which ships next to Scribe as in Squirrel, and the
/// Terminal command that installs a recipe into Scribe's user directory with
/// it.
public struct PlumCommand: Equatable, Sendable {
    /// `Scribe.app/Contents/MacOS/rime-install`.
    public var tool: URL
    public var userDirectory: URL

    public init(tool: URL, userDirectory: URL) {
        self.tool = tool
        self.userDirectory = userDirectory
    }

    /// The tool of the Scribe.app whose shared data is `sharedDirectory`
    /// (`Scribe.app/Contents/SharedSupport`), or nil when it has none.
    public init?(sharedDirectory: URL, userDirectory: URL) {
        let tool = sharedDirectory.standardizedFileURL.deletingLastPathComponent()
            .appending(path: "MacOS/rime-install", directoryHint: .notDirectory)
        guard FileManager.default.isReadableFile(atPath: tool.path(percentEncoded: false)) else { return nil }
        self.init(tool: tool, userDirectory: userDirectory)
    }

    /// For zsh and bash. Without a recipe, "<配方>" stands where it goes.
    public func command(recipe: String) -> String {
        let recipe = recipe.trimmingCharacters(in: .whitespacesAndNewlines)
        return "rime_dir=\(Self.quoted(Self.path(userDirectory))) bash \(Self.quoted(Self.path(tool))) "
            + (recipe.isEmpty ? "<配方>" : Self.word(recipe))
    }

    private static func path(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Single quotes, with any single quote closed, escaped and reopened.
    private static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// A recipe as is when it only has characters recipes use, such as
    /// "iDvel/rime-ice:others/recipes/full" or "lotem/rime-octagram-data@hant".
    private static func word(_ text: String) -> String {
        let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:@+=,")
        return text.unicodeScalars.allSatisfy(plain.contains) ? text : quoted(text)
    }
}
