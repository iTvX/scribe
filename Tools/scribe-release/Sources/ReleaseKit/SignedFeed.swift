import Foundation

/// A feed signed by sign_update: the feed, then a block
///
///     <!-- sparkle-signatures:
///     edSignature: <base64>
///     length: <bytes signed>
///     -->
///
/// The signature covers everything before the block.
public enum SignedFeed {
    private static let prefix = Data("<!-- sparkle-signatures:\n".utf8)
    private static let suffix = Data("-->".utf8)

    /// Splits a feed as Sparkle's SPUExtractAppcastContent does: at the last
    /// signature block prefix, which ends at the first "-->" after it. A feed
    /// without a complete block is all content.
    public static func split(_ data: Data) -> (content: Data, signature: String?, length: Int?) {
        guard let start = data.range(of: prefix, options: .backwards),
              let end = data.range(of: suffix, in: start.upperBound..<data.endIndex),
              let block = String(data: data[start.upperBound..<end.lowerBound], encoding: .utf8)
        else { return (data, nil, nil) }

        var signature: String?
        var length: Int?
        for line in block.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.hasPrefix("edSignature:") {
                signature = line.dropFirst("edSignature:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.hasPrefix("length:") {
                length = Int(line.dropFirst("length:".count).trimmingCharacters(in: .whitespacesAndNewlines).prefix(while: \.isASCIIDigit))
            }
        }
        return (Data(data[data.startIndex..<start.lowerBound]), signature, length)
    }

    /// The feed carries a signature by `publicKey` over exactly the bytes its
    /// block says were signed.
    public static func isValid(_ data: Data, publicKey: String) -> Bool {
        let (content, signature, length) = split(data)
        guard let signature, length == content.count else { return false }
        return EdDSA.isValid(signature: signature, of: content, publicKey: publicKey)
    }
}

extension Character {
    var isASCIIDigit: Bool {
        ("0"..."9").contains(self)
    }
}
