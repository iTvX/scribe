import Foundation
import ScribeConfig
import Testing

struct SettingsLocationTests {
    static let home = URL(filePath: "/Users/test", directoryHint: .isDirectory)
    static let installed = URL(filePath: "/Applications/Scribe.app/Contents/SharedSupport", directoryHint: .isDirectory)
    static let user = URL(filePath: "/tmp/user", directoryHint: .isDirectory)
    static let shared = URL(filePath: "/tmp/shared", directoryHint: .isDirectory)

    @Test func usesTheInstalledScribeWithoutOverrides() {
        let location = SettingsLocation(home: Self.home, userOverride: nil, sharedOverride: nil) { Self.installed }
        #expect(location.userDirectory.path(percentEncoded: false) == "/Users/test/Library/Scribe/")
        #expect(location.sharedDirectory == Self.installed)
        #expect(location.isLive)
    }

    @Test func aSharedOverrideOnlyReplacesTheSharedDirectory() {
        var looked = false
        let location = SettingsLocation(home: Self.home, userOverride: nil, sharedOverride: Self.shared) {
            looked = true
            return Self.installed
        }
        #expect(location.userDirectory.path(percentEncoded: false) == "/Users/test/Library/Scribe/")
        #expect(location.sharedDirectory == Self.shared)
        // The real user directory is still the one a running Scribe has open.
        #expect(location.isLive)
        #expect(!looked)
    }

    @Test func aUserOverrideNeverLooksForTheInstalledScribe() {
        var looked = false
        let location = SettingsLocation(home: Self.home, userOverride: Self.user, sharedOverride: nil) {
            looked = true
            return Self.installed
        }
        #expect(location == SettingsLocation(home: Self.home, userOverride: Self.user, sharedOverride: nil) { nil })
        #expect(location.userDirectory == Self.user)
        #expect(location.sharedDirectory == nil)
        #expect(!location.isLive)
        #expect(!looked)

        let both = SettingsLocation(home: Self.home, userOverride: Self.user, sharedOverride: Self.shared) { Self.installed }
        #expect(both.sharedDirectory == Self.shared)
        #expect(!both.isLive)
    }
}
