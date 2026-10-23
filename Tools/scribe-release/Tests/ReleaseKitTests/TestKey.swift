import CryptoKit
import Foundation
import ReleaseKit

/// A throwaway signing key, used the way sign_update uses the real one.
struct TestKey {
    let key = Curve25519.Signing.PrivateKey()

    var publicKey: String {
        key.publicKey.rawRepresentation.base64EncodedString()
    }

    func sign(_ data: Data) throws -> String {
        try key.signature(for: data).base64EncodedString()
    }

    /// As Sparkle's signAppcast: the content, then the signing block.
    func signFeed(_ content: Data) throws -> Data {
        var feed = content
        feed.append(Data("<!-- sparkle-signatures:\nedSignature: \(try sign(content))\nlength: \(content.count)\n-->\n".utf8))
        return feed
    }
}

func item(
    build: String, channel: String? = nil, url: String? = nil, shortVersion: String = "0.1.0",
    length: Int = 1234, signature: String = "c2lnbmF0dXJl", notes: String = "- Notes"
) -> AppcastItem {
    AppcastItem(
        title: "中书 \(shortVersion)",
        shortVersion: shortVersion,
        build: build,
        channel: channel,
        minimumSystemVersion: "14.0",
        publicationDate: Date(timeIntervalSince1970: 1_792_756_800),  // 2026-10-23 12:00:00 UTC
        notes: notes,
        url: url ?? "https://github.com/iTvX/scribe/releases/download/v\(shortVersion)/Scribe-\(shortVersion).pkg",
        length: length,
        edSignature: signature
    )
}

func makeFeed(_ item: AppcastItem, existing: Data? = nil) throws -> Data {
    try Appcast.make(item: item, existing: existing, feedTitle: "中书 Scribe", feedLink: "https://github.com/iTvX/scribe")
}

extension Data {
    var text: String {
        String(decoding: self, as: UTF8.self)
    }
}
