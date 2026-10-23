import Foundation
import RimeKit
import ScribeConfig
import ScribeCore

/// `Scribe --replay FILE`: plays a replay file through an input session,
/// with this app's librime and plugins and a temporary copy of the user's
/// configuration. The copy leaves out the user dictionaries, which the
/// running input method keeps open.
@MainActor
enum ReplayCommand {
    static func run(file: String) -> Bool {
        let script: ReplayScript
        do {
            script = try ReplayScript(String(contentsOfFile: file, encoding: .utf8))
        } catch {
            print("\(file): \(error)")
            return false
        }

        let fileManager = FileManager.default
        let userDirectory = UserDirectories(home: fileManager.homeDirectoryForCurrentUser).scribe
        let copy = fileManager.temporaryDirectory.appending(path: "scribe-replay-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: copy) }
        do {
            try fileManager.copyItem(at: userDirectory, to: copy)
            for item in try fileManager.contentsOfDirectory(atPath: copy.path(percentEncoded: false)) where item.hasSuffix(".userdb") {
                try fileManager.removeItem(at: copy.appending(path: item))
            }
        } catch {
            print("Cannot copy \(userDirectory.path(percentEncoded: false)): \(error)")
            return false
        }

        let engine = LibrimeEngine.shared
        engine.start(RimeService.configuration(userDirectory: copy, logDirectory: nil))
        defer { engine.stop() }
        if engine.startMaintenance(fullCheck: false) {
            engine.joinMaintenance()
        }
        if let probe = engine.createSession() {
            print("schema: \(engine.status(in: probe)?.schemaID ?? "none")")
            engine.destroySession(probe)
        }

        let session = InputSession(engine: engine)
        defer { session.close() }
        let failures = ReplayRunner.run(script, in: session)
        for failure in failures {
            print(failure)
        }
        print(failures.isEmpty ? "passed \(script.steps.count) keys" : "\(failures.count) failures")
        return failures.isEmpty
    }
}
