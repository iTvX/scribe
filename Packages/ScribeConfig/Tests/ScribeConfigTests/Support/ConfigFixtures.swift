import Foundation
import Testing

/// Files under Tests/Fixtures/config and SharedSupport, found from this
/// source file's path.
enum ConfigFixtures {
    static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()  // Support
        .deletingLastPathComponent()  // ScribeConfigTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ScribeConfig
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root

    static let directory = repository.appending(path: "Tests/Fixtures/config", directoryHint: .isDirectory)
    static let squirrelYAML = repository.appending(path: "SharedSupport/squirrel.yaml")
    static let scribeYAML = repository.appending(path: "SharedSupport/scribe.yaml")
    static let rimeIceYAML = directory.appending(path: "rime-ice/squirrel.yaml")
    static let maxSampleCustomYAML = directory.appending(path: "max-sample/squirrel.custom.yaml")

    static func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Compares `actual` with snapshots/<name>.txt, or writes the file when
    /// SCRIBE_RECORD_SNAPSHOTS=1.
    static func expectSnapshot(
        _ actual: String,
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let url = directory.appending(path: "snapshots/\(name).txt")
        if ProcessInfo.processInfo.environment["SCRIBE_RECORD_SNAPSHOTS"] == "1" {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try actual.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let expected = try String(contentsOf: url, encoding: .utf8)
        #expect(actual == expected, "snapshot \(name) differs; rerun with SCRIBE_RECORD_SNAPSHOTS=1 to update it", sourceLocation: sourceLocation)
    }
}
