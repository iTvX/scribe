import Foundation

/// Copies a Rime user directory into a staging directory, applying the skip
/// rules and collecting what goes into the report.
struct DirectoryCopier {
    let sourceRoot: URL
    let stagingRoot: URL
    /// A custom `sync_dir` inside the source, relative to it.
    let syncDirectoryPath: String?

    private(set) var imported: [ImportedItem] = []
    private(set) var skipped: [SkippedItem] = []
    private(set) var userDictionaryNames: Set<String> = []
    private var fileNotices: [(key: (path: String, line: Int, rank: Int), notice: MigrationNotice)] = []

    init(sourceRoot: URL, stagingRoot: URL, syncDirectoryPath: String?) {
        self.sourceRoot = sourceRoot
        self.stagingRoot = stagingRoot
        self.syncDirectoryPath = syncDirectoryPath
    }

    /// Notices about the copied files, in path and line order.
    var notices: [MigrationNotice] {
        fileNotices.sorted { $0.key < $1.key }.map(\.notice)
    }

    /// Copies everything except `installation.yaml`, which the importer writes.
    mutating func copy() throws {
        try copyContents(ofDirectory: "")
    }

    private mutating func copyContents(ofDirectory directory: String) throws {
        let fileManager = FileManager.default
        let names = try fileManager.contentsOfDirectory(atPath: sourcePath(directory)).sorted()
        for name in names {
            let path = directory.isEmpty ? name : directory + "/" + name
            let source = sourcePath(path)
            let target = stagingPath(path)
            if let reason = skipReason(path: path, name: name, atRoot: directory.isEmpty) {
                skipped.append(SkippedItem(path: path, reason: reason))
                continue
            }
            if path == ".git" {
                try fileManager.copyItem(atPath: source, toPath: target)
                imported.append(ImportedItem(path: path, kind: .gitRepository))
                continue
            }
            if path == "installation.yaml" {
                continue
            }

            let type = try fileManager.attributesOfItem(atPath: source)[.type] as? FileAttributeType
            switch type {
            case .typeDirectory:
                try fileManager.createDirectory(atPath: target, withIntermediateDirectories: false)
                try copyContents(ofDirectory: path)
            case .typeRegular:
                try fileManager.copyItem(atPath: source, toPath: target)
                record(path: path, at: target)
            case .typeSymbolicLink:
                let destination = try fileManager.destinationOfSymbolicLink(atPath: source)
                try fileManager.createSymbolicLink(atPath: target, withDestinationPath: destination)
                imported.append(ImportedItem(path: path, kind: ImportedFileKind(path: path)))
                if Self.leavesSource(link: path, target: destination) {
                    fileNotices.append(((path, 0, 0), .symbolicLink(path: path, target: destination)))
                }
            default:
                // Sockets, pipes and devices have no place in a Rime directory.
                continue
            }
        }
    }

    private mutating func record(path: String, at target: String) {
        let kind = ImportedFileKind(path: path)
        imported.append(ImportedItem(path: path, kind: kind))
        switch kind {
        case .otherFrontendConfig:
            fileNotices.append(((path, 0, 1), .otherFrontendConfig(file: path)))
        case .lua where path.hasSuffix(".lua"):
            guard let data = FileManager.default.contents(atPath: target) else { return }
            for notice in LuaFrontendScanner.notices(in: String(decoding: data, as: UTF8.self), file: path) {
                guard case .luaChecksFrontend(_, let line, _) = notice else { continue }
                fileNotices.append(((path, line, 2), notice))
            }
        default:
            break
        }
    }

    private mutating func skipReason(path: String, name: String, atRoot: Bool) -> SkipReason? {
        if name == ".DS_Store" {
            return .systemFile
        }
        if path == syncDirectoryPath {
            return .syncDirectory
        }
        guard atRoot else { return nil }
        switch name {
        case "build":
            return .buildOutput
        case "sync":
            return .syncDirectory
        case "trash":
            return .trash
        default:
            for suffix in [".userdb", ".userdb.kct"] where name.hasSuffix(suffix) {
                // Hidden ones, such as .temp.userdb, are librime's scratch space.
                if !name.hasPrefix(".") {
                    userDictionaryNames.insert(String(name.dropLast(suffix.count)))
                }
                return .userDictionary
            }
            return name.hasSuffix(".userdb.txt") ? .userDictionary : nil
        }
    }

    /// Whether a link's target is absolute or climbs out of the source.
    static func leavesSource(link: String, target: String) -> Bool {
        if target.hasPrefix("/") {
            return true
        }
        var components = link.split(separator: "/").dropLast()
        for component in target.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                guard components.popLast() != nil else { return true }
            default:
                components.append(component)
            }
        }
        return false
    }

    private func sourcePath(_ path: String) -> String {
        sourceRoot.appending(path: path).path(percentEncoded: false)
    }

    private func stagingPath(_ path: String) -> String {
        stagingRoot.appending(path: path).path(percentEncoded: false)
    }
}
