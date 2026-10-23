import Foundation
import RimeKit

/// Shared test data in the repository's Tests/Fixtures.
public enum TestFixtures {
    public static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()  // ScribeTestSupport
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // ScribeCore
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root
        .appending(path: "Tests/Fixtures", directoryHint: .isDirectory)

    /// Shared data with the minimal scribe_test schema.
    public static let rime = root.appending(path: "rime", directoryHint: .isDirectory)

    public static let replays = root.appending(path: "replays", directoryHint: .isDirectory)

    public static func replayFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: replays, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "replay" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// The process's librime, deployed once with the scribe_test schema and a
/// temporary user directory.
@MainActor
public enum TestRime {
    public static let engine: LibrimeEngine = {
        let userDirectory = FileManager.default.temporaryDirectory
            .appending(path: "scribe-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try! FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        let engine = LibrimeEngine.shared
        engine.start(RimeConfiguration(
            sharedDataDirectory: TestFixtures.rime,
            userDataDirectory: userDirectory,
            minimumLogLevel: 2,
            appName: "rime.scribe-tests"
        ))
        precondition(engine.deploy(fullCheck: true), "deploying the test schema failed")
        return engine
    }()
}
