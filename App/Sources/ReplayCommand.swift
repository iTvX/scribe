import Foundation
import RimeKit
import ScribeConfig
import ScribeCore

/// `Scribe --replay FILE [USER_DIR]`: plays a replay file through an input
/// session, with this app's librime and plugins and a temporary copy of the
/// user's configuration. The copy leaves out the user dictionaries, which the
/// running input method keeps open. With USER_DIR, such as a test setup in a
/// temporary directory, that directory is used and deployed in place.
@MainActor
enum ReplayCommand {
    static func run(file: String, userDirectory: String? = nil) -> Bool {
        let script: ReplayScript
        do {
            script = try ReplayScript(String(contentsOfFile: file, encoding: .utf8))
        } catch {
            print("\(file): \(error)")
            return false
        }

        let fileManager = FileManager.default
        let liveDirectory = UserDirectories(home: fileManager.homeDirectoryForCurrentUser).scribe
        let directory: URL
        if let userDirectory {
            directory = URL(filePath: userDirectory, directoryHint: .isDirectory).standardizedFileURL
            guard directory.resolvingSymlinksInPath() != liveDirectory.resolvingSymlinksInPath() else {
                print("\(userDirectory) is the input method's own directory; leave out USER_DIR to play against a copy")
                return false
            }
        } else {
            directory = fileManager.temporaryDirectory.appending(path: "scribe-replay-\(UUID().uuidString)", directoryHint: .isDirectory)
            do {
                try fileManager.copyItem(at: liveDirectory, to: directory)
                for item in try fileManager.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) where item.hasSuffix(".userdb") {
                    try fileManager.removeItem(at: directory.appending(path: item))
                }
            } catch {
                print("Cannot copy \(liveDirectory.path(percentEncoded: false)): \(error)")
                return false
            }
        }
        defer {
            if userDirectory == nil {
                try? fileManager.removeItem(at: directory)
            }
        }

        // As the input method runs, so the replay covers OpenCC too.
        RimeService.useSharedDataAsWorkingDirectory()
        let engine = LibrimeEngine.shared
        engine.start(RimeService.configuration(userDirectory: directory, logDirectory: nil))
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
