import Foundation
import Observation
import ScribeConfig

/// The state of the import screen: which directories, and how the import went.
///
/// Launch arguments (or defaults) override the directories for testing:
/// `-ScribeImportSource <path>`, `-ScribeUserDirectory <path>`, and
/// `-ScribeImportOnLaunch YES` to import once at launch without asking.
@MainActor @Observable
final class ImportModel {
    enum Phase {
        case ready
        case importing
        case finished(MigrationReport)
        case failed(String)
    }

    var source: URL
    var destination: URL
    private(set) var phase: Phase = .ready
    /// Shown before an import that would move existing files to a backup.
    var isConfirmingBackup = false

    private let importsOnLaunch: Bool
    private var handledLaunch = false

    init(defaults: UserDefaults = .standard, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let directories = UserDirectories(home: home)
        source = defaults.string(forKey: "ScribeImportSource").map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? directories.squirrel
        destination = defaults.string(forKey: "ScribeUserDirectory").map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? directories.scribe
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

    /// Runs the import once if `ScribeImportOnLaunch` is set.
    func importOnLaunchIfRequested() {
        guard importsOnLaunch, !handledLaunch else { return }
        handledLaunch = true
        startImport()
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
        phase = .importing
        Log.importer.notice("Importing \(importer.source.path(percentEncoded: false), privacy: .public) into \(importer.destination.path(percentEncoded: false), privacy: .public)")
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try importer.run() }
            }.value
            finish(with: result)
        }
    }

    /// Back to the import screen after a report or an error.
    func reset() {
        phase = .ready
    }

    private func finish(with result: Result<MigrationReport, any Error>) {
        switch result {
        case .success(let report):
            phase = .finished(report)
            let summary = report.summary
            Log.importer.notice("\(summary, privacy: .public)")
            emit(summary)
        case .failure(let error):
            let message = Self.message(for: error)
            phase = .failed(message)
            Log.importer.error("Import failed: \(String(describing: error), privacy: .public)")
            emit("Import failed: \(String(describing: error))")
        }
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
            + "; \(userDictionaries.dictionaries.count) user dictionaries, \(userDictionaries.snapshots.count) snapshots"
            + "; backup \(backup?.path(percentEncoded: false) ?? "none")"
            + "; from \(source.path(percentEncoded: false)) to \(destination.path(percentEncoded: false))"
    }
}
