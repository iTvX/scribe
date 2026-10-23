import Foundation
import ReleaseKit
import Testing

@Suite struct AppcastTests {
    @Test func newFeed() throws {
        let feed = try makeFeed(item(build: "20261023120000", length: 4321, signature: "U0lH", notes: "- **First** release"))
        let text = feed.text
        #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"))
        #expect(text.contains("<rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\" version=\"2.0\">"))
        #expect(text.contains("<title>中书 Scribe</title>"))
        #expect(text.contains("<link>https://github.com/iTvX/scribe</link>"))
        #expect(text.contains("<description>中书 Scribe 的更新</description>"))
        #expect(text.contains("<language>zh</language>"))
        #expect(text.contains("<pubDate>Fri, 23 Oct 2026 12:00:00 +0000</pubDate>"))
        #expect(text.contains("<sparkle:version>20261023120000</sparkle:version>"))
        #expect(text.contains("<sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>"))
        #expect(text.contains("<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>"))
        #expect(text.contains("<description sparkle:format=\"markdown\"><![CDATA[- **First** release]]></description>"))
        #expect(text.contains("""
            <enclosure url="https://github.com/iTvX/scribe/releases/download/v0.1.0/Scribe-0.1.0.pkg" length="4321" \
            type="application/octet-stream" sparkle:edSignature="U0lH" sparkle:installationType="package"/>
            """))
        #expect(!text.contains("sparkle:channel"))

        let items = try Appcast.items(in: feed)
        #expect(items == [item(build: "20261023120000", length: 4321, signature: "U0lH", notes: "- **First** release")])
    }

    @Test func betaChannel() throws {
        let beta = item(build: "20261023120000", channel: "beta", shortVersion: "0.2.0-beta.1")
        let feed = try makeFeed(beta)
        #expect(feed.text.contains("<sparkle:channel>beta</sparkle:channel>"))
        #expect(try Appcast.items(in: feed) == [beta])
    }

    @Test func notesThatEndCDATAAreEscaped() throws {
        let odd = item(build: "20261023120000", notes: "a ]]> b & <c>")
        let feed = try makeFeed(odd)
        #expect(!feed.text.contains("CDATA"))
        #expect(try Appcast.items(in: feed).first?.notes == "a ]]> b & <c>")
    }

    /// A published feed, signed by sign_update: a warning comment at the top
    /// and the signature block at the end.
    func publishedFeed(key: TestKey) throws -> Data {
        var feed = try makeFeed(item(build: "20251201000000", channel: "beta", shortVersion: "0.1.0-beta.1"))
        feed = try makeFeed(item(build: "20260101000000", shortVersion: "0.1.0"), existing: feed)
        var text = feed.text
        let declarationEnd = try #require(text.range(of: "?>"))
        text.insert(contentsOf: "<!-- sparkle-sign-warning:\nIMPORTANT: re-sign after changing this file\n-->", at: declarationEnd.upperBound)
        text = text.replacingOccurrences(of: "<language>zh</language>", with: "<language>zh</language><!-- a note -->")
        return try key.signFeed(Data(text.utf8))
    }

    @Test func mergesIntoAPublishedFeed() throws {
        let published = try publishedFeed(key: TestKey())
        #expect(try Appcast.items(in: published).map(\.build) == ["20260101000000", "20251201000000"])

        let new = item(build: "20261023120000", shortVersion: "0.2.0")
        let feed = try makeFeed(new, existing: published)
        let items = try Appcast.items(in: feed)
        #expect(items.map(\.build) == ["20261023120000", "20260101000000", "20251201000000"])
        #expect(items.first == new)
        #expect(items.last?.channel == "beta")
        #expect(!feed.text.contains("<!--"))
        #expect(!feed.text.contains("sparkle-signatures"))
        #expect(SignedFeed.split(feed).signature == nil)
        // The channel's own elements are kept, once.
        #expect(feed.text.components(separatedBy: "<title>中书 Scribe</title>").count == 2)
        #expect(feed.text.contains("<language>zh</language>"))
    }

    @Test func replacesTheItemWithTheSameURL() throws {
        let published = try publishedFeed(key: TestKey())
        // A re-run of the 0.1.0 release with a new build.
        let rebuilt = item(build: "20260102000000", shortVersion: "0.1.0", length: 99)
        let items = try Appcast.items(in: try makeFeed(rebuilt, existing: published))
        #expect(items.map(\.build) == ["20260102000000", "20251201000000"])
        #expect(items.first?.length == 99)
    }

    @Test func replacesTheItemWithTheSameBuildAndChannel() throws {
        let published = try publishedFeed(key: TestKey())
        let same = item(build: "20260101000000", url: "https://example.com/Scribe-0.1.0.pkg", shortVersion: "0.1.0")
        let items = try Appcast.items(in: try makeFeed(same, existing: published))
        #expect(items.map(\.url) == ["https://example.com/Scribe-0.1.0.pkg", item(build: "1", shortVersion: "0.1.0-beta.1").url])
    }

    @Test func refusesABuildThatIsNotNewer() throws {
        let published = try publishedFeed(key: TestKey())
        #expect(throws: Appcast.Error.notNewer(existing: "20260101000000", new: "20251231000000")) {
            try makeFeed(item(build: "20251231000000", shortVersion: "0.0.9"), existing: published)
        }
        // The same build in another channel is not newer either.
        #expect(throws: Appcast.Error.notNewer(existing: "20260101000000", new: "20260101000000")) {
            try makeFeed(item(build: "20260101000000", channel: "beta", shortVersion: "0.1.1-beta.1"), existing: published)
        }
    }

    @Test func comparesBuildsAsNumbers() throws {
        let existing = try makeFeed(item(build: "999", shortVersion: "0.0.1"))
        #expect(try Appcast.items(in: try makeFeed(item(build: "1000", shortVersion: "0.0.2"), existing: existing)).count == 2)
    }

    @Test func refusesBuildsThatAreNotAllDigits() throws {
        #expect(throws: Appcast.Error.buildNotNumeric("1.0")) {
            try makeFeed(item(build: "1.0"))
        }
        #expect(throws: Appcast.Error.buildNotNumeric("")) {
            try makeFeed(item(build: ""))
        }
        let existing = Data(try makeFeed(item(build: "20260101000000")).text
            .replacingOccurrences(of: "<sparkle:version>20260101000000<", with: "<sparkle:version>2026.1<").utf8)
        #expect(throws: Appcast.Error.existingBuildNotNumeric("2026.1")) {
            try makeFeed(item(build: "20261023120000", shortVersion: "0.2.0"), existing: existing)
        }
    }

    @Test func refusesSomethingElse() {
        #expect(throws: Appcast.Error.self) {
            try makeFeed(item(build: "1"), existing: Data("<html><body/></html>".utf8))
        }
        #expect(throws: Appcast.Error.self) {
            try makeFeed(item(build: "1"), existing: Data("not xml".utf8))
        }
    }
}
