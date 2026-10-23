import Foundation
import ReleaseKit
import Testing

@Suite struct SignedFeedTests {
    let key = TestKey()
    let content = Data("<?xml version=\"1.0\"?>\n<rss version=\"2.0\"><channel><title>中书</title></channel></rss>".utf8)

    @Test func splitsASignedFeed() throws {
        let feed = try key.signFeed(content)
        let (split, signature, length) = SignedFeed.split(feed)
        #expect(split == content)
        // CryptoKit's signatures are randomized, so check this one verifies.
        #expect(EdDSA.isValid(signature: try #require(signature), of: content, publicKey: key.publicKey))
        #expect(length == content.count)
        #expect(SignedFeed.isValid(feed, publicKey: key.publicKey))
    }

    @Test func anUnsignedFeedIsAllContent() {
        let (split, signature, length) = SignedFeed.split(content)
        #expect(split == content)
        #expect(signature == nil)
        #expect(length == nil)
        #expect(!SignedFeed.isValid(content, publicKey: key.publicKey))
    }

    @Test func anUnfinishedBlockIsContent() {
        var feed = content
        feed.append(Data("<!-- sparkle-signatures:\nedSignature: abc\n".utf8))
        let (split, signature, _) = SignedFeed.split(feed)
        #expect(split == feed)
        #expect(signature == nil)
    }

    /// As in Sparkle, only the last block counts, so text that merely looks
    /// like a block inside the feed stays content.
    @Test func theLastBlockCounts() throws {
        var inner = content
        inner.append(Data("<!-- sparkle-signatures:\nedSignature: old\nlength: 1\n-->\n".utf8))
        let feed = try key.signFeed(inner)
        #expect(SignedFeed.split(feed).content == inner)
        #expect(SignedFeed.isValid(feed, publicKey: key.publicKey))
    }

    @Test func aTamperedByteFails() throws {
        var feed = try key.signFeed(content)
        let index = try #require(feed.firstIndex(of: UInt8(ascii: "2")))
        feed[index] = UInt8(ascii: "3")
        #expect(!SignedFeed.isValid(feed, publicKey: key.publicKey))
    }

    @Test func aWrongLengthFails() throws {
        let signature = try key.sign(content)
        var feed = content
        feed.append(Data("<!-- sparkle-signatures:\nedSignature: \(signature)\nlength: \(content.count - 1)\n-->\n".utf8))
        #expect(SignedFeed.split(feed).signature == signature)
        #expect(!SignedFeed.isValid(feed, publicKey: key.publicKey))
    }

    @Test func anotherKeyFails() throws {
        #expect(!SignedFeed.isValid(try key.signFeed(content), publicKey: TestKey().publicKey))
    }
}
