import Foundation

/// Whether and how this copy of Scribe updates itself. Only release builds
/// carry SUFeedURL and SUPublicEDKey (build-release.sh adds them), and only
/// the copy the package installed, in /Library/Input Methods, may replace
/// itself with the next package. Local builds never check for updates.
struct UpdateConfiguration: Equatable, Sendable {
    static let installDirectory = "/Library/Input Methods"
    /// `defaults write io.github.itvx.inputmethod.Scribe BetaUpdates -bool YES`
    static let betaUpdatesKey = "BetaUpdates"

    var feedURL: URL
    var publicKey: String
    var receivesBetaUpdates: Bool

    init?(infoDictionary: [String: Any], bundleURL: URL, defaults: UserDefaults) {
        guard let feed = infoDictionary["SUFeedURL"] as? String,
              let feedURL = URL(string: feed), feedURL.scheme == "https", feedURL.host() != nil,
              let publicKey = infoDictionary["SUPublicEDKey"] as? String,
              Data(base64Encoded: publicKey)?.count == 32
        else { return nil }
        let directory = bundleURL.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent()
        guard Self.trimmingSlash(directory.path(percentEncoded: false)) == Self.installDirectory else { return nil }
        self.feedURL = feedURL
        self.publicKey = publicKey
        receivesBetaUpdates = defaults.bool(forKey: Self.betaUpdatesKey)
    }

    /// Sparkle channels accepted besides the default one: ["beta"] when opted in.
    var allowedChannels: Set<String> {
        receivesBetaUpdates ? ["beta"] : []
    }

    private static func trimmingSlash(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
