import CryptoKit
import Foundation

/// Sparkle's Ed25519 keys and signatures, all base64. A private key is the
/// 32-byte seed, the format sign_update's `--ed-key-file` reads; the public
/// key is what goes in SUPublicEDKey.
public enum EdDSA {
    public enum KeyError: Error, Equatable, CustomStringConvertible {
        case notBase64
        case wrongLength(Int)

        public var description: String {
            switch self {
            case .notBase64: "the private key is not base64"
            case .wrongLength(let count): "the private key is \(count) bytes; expected a 32-byte seed"
            }
        }
    }

    public static func newPrivateKey() -> String {
        Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
    }

    /// Surrounding whitespace, such as the newline at the end of a key file,
    /// is ignored.
    public static func publicKey(forPrivateKey privateKey: String) throws -> String {
        guard let seed = Data(base64Encoded: privateKey.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw KeyError.notBase64
        }
        guard seed.count == 32 else {
            throw KeyError.wrongLength(seed.count)
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey.rawRepresentation.base64EncodedString()
    }

    public static func isValid(signature: String, of data: Data, publicKey: String) -> Bool {
        guard let signature = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)),
              let keyData = Data(base64Encoded: publicKey.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return false }
        return key.isValidSignature(signature, for: data)
    }
}
