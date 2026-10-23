import Foundation

/// Copies a Rime user directory, such as Squirrel's ~/Library/Rime, into Scribe's.
///
/// The copy is assembled in a staging directory next to the destination and
/// moved into place at the end, so the destination never holds half an import.
/// A destination that is not empty is moved to a backup first, never deleted.
public struct RimeDirectoryImporter: Sendable {
    public var source: URL
    public var destination: URL

    public init(source: URL, destination: URL) {
        self.source = source
        self.destination = destination
    }

    /// Never writes to `source`. Synchronous; callers run it off the main actor.
    public func run(now: Date = .now,
                    makeInstallationID: @Sendable () -> String = { UUID().uuidString.lowercased() }) throws -> MigrationReport {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw RimeImportError.sourceNotFound(source) }

        let sourceRoot = Self.resolved(source)
        let target = Self.resolved(destination)
        guard !Self.overlaps(sourceRoot, target) else { throw RimeImportError.overlappingDirectories }

        let installationURL = sourceRoot.appending(path: "installation.yaml")
        let installation = (try? String(contentsOf: installationURL, encoding: .utf8)).map(InstallationFile.init(parsing:))
        let squirrelInstallationID = installation?.installationID
        let syncDirectory = installation?.syncDirectory
        let customSyncDirectory = syncDirectory.flatMap { $0.hasPrefix("/") ? URL(filePath: $0, directoryHint: .isDirectory) : nil }

        let parent = target.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appending(path: ".\(target.lastPathComponent).importing-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)

        do {
            var copier = DirectoryCopier(
                sourceRoot: sourceRoot,
                stagingRoot: staging,
                syncDirectoryPath: customSyncDirectory.flatMap { Self.relativePath(of: Self.resolved($0), in: sourceRoot) }
            )
            try copier.copy()

            let installationID = makeInstallationID()
            try InstallationFile.contents(installationID: installationID, syncDirectory: syncDirectory)
                .write(to: staging.appending(path: "installation.yaml"), atomically: false, encoding: .utf8)

            let snapshotFolder = (customSyncDirectory ?? source.appending(path: "sync", directoryHint: .isDirectory))
            let userDictionaries = UserDictionaryImport(
                dictionaries: copier.userDictionaryNames.sorted(),
                snapshots: squirrelInstallationID.map {
                    Self.snapshots(in: snapshotFolder.appending(path: $0, directoryHint: .isDirectory))
                } ?? []
            )
            var notices = copier.notices
            if !userDictionaries.dictionaries.isEmpty && userDictionaries.snapshots.isEmpty {
                notices.append(.userDictionariesNotSynced(userDictionaries.dictionaries))
            }

            let backup = try Self.moveIntoPlace(staging, at: target, now: now)
            return MigrationReport(
                source: source,
                destination: destination,
                backup: backup,
                imported: (copier.imported + [ImportedItem(path: "installation.yaml", kind: .installation)])
                    .sorted { $0.path < $1.path },
                skipped: copier.skipped.sorted { $0.path < $1.path },
                installationID: installationID,
                squirrelInstallationID: squirrelInstallationID,
                syncDirectory: syncDirectory,
                userDictionaries: userDictionaries,
                notices: notices
            )
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    /// Renames the staging directory to `target`, first moving whatever is
    /// there to a backup unless it is an empty directory. Returns the backup.
    private static func moveIntoPlace(_ staging: URL, at target: URL, now: Date) throws -> URL? {
        let fileManager = FileManager.default
        let path = target.path(percentEncoded: false)
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
            try fileManager.moveItem(at: staging, to: target)
            return nil
        }
        if attributes[.type] as? FileAttributeType == .typeDirectory,
           try fileManager.contentsOfDirectory(atPath: path).isEmpty {
            try fileManager.removeItem(at: target)
            try fileManager.moveItem(at: staging, to: target)
            return nil
        }

        let backup = backupURL(for: target, now: now)
        try fileManager.moveItem(at: target, to: backup)
        do {
            try fileManager.moveItem(at: staging, to: target)
        } catch {
            try? fileManager.moveItem(at: backup, to: target)
            throw error
        }
        return backup
    }

    /// `<parent>/<name> backup <yyyyMMdd-HHmmss>`, with `-2`, `-3`, ... appended
    /// when that is taken.
    private static func backupURL(for target: URL, now: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(target.lastPathComponent) backup \(formatter.string(from: now))"
        let parent = target.deletingLastPathComponent()
        var name = base
        var counter = 1
        while (try? FileManager.default.attributesOfItem(atPath: parent.appending(path: name).path(percentEncoded: false))) != nil {
            counter += 1
            name = "\(base)-\(counter)"
        }
        return parent.appending(path: name, directoryHint: .isDirectory)
    }

    /// The `*.userdb.txt` files in a folder, sorted; none if it does not exist.
    private static func snapshots(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".userdb.txt") }.sorted().map {
            folder.appending(path: $0, directoryHint: .notDirectory)
        }
    }

    /// The URL with every symbolic link resolved, also when it does not exist
    /// yet: the deepest existing ancestor is resolved and the rest appended.
    static func resolved(_ url: URL) -> URL {
        let components = url.standardizedFileURL.pathComponents
        for count in stride(from: components.count, to: 0, by: -1) {
            let prefix = NSString.path(withComponents: Array(components[..<count]))
            guard let real = realpath(prefix, nil) else { continue }
            defer { free(real) }
            var result = URL(filePath: String(cString: real), directoryHint: .isDirectory)
            for component in components[count...] {
                result.append(path: component, directoryHint: .isDirectory)
            }
            return result
        }
        return url.standardizedFileURL
    }

    /// Whether two resolved URLs are the same or one contains the other.
    static func overlaps(_ first: URL, _ second: URL) -> Bool {
        let a = first.pathComponents, b = second.pathComponents
        return a.starts(with: b) || b.starts(with: a)
    }

    /// `url` relative to `root`, "/" separated, if it lies strictly inside it.
    static func relativePath(of url: URL, in root: URL) -> String? {
        let components = url.pathComponents, rootComponents = root.pathComponents
        guard components.count > rootComponents.count, components.starts(with: rootComponents) else { return nil }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }
}

public enum RimeImportError: Error, Equatable, Sendable {
    /// The source is missing or not a directory.
    case sourceNotFound(URL)
    /// The source and destination are the same, or one is inside the other.
    case overlappingDirectories
}
