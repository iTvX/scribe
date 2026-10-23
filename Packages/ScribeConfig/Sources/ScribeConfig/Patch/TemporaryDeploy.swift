import Foundation
import RimeKit

/// Deploys one config from a temporary copy of a user directory, so its
/// effective values can be read without touching the real directory or
/// waiting for Scribe to deploy it.
@MainActor
struct TemporaryDeploy {
    let engine: LibrimeEngine
    let userDirectory: URL
    let sharedDirectory: URL

    /// Copies the top-level `*.yaml` files of the user directory (but not
    /// user.yaml or installation.yaml) with `replacing` written over them,
    /// deploys `<configID>.yaml`, runs `body` and stops the engine again.
    func run<T>(_ configID: String, replacing: [String: String] = [:],
                _ body: (LibrimeEngine) throws(PatchSaveError) -> T) throws(PatchSaveError) -> T {
        guard !engine.isRunning else { throw .engineBusy }
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory
            .appending(path: "scribe-deploy-check-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: temporary) }
        do {
            try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
            let names = try fileManager.contentsOfDirectory(atPath: userDirectory.path(percentEncoded: false))
            for name in names where name.hasSuffix(".yaml") && !["user.yaml", "installation.yaml"].contains(name) {
                // Reading follows symbolic links, which may be relative.
                guard let data = fileManager.contents(atPath: userDirectory.appending(path: name).path(percentEncoded: false))
                else { continue }
                try data.write(to: temporary.appending(path: name))
            }
            for (name, text) in replacing {
                try Data(text.utf8).write(to: temporary.appending(path: name))
            }
        } catch {
            throw .deployFailed(error.localizedDescription)
        }

        engine.start(RimeConfiguration(sharedDataDirectory: sharedDirectory, userDataDirectory: temporary, minimumLogLevel: 2))
        defer { engine.stop() }
        guard engine.deployConfigFile("\(configID).yaml", versionKey: "config_version") else {
            throw .deployFailed("librime 部署 \(configID).yaml 失败")
        }
        return try body(engine)
    }
}
