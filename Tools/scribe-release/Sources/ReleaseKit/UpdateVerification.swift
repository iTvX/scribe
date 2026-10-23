import Foundation

/// Checks a signed feed and its package the way an installed copy of Scribe
/// will, independently of Sparkle's own tools.
public enum UpdateVerification {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case feedSignature
        case itemCount(url: String, found: Int)
        case build(expected: String, found: String)
        case shortVersion(expected: String, found: String)
        case channel(expected: String?, found: String?)
        case installationType(String)
        case length(expected: Int, found: Int)
        case packageSignature

        public var description: String {
            switch self {
            case .feedSignature:
                "the feed is not signed by this public key, or its signature does not cover the whole feed"
            case .itemCount(let url, let found):
                "expected exactly one item for \(url), found \(found)"
            case .build(let expected, let found):
                "the item's sparkle:version is \(found), expected \(expected)"
            case .shortVersion(let expected, let found):
                "the item's sparkle:shortVersionString is \(found), expected \(expected)"
            case .channel(let expected, let found):
                "the item's sparkle:channel is \(found ?? "absent"), expected \(expected ?? "absent")"
            case .installationType(let found):
                "the item's sparkle:installationType is \(found), expected package"
            case .length(let expected, let found):
                "the item's length is \(found), but the package has \(expected) bytes"
            case .packageSignature:
                "the item's sparkle:edSignature does not verify the package with this public key"
            }
        }
    }

    public static func verify(
        feed: Data, package: Data, url: String, publicKey: String, build: String, shortVersion: String, channel: String?
    ) throws {
        guard SignedFeed.isValid(feed, publicKey: publicKey) else { throw Failure.feedSignature }
        let items = try Appcast.items(in: feed).filter { $0.url == url }
        guard items.count == 1, let item = items.first else {
            throw Failure.itemCount(url: url, found: items.count)
        }
        guard item.build == build else { throw Failure.build(expected: build, found: item.build) }
        guard item.shortVersion == shortVersion else {
            throw Failure.shortVersion(expected: shortVersion, found: item.shortVersion)
        }
        guard item.channel == channel else { throw Failure.channel(expected: channel, found: item.channel) }
        guard item.installationType == "package" else { throw Failure.installationType(item.installationType) }
        guard item.length == package.count else { throw Failure.length(expected: package.count, found: item.length) }
        guard EdDSA.isValid(signature: item.edSignature, of: package, publicKey: publicKey) else {
            throw Failure.packageSignature
        }
    }
}
