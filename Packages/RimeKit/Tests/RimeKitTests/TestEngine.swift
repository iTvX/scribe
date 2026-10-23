import Foundation
import RimeKit

/// One deployed librime for the whole test process, using the minimal schema
/// in Tests/Fixtures/rime and a temporary user directory.
@MainActor
enum TestEngine {
    static let fixtures = URL(filePath: #filePath)
        .deletingLastPathComponent()  // RimeKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // RimeKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root
        .appending(path: "Tests/Fixtures/rime", directoryHint: .isDirectory)

    static let engine: LibrimeEngine = {
        let userDirectory = FileManager.default.temporaryDirectory
            .appending(path: "scribe-rimekit-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try! FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        let engine = LibrimeEngine.shared
        engine.start(RimeConfiguration(
            sharedDataDirectory: fixtures,
            userDataDirectory: userDirectory,
            minimumLogLevel: 2,
            appName: "rime.scribe-tests"
        ))
        precondition(engine.deploy(fullCheck: true), "deploying the test schema failed")
        return engine
    }()
}

/// Keysyms and masks used by the tests.
enum Key {
    static let space: Int32 = 0x20
    static let returnKey: Int32 = 0xff0d
    static let backSpace: Int32 = 0xff08
    static let escape: Int32 = 0xff1b
    static let pageDown: Int32 = 0xff56
    static let pageUp: Int32 = 0xff55

    static func character(_ character: Character) -> Int32 {
        Int32(character.unicodeScalars.first!.value)
    }
}

extension LibrimeEngine {
    func type(_ text: String, in session: RimeSessionID) {
        for character in text {
            _ = processKey(Key.character(character), modifiers: 0, in: session)
        }
    }
}
