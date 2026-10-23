import AppKit
import Foundation
import Observation
import ScribeConfig
import ScribeCore

/// The state of the import screen: which directories, and how the import went.
///
/// Launch arguments (or defaults) override the directories for testing:
/// `-ScribeImportSource <path>`, `-ScribeUserDirectory <path>`, and
/// `-ScribeImportOnLaunch YES` to import once at launch without asking.
/// With the Scribe directory overridden, the app never looks for or
/// notifies a running Scribe.
@MainActor @Observable
final class ImportModel {
    enum Phase {
        case ready
        /// What is being done right now.
        case importing(String)
        case finished(MigrationReport)
        case failed(String)
    }

    var source: URL
    var destination: URL
    private(set) var phase: Phase = .ready
    /// The user words of the last import; updated while Scribe syncs.
    private(set) var userWords = UserWordsOutcome()
    /// Shown before an import that would move existing files to a backup.
    var isConfirmingBackup = false

    /// Whether the destination is the Scribe directory the input method uses.
    let isLive: Bool
    private let importsOnLaunch: Bool
    private var handledLaunch = false

    static let scribeBundleIdentifier = "io.github.itvx.inputmethod.Scribe"
    /// How long to wait for a running Scribe to merge staged snapshots.
    static let syncTimeout: Duration = .seconds(120)

    init(defaults: UserDefaults = .standard, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let directories = UserDirectories(home: home)
        source = defaults.string(forKey: "ScribeImportSource").map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? directories.squirrel
        let override = defaults.string(forKey: "ScribeUserDirectory").map { URL(filePath: $0, directoryHint: .isDirectory) }
        destination = override ?? directories.scribe
        isLive = override == nil
        importsOnLaunch = defaults.bool(forKey: "ScribeImportOnLaunch")
    }

    var isImporting: Bool {
        if case .importing = phase { true } else { false }
    }

    /// Whether importing would first move the destination to a backup: it
    /// exists and is not an empty directory.
    var destinationHasContents: Bool {
        let path = destination.path(percentEncoded: false)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { return true }
        return (try? FileManager.default.contentsOfDirectory(atPath: path).isEmpty) == false
    }

    /// Cleans up snapshots an earlier import staged once Scribe has merged
    /// them, then imports if `ScribeImportOnLaunch` is set. Runs once.
    func launch() {
        guard !handledLaunch else { return }
        handledLaunch = true
        if let installationID = UserWordsStaging.installationID(in: destination) {
            let staging = UserWordsStaging(userDirectory: destination)
            if FileManager.default.fileExists(atPath: staging.folder.path(percentEncoded: false)),
               staging.removeIfMerged(installationID: installationID) {
                Log.importer.notice("Removed merged user words in \(staging.folder.path(percentEncoded: false), privacy: .public)")
            }
        }
        if importsOnLaunch {
            startImport()
        }
    }

    /// Imports, asking first when the destination has contents.
    func requestImport() {
        if destinationHasContents {
            isConfirmingBackup = true
        } else {
            startImport()
        }
    }

