import Foundation
import RimeKit

/// Moves the words Squirrel has learned into Scribe's user dictionaries without touching Squirrel's files.
///
/// Runs librime in this process, so the engine must not be in use for
/// anything else meanwhile.
@MainActor
public struct UserWordsMigrator {
    public let engine: LibrimeEngine

    public init(engine: LibrimeEngine = .shared) {
        self.engine = engine
    }

    /// Exports a snapshot from a copy of each Squirrel user dictionary into `workDirectory`.
    /// The engine must be stopped; it is stopped again on return.
    ///
    /// A dictionary that cannot be exported falls back to Squirrel's own sync
    /// snapshot of it, if there is one. Snapshots of names without a
    /// dictionary are used as they are.
    public func exportSnapshots(_ dictionaries: UserDictionaryImport, from squirrelDirectory: URL,
                                workDirectory: URL) -> (snapshots: [String: URL], failed: [String: String]) {
        var squirrelSnapshots: [String: URL] = [:]
        for snapshot in dictionaries.snapshots {
            squirrelSnapshots[String(snapshot.lastPathComponent.dropLast(Self.snapshotExtension.count))] = snapshot
        }
        var snapshots = squirrelSnapshots.filter { !dictionaries.dictionaries.contains($0.key) }
        var reasons: [String: String] = [:]

        let user = workDirectory.appending(path: "user", directoryHint: .isDirectory)
        var copied: [String] = []
        for name in dictionaries.dictionaries {
            let source = squirrelDirectory.appending(path: "\(name).userdb", directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false), isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                let legacy = squirrelDirectory.appending(path: "\(name).userdb.kct").path(percentEncoded: false)
                reasons[name] = FileManager.default.fileExists(atPath: legacy)
                    ? "只有旧格式的 \(name).userdb.kct，librime 已不能读取"
                    : "找不到 \(name).userdb"
                continue
            }
            do {
                try Self.copyDatabase(source, to: user.appending(path: "\(name).userdb", directoryHint: .isDirectory))
                copied.append(name)
            } catch {
                reasons[name] = "复制词库失败：\(error.localizedDescription)"
            }
        }

        if !copied.isEmpty {
            if engine.isRunning {
                for name in copied { reasons[name] = "librime 正在使用，无法导出" }
            } else {
                do {
                    try prepareExport(in: workDirectory)
                    engine.start(RimeConfiguration(
                        sharedDataDirectory: workDirectory.appending(path: "shared", directoryHint: .isDirectory),
                        userDataDirectory: user,
                        minimumLogLevel: 2
                    ))
                    defer { engine.stop() }
                    // Reads installation.yaml, so snapshots go to <work>/sync/squirrel-import.
                    let ready = engine.runTask("installation_update")
                    for name in copied {
                        if ready, let snapshot = engine.backupUserDictionary(name) {
                            snapshots[name] = snapshot
                        } else {
                            reasons[name] = "导出快照失败"
                        }
                    }
                } catch {
                    for name in copied { reasons[name] = "准备导出失败：\(error.localizedDescription)" }
                }
            }
        }

        var failed: [String: String] = [:]
        for (name, reason) in reasons {
            if let fallback = squirrelSnapshots[name] {
                snapshots[name] = fallback
            } else {
                failed[name] = reason
            }
        }
        return (snapshots, failed)
    }

    /// Merges snapshots into the user dictionaries in `scribeDirectory` with librime's restore. Only for a
    /// directory no running Scribe has open. The engine must be stopped; it is stopped again on return.
    public func restore(_ snapshots: [String: URL], into scribeDirectory: URL) -> UserWordsMigrationResult {
        guard !snapshots.isEmpty else { return UserWordsMigrationResult(merged: [], failed: [:]) }
        guard !engine.isRunning else {
            return UserWordsMigrationResult(merged: [], failed: snapshots.mapValues { _ in "librime 正在使用，无法合并" })
        }
        let shared = FileManager.default.temporaryDirectory
            .appending(path: "scribe-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        } catch {
            return UserWordsMigrationResult(merged: [], failed: snapshots.mapValues { _ in error.localizedDescription })
        }
        defer { try? FileManager.default.removeItem(at: shared) }

        engine.start(RimeConfiguration(sharedDataDirectory: shared, userDataDirectory: scribeDirectory, minimumLogLevel: 2))
        defer { engine.stop() }
        // New dictionaries take the installation ID from installation.yaml.
        guard engine.runTask("installation_update") else {
            return UserWordsMigrationResult(merged: [], failed: snapshots.mapValues { _ in "librime 无法读取中书目录" })
        }
        var result = UserWordsMigrationResult(merged: [], failed: [:])
        for (name, snapshot) in snapshots.sorted(by: { $0.key < $1.key }) {
            if engine.restoreUserDictionary(from: snapshot) {
                result.merged.append(name)
            } else {
                result.failed[name] = "librime 合并快照失败"
            }
        }
        return result
    }

    static let snapshotExtension = ".userdb.txt"

    /// An installation.yaml that sends snapshots to `<work>/sync/squirrel-import`,
    /// and an empty shared data directory.
    private func prepareExport(in workDirectory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: workDirectory.appending(path: "shared", directoryHint: .isDirectory),
                                        withIntermediateDirectories: true)
        let sync = workDirectory.appending(path: "sync", directoryHint: .isDirectory)
        try InstallationFile.contents(installationID: UserWordsStaging.folderName, syncDirectory: sync.path(percentEncoded: false))
            .write(to: workDirectory.appending(path: "user/installation.yaml"), atomically: true, encoding: .utf8)
    }

    /// Copies a LevelDB directory, leaving out the LOCK file Squirrel may hold.
    private static func copyDatabase(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in try fileManager.contentsOfDirectory(atPath: source.path(percentEncoded: false)) where name != "LOCK" {
            try fileManager.copyItem(at: source.appending(path: name), to: destination.appending(path: name))
        }
    }
}

/// Which dictionaries a restore merged and which it could not.
public struct UserWordsMigrationResult: Equatable, Sendable {
    /// Dictionary names, sorted.
    public var merged: [String]
    /// Name to reason.
    public var failed: [String: String]

    public init(merged: [String], failed: [String: String]) {
        self.merged = merged
        self.failed = failed
    }
}
