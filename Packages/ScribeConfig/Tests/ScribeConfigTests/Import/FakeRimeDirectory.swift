import Foundation

/// A copy of `Tests/Fixtures/rime-dir` in a fresh temporary directory, plus
/// the files git cannot hold: deploy output, a nested repository, user
/// dictionaries, librime's trash, Finder files and a sync snapshot.
///
/// Everything lives under `root`; call `remove()` when done.
struct FakeRimeDirectory {
    static let fixture = URL(filePath: #filePath)
        .deletingLastPathComponent() // Import
        .deletingLastPathComponent() // ScribeConfigTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // ScribeConfig
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository root
        .appending(path: "Tests/Fixtures/rime-dir", directoryHint: .isDirectory)

    /// The `installation_id` in the fixture's `installation.yaml`.
    static let squirrelInstallationID = "5c1d2f3e-squirrel-fixture-0001"
    /// The custom `sync_dir` in the fixture's `installation.yaml`; it does not exist.
    static let fixtureSyncDirectory = "/Volumes/Fixture Cloud/Rime 同步"

    /// The files the fixture adds at runtime, relative to the source.
    static let runtimeFiles: [String: Data] = [
        "build/rime_ice.prism.bin": Data([0x52, 0x49, 0x4D, 0x45, 0x00, 0x01]),
        ".git/HEAD": Data("ref: refs/heads/main\n".utf8),
        ".git/config": Data("[core]\n\trepositoryformatversion = 0\n\tbare = false\n".utf8),
        ".git/hooks/pre-commit": Data("#!/bin/sh\nexit 0\n".utf8),
        ".git/objects/3f/4a8c1d0e2b7f9a6c5d4e3f2a1b0c9d8e7f6a5b": Data([0x78, 0x01, 0x2B, 0x49, 0x4D]),
        ".git/.DS_Store": Data([0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31]),
        "rime_ice.userdb/CURRENT": Data("MANIFEST-000004\n".utf8),
        "rime_ice.userdb/LOCK": Data(),
        "wubi86.userdb.kct": Data([0x4B, 0x43, 0x0A, 0x00]),
        "rime_ice.userdb.txt": Data("# Rime user dictionary export\n".utf8),
        "trash/old.yaml": Data("patch: {}\n".utf8),
        ".DS_Store": Data([0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31]),
        "lua/.DS_Store": Data([0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31]),
        "lua/build/keep.lua": Data("return {}\n".utf8),
        "sync/\(squirrelInstallationID)/rime_ice.userdb.txt": Data("# Rime user dictionary\nzhong shu\t中书\tc=3\n".utf8),
    ]

    let root: URL
    var source: URL { root.appending(path: "Rime", directoryHint: .isDirectory) }
    var destination: URL { root.appending(path: "Scribe", directoryHint: .isDirectory) }

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appending(path: "ScribeConfigTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.copyItem(at: Self.fixture, to: source)
        for (path, data) in Self.runtimeFiles {
            try write(data, to: path)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url(".git/hooks/pre-commit").path(percentEncoded: false))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// A path inside the source.
    func url(_ path: String) -> URL {
        source.appending(path: path)
    }

    func write(_ data: Data, to path: String) throws {
        let file = url(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }

    func write(_ text: String, to path: String) throws {
        try write(Data(text.utf8), to: path)
    }

    /// Replaces the source's `installation.yaml`; nil removes it.
    func setInstallationFile(_ text: String?) throws {
        if let text {
            try write(text, to: "installation.yaml")
        } else {
            try FileManager.default.removeItem(at: url("installation.yaml"))
        }
    }

    /// The fixture's `installation.yaml` without its `sync_dir` line, so
    /// librime would use the default `sync/` inside the source.
    func useDefaultSyncDirectory() throws {
        let text = try String(contentsOf: url("installation.yaml"), encoding: .utf8)
        let lines = text.split(separator: "\n").filter { !$0.hasPrefix("sync_dir:") }
        try setInstallationFile(lines.joined(separator: "\n") + "\n")
    }
}

/// Every item under a directory, without following symbolic links: relative
/// paths mapped to type, permissions, contents or link target and, unless
/// `dates` is false, modification date.
func snapshot(of directory: URL, dates: Bool = true) throws -> [String: String] {
    let fileManager = FileManager.default
    let root = directory.path(percentEncoded: false)
    var result: [String: String] = [:]
    func visit(_ relative: String) throws {
        let path = relative.isEmpty ? root : (root as NSString).appendingPathComponent(relative)
        let attributes = try fileManager.attributesOfItem(atPath: path)
        let type = attributes[.type] as? FileAttributeType
        let date = dates ? (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0 : 0
        let permissions = attributes[.posixPermissions] as? Int ?? 0
        switch type {
        case .typeDirectory:
            result[relative] = "directory \(permissions) \(date)"
            for name in try fileManager.contentsOfDirectory(atPath: path) {
                try visit(relative.isEmpty ? name : relative + "/" + name)
            }
        case .typeSymbolicLink:
            result[relative] = "link \(try fileManager.destinationOfSymbolicLink(atPath: path)) \(date)"
        default:
            let data = fileManager.contents(atPath: path) ?? Data()
            result[relative] = "file \(permissions) \(date) \(data.base64EncodedString())"
        }
    }
    try visit("")
    return result
}

/// Whether anything, even a dangling symbolic link, exists at a URL.
func itemExists(_ url: URL) -> Bool {
    (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))) != nil
}

/// The names in a directory, sorted.
func names(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
}
