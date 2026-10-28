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

/// Why a save could not be completed or verified. Conflicts preserve the new
/// on-disk contents; a failed post-write verification retains the backup.
public enum PatchSaveError: Error, Equatable, Sendable {
    /// The file is no longer the text the page loaded.
    case changedOnDisk
    /// A previously imported or manually created link points outside the
    /// user's Scribe directory. Reading is allowed, writing requires making
    /// an independent copy first.
    case externalLink(URL)
    /// An uncoordinated writer changed the file at replacement time. Both
    /// versions are retained; the URL holds the displaced version.
    case concurrentWrite(URL)
    /// The file is not valid UTF-8, so it cannot be edited byte for byte.
    case notUTF8
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
    /// Writing or verification failed; the message includes any recovery path.
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
    /// Exercises an uncoordinated editor racing the atomic replacement.
    var beforeReplace: (() throws -> Void)?

    public init(userDirectory: URL, sharedDirectory: URL, engine: LibrimeEngine = .shared) {
        self.userDirectory = userDirectory
        self.sharedDirectory = sharedDirectory
        self.engine = engine
    }

    /// Applies `changes` to `<configID>.custom.yaml`, verifies, writes atomically. Validation
    /// or conflict failures leave the file untouched. `expectedOriginal` is the text the page loaded; a different file on disk throws .changedOnDisk.
    public func save(_ configID: String, changes: [PatchChange], expectedOriginal: String?) throws(PatchSaveError) -> PatchSaveResult {
        guard !engine.isRunning else { throw .engineBusy }
        // Edit the target of a symbolic link, never the link.
        let requestedFile = userDirectory.appending(path: "\(configID).custom.yaml")
        let file = Self.resolvedFile(requestedFile)
        guard file.pathComponents.starts(with: RimeDirectoryImporter.resolved(userDirectory).pathComponents) else {
            throw .externalLink(file)
        }
        let originalData = FileManager.default.contents(atPath: file.path(percentEncoded: false))
        var original: String?
        if let originalData {
            guard let text = Self.utf8Text(originalData) else { throw .notUTF8 }
            original = text
        }
        // Bytes, since String equality ignores Unicode normalization.
        guard originalData == expectedOriginal.map({ Data($0.utf8) }) else { throw .changedOnDisk }

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
        try write(editor.text, to: file, requestedFile: requestedFile, original: originalData)
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

    /// Validate again at commit time, inside a coordinated write. Keep the
    /// replaced version until verification succeeds; never roll back over a
    /// new edit made by a writer that does not participate in coordination.
    private func write(_ text: String, to file: URL, requestedFile: URL, original: Data?) throws(PatchSaveError) {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var failure: PatchSaveError?
        coordinator.coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { coordinated in
            guard Self.resolvedFile(requestedFile).path == file.path,
                  FileManager.default.contents(atPath: coordinated.path) == original else {
                failure = .changedOnDisk
                return
            }
            do {
                try replace(text, at: coordinated, original: original)
            } catch {
                failure = error as? PatchSaveError ?? .writeFailed(error.localizedDescription)
            }
        }
        if let failure { throw failure }
        if let coordinationError { throw .writeFailed(coordinationError.localizedDescription) }
    }

    private func replace(_ text: String, at file: URL, original: Data?) throws(PatchSaveError) {
        let fileManager = FileManager.default
        let data = Data(text.utf8)
        let temporary = file.deletingLastPathComponent()
            .appending(path: ".\(file.lastPathComponent).scribe-\(UUID().uuidString)", directoryHint: .notDirectory)
        let backupName = ".\(file.lastPathComponent).scribe-backup-\(UUID().uuidString)"
        let backup = file.deletingLastPathComponent().appending(path: backupName)
        do {
            try data.write(to: temporary)
            try beforeReplace?()
            if original == nil {
                try fileManager.moveItem(at: temporary, to: file)
            } else {
                _ = try fileManager.replaceItemAt(file, withItemAt: temporary, backupItemName: backupName,
                                                 options: .withoutDeletingBackupItem)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            let recovery = fileManager.fileExists(atPath: backup.path) ? "；原文件备份：\(backup.path)" : ""
            throw .writeFailed(error.localizedDescription + recovery)
        }
        if let original {
            guard let displaced = fileManager.contents(atPath: backup.path) else {
                throw .writeFailed("无法校验替换时的备份，请检查当前文件和 \(backup.path)")
            }
            guard displaced == original else { throw .concurrentWrite(backup) }
        }
        guard fileManager.contents(atPath: file.path(percentEncoded: false)) == data else {
            let recovery = original == nil ? "" : "，原文件保存在 \(backup.path)"
            throw .writeFailed("写入后的文件被再次改动，已保留当前内容\(recovery)")
        }
        try? fileManager.removeItem(at: backup)
    }

    /// The text of valid UTF-8 bytes, or nil; decoding is exact, so writing
    /// the text back gives the same bytes.
    nonisolated static func utf8Text(_ data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        return Data(text.utf8) == data ? text : nil
    }

    /// The file with every symbolic link resolved, the file itself included;
    /// for a file that does not exist yet, its resolved directory.
    nonisolated static func resolvedFile(_ url: URL) -> URL {
        if let real = realpath(url.path(percentEncoded: false), nil) {
            defer { free(real) }
            return URL(filePath: String(cString: real), directoryHint: .notDirectory)
        }
        return RimeDirectoryImporter.resolved(url.deletingLastPathComponent())
            .appending(path: url.lastPathComponent, directoryHint: .notDirectory)
    }
}