    func startImport() {
        guard !isImporting else { return }
        let importer = RimeDirectoryImporter(source: source, destination: destination)
        phase = .importing("正在复制文件…")
        userWords = UserWordsOutcome()
        Log.importer.notice("Importing \(importer.source.path(percentEncoded: false), privacy: .public) into \(importer.destination.path(percentEncoded: false), privacy: .public)")
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try importer.run() }
            }.value
            switch result {
            case .success(let report):
                await finish(report)
            case .failure(let error):
                phase = .failed(Self.message(for: error))
                Log.importer.error("Import failed: \(String(describing: error), privacy: .public)")
                emit("Import failed: \(String(describing: error))")
            }
        }
    }

    /// Back to the import screen after a report or an error.
    func reset() {
        phase = .ready
    }

    private func finish(_ report: MigrationReport) async {
        let serverRunning = isLive
            && !NSRunningApplication.runningApplications(withBundleIdentifier: Self.scribeBundleIdentifier).isEmpty
        userWords = await migrateUserWords(report)
        phase = .finished(report)
        let summary = report.summary + "; " + userWords.summary
        Log.importer.notice("\(summary, privacy: .public)")
        emit(summary)

        guard serverRunning else { return }
        // The running Scribe still has the moved files open; a reload makes it
        // use the imported directory.
        post(ServerNotification.reload)
        guard let staging = userWords.staging else { return }
        let posted = Date.now
        post(ServerNotification.sync)
        userWords.syncState = .waiting
        await waitForSync(staging, installationID: report.installationID, since: posted)
    }

    /// Exports every user dictionary from a copy and merges it into the
    /// destination. Snapshots that cannot be merged directly are staged for
    /// Scribe's own sync.
    private func migrateUserWords(_ report: MigrationReport) async -> UserWordsOutcome {
        let dictionaries = report.userDictionaries
        var outcome = UserWordsOutcome()
        guard !dictionaries.dictionaries.isEmpty || !dictionaries.snapshots.isEmpty else { return outcome }
        let work = FileManager.default.temporaryDirectory
            .appending(path: "scribe-settings-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        let migrator = UserWordsMigrator()

        var snapshots: [String: URL] = [:]
        let names = dictionaries.dictionaries
        for (index, name) in names.enumerated() {
            await show("正在导出用户词 \(name)（\(index + 1)/\(names.count)）…")
            let own = dictionaries.snapshots.filter { $0.lastPathComponent == "\(name).userdb.txt" }
            let exported = migrator.exportSnapshots(UserDictionaryImport(dictionaries: [name], snapshots: own),
                                                    from: report.source, workDirectory: work)
            snapshots.merge(exported.snapshots) { $1 }
            outcome.failed.merge(exported.failed) { $1 }
        }
        let others = dictionaries.snapshots.filter { snapshot in
            !names.contains { snapshot.lastPathComponent == "\($0).userdb.txt" }
        }
        snapshots.merge(migrator.exportSnapshots(UserDictionaryImport(dictionaries: [], snapshots: others),
                                                 from: report.source, workDirectory: work).snapshots) { $1 }

        var unmerged: [String: URL] = [:]
        for (name, snapshot) in snapshots.sorted(by: { $0.key < $1.key }) {
            await show("正在合并用户词 \(name)…")
            let result = migrator.restore([name: snapshot], into: report.destination)
            if result.merged.contains(name) {
                outcome.merged.append(name)
            } else {
                Log.importer.error("Could not merge \(name, privacy: .public): \(result.failed[name] ?? "", privacy: .public)")
                unmerged[name] = snapshot
            }
        }

        if !unmerged.isEmpty {
            // The imported sync_dir, or the sync folder of the imported directory.
            let staging = UserWordsStaging(userDirectory: report.destination)
            do {
                try staging.stage(unmerged)
                outcome.staged = unmerged.keys.sorted()
                outcome.staging = staging
                outcome.syncState = .nextSync
            } catch {
                for name in unmerged.keys {
                    outcome.failed[name] = "无法放进同步文件夹：\(error.localizedDescription)"
                }
            }
        }
        return outcome
    }

    /// Polls once a second until Scribe has backed up every staged
    /// dictionary after `since`, then removes the staging folder.
    private func waitForSync(_ staging: UserWordsStaging, installationID: String, since: Date) async {
        let deadline = ContinuousClock.now + Self.syncTimeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .seconds(1))
            if staging.removeIfMerged(installationID: installationID, since: since) {
                userWords.syncState = .merged
                Log.importer.notice("Scribe merged the staged user words; removed \(staging.folder.path(percentEncoded: false), privacy: .public)")
                emit("User words merged by Scribe's sync")
                return
            }
        }
        userWords.syncState = .waiting
        Log.importer.notice("Still waiting for Scribe to sync \(staging.folder.path(percentEncoded: false), privacy: .public)")
        emit("User words still waiting for Scribe's sync")
    }

    /// Posts one of the running Scribe's notifications. Only for the live directory.
    private func post(_ name: String) {
        guard isLive else { return }
        Log.importer.notice("Posting \(name, privacy: .public)")
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Shows progress and lets the window draw it before more work on the main actor.
    private func show(_ progress: String) async {
        phase = .importing(progress)
        try? await Task.sleep(for: .milliseconds(20))
    }

    /// Prints a line to stdout right away, so a smoke test can follow along.
    private func emit(_ line: String) {
        print(line)
        fflush(nil)
    }

    static func message(for error: any Error) -> String {
        switch error as? RimeImportError {
        case .sourceNotFound(let url):
            "找不到要导入的目录：\(url.path(percentEncoded: false))"
        case .overlappingDirectories:
            "来源目录和中书目录不能是同一个，也不能一个在另一个里面。"
        case nil:
            error.localizedDescription
        }
    }
}

/// What happened to the user words of an import.
struct UserWordsOutcome {
    enum SyncState {
        /// Nothing staged.
        case none
        /// Staged; Scribe merges them the next time it syncs.
        case nextSync
        /// Scribe was asked to sync and has not merged them yet.
        case waiting
        /// Scribe merged them and the staging folder is gone.
        case merged
    }

    /// Merged straight into the imported directory, sorted.
    var merged: [String] = []
    /// Staged for Scribe's sync, sorted.
    var staged: [String] = []
    var staging: UserWordsStaging?
    var syncState = SyncState.none
    /// Name to reason.
    var failed: [String: String] = [:]

    var summary: String {
        "user words merged \(merged.count) (\(merged.joined(separator: ", ")))"
            + ", staged \(staged.count) (\(staged.joined(separator: ", ")))"
            + ", failed \(failed.count) (\(failed.keys.sorted().joined(separator: ", ")))"
    }
}

extension MigrationReport {
    /// One line with counts per kind, skips, notices and the backup.
    var summary: String {
        let kinds = ImportedFileKind.allCases.compactMap { kind -> String? in
            let count = imported.count(where: { $0.kind == kind })
            return count > 0 ? "\(kind.rawValue) \(count)" : nil
        }
        let reasons = SkipReason.allCases.compactMap { reason -> String? in
            let count = skipped.count(where: { $0.reason == reason })
            return count > 0 ? "\(reason.rawValue) \(count)" : nil
        }
        return "Import finished: \(imported.count) imported (\(kinds.joined(separator: ", ")))"
            + "; \(skipped.count) skipped (\(reasons.joined(separator: ", ")))"
            + "; \(notices.count) notices"
            + "; backup \(backup?.path(percentEncoded: false) ?? "none")"
            + "; from \(source.path(percentEncoded: false)) to \(destination.path(percentEncoded: false))"
    }
}
