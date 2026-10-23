import Foundation
import RimeKit

/// One change to a `*.custom.yaml` patch.
public enum PatchChange: Equatable, Sendable {
    case set(String, ConfigNode)
    case remove(String)
}

public struct PatchSaveResult: Equatable, Sendable {
    /// Entries removed because a set key now carries their effect, such as
    /// "schema_list/+" when setting "schema_list", in file order.
    public var supersededKeys: [String]
    /// The file written; the target when the custom file is a symbolic link.
    public var file: URL
}

/// Why a save did not happen. The file is unchanged in every case.
public enum PatchSaveError: Error, Equatable, Sendable {
    /// The file is no longer the text the page loaded.
    case changedOnDisk
    /// librime is running in this process; the checks need it to themselves.
    case engineBusy
    /// The file has a layout the editor cannot change safely.
    case unsupportedLayout(line: Int, reason: UnsupportedLayout)
    /// librime cannot read the new text.
    case unreadable
    /// The new text's patch keys are not the expected ones.
    case unexpectedKeys(expected: [String], actual: [String])
    /// A top-level key other than patch would change.
    case topLevelChanged(String)
    /// librime could not deploy the config with the new text.
    case deployFailed(String)
    /// After deploying, a set key does not have the value it was set to.
    case notEffective(key: String, expected: ConfigNode, actual: ConfigNode)
    /// Writing or reading back failed; the original bytes are back in place.
    case writeFailed(String)
}

/// Saves changes to a `*.custom.yaml` only after librime confirms them: the
/// new text must parse with the expected patch keys, and a deploy from a
/// temporary copy of the user directory must give each set key the intended
/// value. Edits go through `CustomPatchEditor`, so the rest of the file stays
/// as the user wrote it.
@MainActor
public struct CustomPatchWriter {
    public var userDirectory: URL
    public var sharedDirectory: URL
    public let engine: LibrimeEngine
    /// For tests: replaces the value the effective check expects for a key.
    var expectation: (String, ConfigNode) -> ConfigNode = { $1 }

    public init(userDirectory: URL, sharedDirectory: URL, engine: LibrimeEngine = .shared) {
        self.userDirectory = userDirectory
        self.sharedDirectory = sharedDirectory
        self.engine = engine
    }

    /// Applies `changes` to `<configID>.custom.yaml`, verifies, writes atomically. Throws without touching the file
    /// when any check fails. `expectedOriginal` is the text the page loaded; a different file on disk throws .changedOnDisk.
    public func save(_ configID: String, changes: [PatchChange], expectedOriginal: String?) throws(PatchSaveError) -> PatchSaveResult {
        guard !engine.isRunning else { throw .engineBusy }
        // Edit the target of a symbolic link, never the link.
        let file = Self.resolvedFile(userDirectory.appending(path: "\(configID).custom.yaml"))
        let originalData = FileManager.default.contents(atPath: file.path(percentEncoded: false))
        let original = originalData.map { String(decoding: $0, as: UTF8.self) }
        guard original == expectedOriginal else { throw .changedOnDisk }

        var editor: CustomPatchEditor
        do {
            editor = try CustomPatchEditor(text: original ?? "")
        } catch {
            switch error {
            case .unsupportedLayout(let line, let reason):
                throw .unsupportedLayout(line: line, reason: reason)
            }
        }
        var expectedKeys = editor.keys
        var superseded: [String] = []
        var sets: [(key: String, value: ConfigNode)] = []
        for change in changes {
            switch change {
            case .set(let key, let value):
                // The page writes the key's whole effective value, so entries
                // that patch inside it would apply twice.
                let removed = editor.removeDescendants(of: key)
                superseded += removed.filter { !superseded.contains($0) }
                editor.set(key, to: value)
                expectedKeys.removeAll { removed.contains($0) || $0 == key }
                expectedKeys.append(key)
                sets.removeAll { $0.key == key }
                sets.append((key, value))
            case .remove(let key):
                editor.remove(key)
                expectedKeys.removeAll { $0 == key }
                sets.removeAll { $0.key == key }
            }
        }
        superseded.removeAll { key in sets.contains { $0.key == key } }

        try checkParse(original: original ?? "", edited: editor.text, expectedKeys: expectedKeys)
        try checkEffect(configID, edited: editor.text, sets: sets)
        try write(editor.text, to: file, original: originalData)
        return PatchSaveResult(supersededKeys: superseded, file: file)
    }

