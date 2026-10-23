import Foundation
import RimeKit

/// `Scribe --self-test`: starts librime from this app bundle with a
/// temporary user directory and checks that the plugins loaded.
@MainActor
enum SelfTest {
    static let plugins = ["lua", "octagram", "predict"]

    static func run() -> Bool {
        let userDirectory = FileManager.default.temporaryDirectory
            .appending(path: "scribe-self-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: userDirectory) }

        let engine = LibrimeEngine.shared
        engine.start(RimeService.configuration(userDirectory: userDirectory, logDirectory: nil))
        defer { engine.stop() }

        print("librime \(Librime.version ?? "unknown")")
        print("shared data: \(RimeService.sharedDataDirectory().path(percentEncoded: false))")
        var passed = true
        for plugin in plugins {
            let loaded = Librime.hasModule(plugin)
            print("plugin \(plugin): \(loaded ? "loaded" : "MISSING")")
            passed = passed && loaded
        }
        return passed
    }
}
