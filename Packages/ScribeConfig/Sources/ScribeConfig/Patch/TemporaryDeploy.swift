import Foundation
import RimeKit

/// Deploys configs from a temporary copy of a user directory, so their
/// effective values can be read without touching the real directory or
/// waiting for Scribe to deploy it.
@MainActor
struct TemporaryDeploy {
    let engine: LibrimeEngine
    let userDirectory: URL
    let sharedDirectory: URL

    func run<T>(_ configID: String, replacing: [String: String] = [:],
                _ body: (LibrimeEngine) throws(PatchSaveError) -> T) throws(PatchSaveError) -> T {
        try run([configID], replacing: replacing, body)
    }

    /// Copies the top-level `*.yaml` files of the user directory (but not
    /// user.yaml, installation.yaml or dictionaries, which can be large and a
    /// config never includes) with `replacing` written over them, plus
    /// build/<schemaID>.schema.yaml when there is one; deploys
    /// `<configID>.yaml` for each ID, runs `body` and stops the engine again.
    func run<T>(_ configIDs: [String], replacing: [String: String] = [:], schemaID: String? = nil,
                _ body: (LibrimeEngine) throws(PatchSaveError) -> T) throws(PatchSaveError) -> T {
        guard !engine.isRunning else { throw .engineBusy }
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory
            .appending(path: "scribe-deploy-check-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: temporary) }
        do {
            try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
            let names = try fileManager.contentsOfDirectory(atPath: userDirectory.path(percentEncoded: false))
            for name in names where name.hasSuffix(".yaml") && !name.hasSuffix(".dict.yaml")
                && !["user.yaml", "installation.yaml"].contains(name) {
                // Reading follows symbolic links, which may be relative.
                guard let data = fileManager.contents(atPath: userDirectory.appending(path: name).path(percentEncoded: false))
                else { continue }
                try data.write(to: temporary.appending(path: name))
            }
            for (name, text) in replacing {
                try Data(text.utf8).write(to: temporary.appending(path: name))
            }
            if let schemaID, !schemaID.isEmpty, !schemaID.contains("/") {
                let file = "build/\(schemaID).schema.yaml"
                if let data = fileManager.contents(atPath: userDirectory.appending(path: file).path(percentEncoded: false)) {
                    try fileManager.createDirectory(at: temporary.appending(path: "build"), withIntermediateDirectories: true)
                    try data.write(to: temporary.appending(path: file))
                }
            }
        } catch {
            throw .deployFailed(error.localizedDescription)
        }

        engine.start(RimeConfiguration(sharedDataDirectory: sharedDirectory, userDataDirectory: temporary, minimumLogLevel: 2))
        defer { engine.stop() }
        for configID in configIDs where !engine.deployConfigFile("\(configID).yaml", versionKey: "config_version") {
            throw .deployFailed("librime 部署 \(configID).yaml 失败")
        }
        return try body(engine)
    }
}

/// A `<configID>.custom.yaml` as the pages load it: its text if it is valid
/// UTF-8, its patch keys, and why it cannot be edited, if it cannot.
struct CustomFile {
    var text: String?
    var keys: [String] = []
    var problem: PatchSaveError?

    init(userDirectory: URL, configID: String) {
        let file = CustomPatchWriter.resolvedFile(userDirectory.appending(path: "\(configID).custom.yaml"))
        let data = FileManager.default.contents(atPath: file.path(percentEncoded: false))
        text = data.flatMap(CustomPatchWriter.utf8Text)
        if data != nil && text == nil {
            problem = .notUTF8
            return
        }
        do {
            keys = try CustomPatchEditor(text: text ?? "").keys
        } catch {
            switch error {
            case .unsupportedLayout(let line, let reason):
                problem = .unsupportedLayout(line: line, reason: reason)
            }
        }
    }
}
