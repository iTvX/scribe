import Foundation
import ReleaseKit
import Testing

/// Signs a package and its feed the way make-appcast.sh does, then checks
/// them as an installed copy would.
@Suite struct UpdateVerificationTests {
    let key = TestKey()
    let package = Data((0..<10_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    let url = "https://github.com/iTvX/scribe/releases/download/v0.2.0-beta.1/Scribe-0.2.0-beta.1.pkg"

    func signedFeed() throws -> Data {
        let release = item(
            build: "20261023120000", channel: "beta", url: url, shortVersion: "0.2.0-beta.1",
            length: package.count, signature: try key.sign(package)
        )
        let older = try makeFeed(item(build: "20260101000000"))
        return try key.signFeed(try makeFeed(release, existing: older))
    }

    func verify(
        feed: Data? = nil, package: Data? = nil, url: String? = nil, publicKey: String? = nil,
        build: String = "20261023120000", shortVersion: String = "0.2.0-beta.1", channel: String? = "beta"
    ) throws {
        try UpdateVerification.verify(
            feed: try feed ?? signedFeed(), package: package ?? self.package, url: url ?? self.url,
            publicKey: publicKey ?? key.publicKey, build: build, shortVersion: shortVersion, channel: channel
        )
    }

    @Test func aGoodReleaseVerifies() throws {
        try verify()
    }

    @Test func aChangedPackageFails() throws {
        var changed = package
        changed[100] ^= 1
        #expect(throws: UpdateVerification.Failure.packageSignature) { try verify(package: changed) }
        #expect(throws: UpdateVerification.Failure.length(expected: package.count + 1, found: package.count)) {
            try verify(package: package + [0])
        }
    }

    @Test func anotherKeyFails() throws {
        #expect(throws: UpdateVerification.Failure.feedSignature) { try verify(publicKey: TestKey().publicKey) }
    }

    @Test func aChangedFeedFails() throws {
        let feed = Data(try signedFeed().text.replacingOccurrences(of: "0.2.0-beta.1</sparkle:short", with: "0.2.1-beta.1</sparkle:short").utf8)
        #expect(throws: UpdateVerification.Failure.feedSignature) { try verify(feed: feed) }
    }

    @Test func aWrongURLFails() throws {
        #expect(throws: UpdateVerification.Failure.itemCount(url: "https://example.com/Scribe.pkg", found: 0)) {
            try verify(url: "https://example.com/Scribe.pkg")
        }
    }

    @Test func aWrongBuildFails() throws {
        #expect(throws: UpdateVerification.Failure.build(expected: "20261023120001", found: "20261023120000")) {
            try verify(build: "20261023120001")
        }
    }

    @Test func aWrongVersionOrChannelFails() throws {
        #expect(throws: UpdateVerification.Failure.shortVersion(expected: "0.2.0", found: "0.2.0-beta.1")) {
            try verify(shortVersion: "0.2.0")
        }
        #expect(throws: UpdateVerification.Failure.channel(expected: nil, found: "beta")) {
            try verify(channel: nil)
        }
    }
}
