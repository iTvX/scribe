import Foundation
import RimeKit
import ScribeCore
import ScribeTestSupport
import Testing

/// Every file in Tests/Fixtures/replays, played against the fake engine and
/// against librime with the scribe_test schema.
@MainActor
@Suite struct ReplayTests {
    nonisolated static let files = (try? TestFixtures.replayFiles()) ?? []

    @Test func replayFilesExist() {
        #expect(!Self.files.isEmpty)
    }

    @Test(arguments: files)
    func fakeEngine(file: URL) throws {
        try play(file, engineName: "fake", engine: FakeRimeEngine())
    }

    @Test(arguments: files)
    func librime(file: URL) throws {
        try play(file, engineName: "rime", engine: TestRime.engine)
    }

    private func play(_ file: URL, engineName: String, engine: some RimeEngine) throws {
        let script = try ReplayScript(String(contentsOf: file, encoding: .utf8))
        guard script.engines?.contains(engineName) ?? true else { return }
        let session = InputSession(engine: engine)
        defer { session.close() }
        for failure in ReplayRunner.run(script, in: session) {
            Issue.record("\(file.lastPathComponent) \(failure)")
        }
    }
}
