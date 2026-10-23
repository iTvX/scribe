import Foundation
import RimeKit
import ScribeConfig

/// Real squirrel.yaml configs for snapshot cases, flattened to librime paths
/// in Tests/Fixtures/snapshots/configs/<name>.json. Tools/squirrel-oracle
/// feeds the same files to Squirrel, so both sides start from the same
/// config; SnapshotConfigTests keeps them in step with the YAML.
enum SnapshotConfigs {
    static let names = ["squirrel", "max-sample"]

    static func url(_ name: String) -> URL {
        Snapshot.repositoryRoot.appending(path: "Tests/Fixtures/snapshots/configs/\(name).json")
    }

    /// The committed config.
    static func load(_ name: String) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url(name)))
    }

    static func write(_ config: [String: String], name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let url = url(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (encoder.encode(config) + Data("\n".utf8)).write(to: url)
    }

    /// The config as librime reads it: SharedSupport's squirrel.yaml, or
    /// for "max-sample" rime-ice's squirrel.yaml with the sample's
    /// squirrel.custom.yaml deployed over it, as on Max's Mac.
    @MainActor
    static func generate(_ name: String) throws -> ConfigNode {
        let root = Snapshot.repositoryRoot
        let engine = LibrimeEngine.shared
        if name != "max-sample" {
            let text = try String(contentsOf: root.appending(path: "SharedSupport/squirrel.yaml"), encoding: .utf8)
            return try unwrap(engine.withConfig(.yaml(text)) { ConfigNode(snapshotOf: $0) })
        }
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appending(path: "scribe-ui-config-\(UUID().uuidString)", directoryHint: .isDirectory)
        let shared = directory.appending(path: "shared", directoryHint: .isDirectory)
        let user = directory.appending(path: "user", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: shared, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: user, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        try fileManager.copyItem(at: root.appending(path: "SharedSupport/squirrel.yaml"), to: shared.appending(path: "squirrel.yaml"))
        try fileManager.copyItem(at: root.appending(path: "Tests/Fixtures/config/rime-ice/squirrel.yaml"), to: user.appending(path: "squirrel.yaml"))
        try fileManager.copyItem(
            at: root.appending(path: "Tests/Fixtures/config/max-sample/squirrel.custom.yaml"),
            to: user.appending(path: "squirrel.custom.yaml")
        )
        engine.start(RimeConfiguration(sharedDataDirectory: shared, userDataDirectory: user, minimumLogLevel: 2, appName: "rime.scribe-ui-tests"))
        defer { engine.stop() }
        guard engine.deployConfigFile("squirrel.yaml", versionKey: "config_version") else { throw CocoaError(.fileWriteUnknown) }
        return try unwrap(engine.withConfig(.deployed("squirrel")) { ConfigNode(snapshotOf: $0) })
    }

    private static func unwrap(_ node: ConfigNode?) throws -> ConfigNode {
        guard let node else { throw CocoaError(.fileReadCorruptFile) }
        return node
    }

    /// Every scalar of `node` by its librime path, without librime's build
    /// information, whose file times differ from checkout to checkout.
    static func flatten(_ node: ConfigNode, prefix: String = "") -> [String: String] {
        if prefix == "__build_info" {
            return [:]
        }
        switch node {
        case let .scalar(value):
            return [prefix: value]
        case let .map(map):
            return map.reduce(into: [:]) { result, entry in
                result.merge(flatten(entry.value, prefix: prefix.isEmpty ? entry.key : "\(prefix)/\(entry.key)")) { $1 }
            }
        case .list, .null:
            return [:]
        }
    }

    /// The tree for flattened paths, the inverse of `flatten`.
    static func node(from config: [String: String]) -> ConfigNode {
        config.reduce(ConfigNode.map([:])) { node, entry in
            setting(.scalar(entry.value), in: node, at: entry.key)
        }
    }

    private static func setting(_ value: ConfigNode, in node: ConfigNode, at path: String) -> ConfigNode {
        let keys = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let key = keys.first else { return value }
        var map: [String: ConfigNode] = [:]
        if case let .map(existing) = node {
            map = existing
        }
        map[key] = keys.count == 1 ? value : setting(value, in: map[key] ?? .map([:]), at: keys.dropFirst().joined(separator: "/"))
        return .map(map)
    }
}
