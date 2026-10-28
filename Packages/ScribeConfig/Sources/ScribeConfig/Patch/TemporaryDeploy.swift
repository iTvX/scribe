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

    /// Copies `*.yaml` files, including nested include dependencies (but not
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
            try copyConfigs(from: userDirectory, to: temporary, ancestors: [], atRoot: true, snapshotRoot: temporary)
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

    /// Materialize links in the snapshot so relative includes keep working
    /// and a temporary deploy can never write through to the live directory.
    private func copyConfigs(from source: URL, to target: URL, ancestors: Set<String>, atRoot: Bool, snapshotRoot: URL) throws {
        let fileManager = FileManager.default
        let resolved = source.resolvingSymlinksInPath()
        guard !ancestors.contains(resolved.path), !resolved.pathComponents.starts(with: snapshotRoot.resolvingSymlinksInPath().pathComponents) else {
            throw PatchSaveError.deployFailed("配置目录包含循环链接：\(source.path)")
        }
        let ancestors = ancestors.union([resolved.path])
        for name in try fileManager.contentsOfDirectory(atPath: source.path).sorted() {
            if name == ".git" || name.hasSuffix(".userdb") { continue }
            if atRoot && ["build", "sync", "trash", "user.yaml", "installation.yaml"].contains(name) { continue }
            let file = source.appending(path: name)
            var directory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: file.path, isDirectory: &directory)
            if directory.boolValue {
                let destination = target.appending(path: name)
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                try copyConfigs(from: file, to: destination, ancestors: ancestors, atRoot: false, snapshotRoot: snapshotRoot)
            } else if name.hasSuffix(".yaml"), !name.hasSuffix(".dict.yaml") {
                let type = try fileManager.attributesOfItem(atPath: file.resolvingSymlinksInPath().path)[.type] as? FileAttributeType
                guard exists, type == .typeRegular else {
                    throw PatchSaveError.deployFailed("无法读取配置文件：\(file.path)")
                }
                try Data(contentsOf: file).write(to: target.appending(path: name))
            }
        }
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
        if !file.pathComponents.starts(with: RimeDirectoryImporter.resolved(userDirectory).pathComponents) {
            problem = .externalLink(file)
            return
        }
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