    /// The new text parses, has exactly the expected patch keys, and leaves
    /// the other top-level keys alone.
    private func checkParse(original: String, edited: String, expectedKeys: [String]) throws(PatchSaveError) {
        func read(_ text: String) -> (patchKeys: [String], others: [String: ConfigNode])? {
            engine.withConfig(.yaml(text)) { reader in
                var others: [String: ConfigNode] = [:]
                for key in reader.mapKeys(at: "") ?? [] where key != "patch" {
                    others[key] = ConfigNode(snapshotOf: reader, at: key)
                }
                return (reader.mapKeys(at: "patch") ?? [], others)
            }
        }
        guard let before = read(original), let after = read(edited) else { throw .unreadable }
        let sortedExpected = expectedKeys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        let sortedActual = after.patchKeys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        guard sortedActual == sortedExpected else {
            throw .unexpectedKeys(expected: sortedExpected, actual: sortedActual)
        }
        for key in Set(before.others.keys).union(after.others.keys).sorted() where before.others[key] != after.others[key] {
            throw .topLevelChanged(key)
        }
    }

    /// Deploys the config with the new text from a temporary copy of the user
    /// directory and compares each set key's subtree with its value.
    private func checkEffect(_ configID: String, edited: String,
                             sets: [(key: String, value: ConfigNode)]) throws(PatchSaveError) {
        let deploy = TemporaryDeploy(engine: engine, userDirectory: userDirectory, sharedDirectory: sharedDirectory)
        try deploy.run(configID, replacing: ["\(configID).custom.yaml": edited]) { engine throws(PatchSaveError) in
            let actual = engine.withConfig(.deployed(configID)) { reader in
                sets.map { ConfigNode(snapshotOf: reader, at: $0.key) }
            }
            guard let actual else { throw .deployFailed("librime 打不开部署后的 \(configID).yaml") }
            for (set, value) in zip(sets, actual) {
                let expected = expectation(set.key, set.value)
                guard value == expected else {
                    throw .notEffective(key: set.key, expected: expected, actual: value)
                }
            }
        }
    }

    /// Replaces the file through a temporary file next to it, then reads it
    /// back; on any difference the original bytes go back.
    private func write(_ text: String, to file: URL, original: Data?) throws(PatchSaveError) {
        let fileManager = FileManager.default
        let data = Data(text.utf8)
        let temporary = file.deletingLastPathComponent()
            .appending(path: ".\(file.lastPathComponent).scribe-\(UUID().uuidString)", directoryHint: .notDirectory)
        do {
            try data.write(to: temporary)
            if original == nil {
                try fileManager.moveItem(at: temporary, to: file)
            } else {
                _ = try fileManager.replaceItemAt(file, withItemAt: temporary)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw .writeFailed(error.localizedDescription)
        }
        guard fileManager.contents(atPath: file.path(percentEncoded: false)) == data else {
            if let original {
                try? original.write(to: file)
            } else {
                try? fileManager.removeItem(at: file)
            }
            throw .writeFailed("写入后读回的内容不一致，已恢复原文件")
        }
    }

    /// The file with every symbolic link resolved, the file itself included;
    /// for a file that does not exist yet, its resolved directory.
    static func resolvedFile(_ url: URL) -> URL {
        if let real = realpath(url.path(percentEncoded: false), nil) {
            defer { free(real) }
            return URL(filePath: String(cString: real), directoryHint: .notDirectory)
        }
        return RimeDirectoryImporter.resolved(url.deletingLastPathComponent())
            .appending(path: url.lastPathComponent, directoryHint: .notDirectory)
    }
}
