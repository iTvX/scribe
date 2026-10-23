import CryptoKit
import Foundation
import ReleaseKit
import Testing

@Test func newKeyRoundTrip() throws {
    let privateKey = EdDSA.newPrivateKey()
    let seed = try #require(Data(base64Encoded: privateKey))
    #expect(seed.count == 32)

    // A key file usually ends in a newline.
    let publicKey = try EdDSA.publicKey(forPrivateKey: privateKey + "\n")
    #expect(Data(base64Encoded: publicKey)?.count == 32)

    let data = Data("中书 update".utf8)
    let signature = try Curve25519.Signing.PrivateKey(rawRepresentation: seed).signature(for: data)
    #expect(EdDSA.isValid(signature: signature.base64EncodedString(), of: data, publicKey: publicKey))
    #expect(!EdDSA.isValid(signature: signature.base64EncodedString(), of: Data("other".utf8), publicKey: publicKey))
    #expect(!EdDSA.isValid(signature: signature.base64EncodedString(), of: data, publicKey: try EdDSA.publicKey(forPrivateKey: EdDSA.newPrivateKey())))
}

/// The pair sign_update and Sparkle would derive from the same seed: the
/// RFC 8032 test vector 1.
@Test func publicKeyMatchesTheStandardDerivation() throws {
    let seed = Data([
        0x9d, 0x61, 0xb1, 0x9d, 0xef, 0xfd, 0x5a, 0x60, 0xba, 0x84, 0x4a, 0xf4, 0x92, 0xec, 0x2c, 0xc4,
        0x44, 0x49, 0xc5, 0x69, 0x7b, 0x32, 0x69, 0x19, 0x70, 0x3b, 0xac, 0x03, 0x1c, 0xae, 0x7f, 0x60,
    ])
    let publicKey = Data([
        0xd7, 0x5a, 0x98, 0x01, 0x82, 0xb1, 0x0a, 0xb7, 0xd5, 0x4b, 0xfe, 0xd3, 0xc9, 0x64, 0x07, 0x3a,
        0x0e, 0xe1, 0x72, 0xf3, 0xda, 0xa6, 0x23, 0x25, 0xaf, 0x02, 0x1a, 0x68, 0xf7, 0x07, 0x51, 0x1a,
    ])
    #expect(try EdDSA.publicKey(forPrivateKey: seed.base64EncodedString()) == publicKey.base64EncodedString())
}

@Test func onlySeedsAreAccepted() {
    // sign_update's older format: the expanded private key and the public key.
    #expect(throws: EdDSA.KeyError.wrongLength(64)) {
        try EdDSA.publicKey(forPrivateKey: Data(repeating: 1, count: 64).base64EncodedString())
    }
    #expect(throws: EdDSA.KeyError.wrongLength(31)) {
        try EdDSA.publicKey(forPrivateKey: Data(repeating: 1, count: 31).base64EncodedString())
    }
    #expect(throws: EdDSA.KeyError.notBase64) {
        try EdDSA.publicKey(forPrivateKey: "not a key!")
    }
}

@Test func malformedSignaturesAndKeysAreInvalid() {
    let data = Data("x".utf8)
    #expect(!EdDSA.isValid(signature: "", of: data, publicKey: Data(repeating: 1, count: 32).base64EncodedString()))
    #expect(!EdDSA.isValid(signature: Data(repeating: 0, count: 64).base64EncodedString(), of: data, publicKey: "short"))
}
