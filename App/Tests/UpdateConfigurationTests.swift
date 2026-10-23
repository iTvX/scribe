import Foundation
import Testing

@Suite final class UpdateConfigurationTests {
    let suite = "scribe-update-test-\(UUID().uuidString)"
    let defaults: UserDefaults
    let feed = "https://github.com/iTvX/scribe/releases/download/appcast/appcast.xml"
    let key = Data(repeating: 7, count: 32).base64EncodedString()
    let installed = URL(filePath: "/Library/Input Methods/Scribe.app", directoryHint: .isDirectory)

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    deinit {
        defaults.removePersistentDomain(forName: suite)
    }

    func configuration(feed: String?? = .none, key: String?? = .none, at bundle: URL? = nil) -> UpdateConfiguration? {
        var info: [String: Any] = ["CFBundleIdentifier": "io.github.itvx.inputmethod.Scribe"]
        info["SUFeedURL"] = feed ?? self.feed
        info["SUPublicEDKey"] = key ?? self.key
        return UpdateConfiguration(infoDictionary: info, bundleURL: bundle ?? installed, defaults: defaults)
    }

    @Test func enabledForTheInstalledReleaseBuild() throws {
        let configuration = try #require(configuration())
        #expect(configuration.feedURL == URL(string: feed))
        #expect(configuration.publicKey == key)
        #expect(UpdateConfiguration(
            infoDictionary: ["SUFeedURL": feed, "SUPublicEDKey": key],
            bundleURL: URL(filePath: "/Library/Input Methods/./Scribe.app"),
            defaults: defaults
        ) != nil)
    }

    @Test func offWithoutAFeed() {
        #expect(configuration(feed: .some(nil)) == nil)
        #expect(configuration(feed: "") == nil)
    }

    @Test func offWithoutAKey() {
        #expect(configuration(key: .some(nil)) == nil)
        #expect(configuration(key: "not base64!") == nil)
    }

    @Test func offWithAnInsecureFeed() {
        #expect(configuration(feed: "http://github.com/iTvX/scribe/releases/download/appcast/appcast.xml") == nil)
        #expect(configuration(feed: "file:///tmp/appcast.xml") == nil)
    }

    @Test func offWithAKeyOfTheWrongLength() {
        #expect(configuration(key: Data(repeating: 7, count: 31).base64EncodedString()) == nil)
        #expect(configuration(key: Data(repeating: 7, count: 64).base64EncodedString()) == nil)
    }

    @Test func offForTheUsersOwnCopy() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(configuration(at: home.appending(path: "Library/Input Methods/Scribe.app")) == nil)
    }

    @Test func offForALocalBuild() {
        #expect(configuration(at: URL(filePath: "/Users/someone/scribe/build/DerivedData/Build/Products/Release/Scribe.app")) == nil)
        // Not directly in /Library/Input Methods.
        #expect(configuration(at: URL(filePath: "/Library/Input Methods/Old/Scribe.app")) == nil)
    }

    @Test func betaUpdatesAreOptIn() throws {
        let off = try #require(configuration())
        #expect(!off.receivesBetaUpdates)
        #expect(off.allowedChannels.isEmpty)

        defaults.set(true, forKey: UpdateConfiguration.betaUpdatesKey)
        let on = try #require(configuration())
        #expect(on.receivesBetaUpdates)
        #expect(on.allowedChannels == ["beta"])
    }
}
