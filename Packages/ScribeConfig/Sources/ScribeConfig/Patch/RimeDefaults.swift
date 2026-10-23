import Foundation
import RimeKit

/// The settings of default.yaml that Scribe Settings edits, as librime
/// deploys them from the user directory as it is now.
public struct RimeDefaults: Equatable, Sendable {
    /// A list of maps; keys besides `schema`, such as `case`, are kept.
    public var schemaList: ConfigNode
    public var pageSize: Int?
    public var switcherHotkeys: [String]
    /// `ascii_composer/switch_key`: key name to action, such as Shift_L: commit_code.
    public var switchKey: [String: String]
    /// default.custom.yaml as it is now, or nil when there is none; a save
    /// passes it as `expectedOriginal`.
    public var customText: String?
    /// Why default.custom.yaml cannot be edited, such as `.notUTF8` or an
    /// unsupported layout; nil when it can.
    public var editProblem: PatchSaveError?

    public init(schemaList: ConfigNode, pageSize: Int?, switcherHotkeys: [String], switchKey: [String: String],
                customText: String?, editProblem: PatchSaveError? = nil) {
        self.schemaList = schemaList
        self.pageSize = pageSize
        self.switcherHotkeys = switcherHotkeys
        self.switchKey = switchKey
        self.customText = customText
        self.editProblem = editProblem
    }

    /// The schema IDs in `schemaList`, in order.
    public var schemaIDs: [String] {
        guard case .list(let items) = schemaList else { return [] }
        return items.compactMap { $0.string(at: "schema") }
    }

    /// Reads them from a deploy of a temporary copy of the user directory,
    /// so they are right even before Scribe has ever deployed it.
    @MainActor
    public static func load(userDirectory: URL, sharedDirectory: URL,
                            engine: LibrimeEngine = .shared) throws(PatchSaveError) -> RimeDefaults {
        let custom = CustomPatchWriter.resolvedFile(userDirectory.appending(path: "default.custom.yaml"))
        let customData = FileManager.default.contents(atPath: custom.path(percentEncoded: false))
        let customText = customData.flatMap(CustomPatchWriter.utf8Text)
        var editProblem: PatchSaveError?
        if customData != nil && customText == nil {
            editProblem = .notUTF8
        } else {
            do {
                _ = try CustomPatchEditor(text: customText ?? "")
            } catch {
                switch error {
                case .unsupportedLayout(let line, let reason):
                    editProblem = .unsupportedLayout(line: line, reason: reason)
                }
            }
        }
        let deploy = TemporaryDeploy(engine: engine, userDirectory: userDirectory, sharedDirectory: sharedDirectory)
        return try deploy.run("default") { engine throws(PatchSaveError) in
            let defaults = engine.withConfig(.deployed("default")) { reader in
                let hotkeys = ConfigNode(snapshotOf: reader, at: "switcher/hotkeys")
                let switchKey = ConfigNode(snapshotOf: reader, at: "ascii_composer/switch_key")
                return RimeDefaults(
                    schemaList: ConfigNode(snapshotOf: reader, at: "schema_list"),
                    pageSize: reader.int(at: "menu/page_size"),
                    switcherHotkeys: hotkeys.scalars,
                    switchKey: switchKey.scalarMap,
                    customText: customText,
                    editProblem: editProblem
                )
            }
            guard let defaults else { throw .deployFailed("librime 打不开部署后的 default.yaml") }
            return defaults
        }
    }
}

extension ConfigNode {
    /// The scalars of a list, skipping anything else.
    var scalars: [String] {
        guard case .list(let items) = self else { return [] }
        return items.compactMap { if case .scalar(let value) = $0 { value } else { nil } }
    }

    /// The scalar values of a map, skipping anything else.
    var scalarMap: [String: String] {
        guard case .map(let map) = self else { return [:] }
        return map.compactMapValues { if case .scalar(let value) = $0 { value } else { nil } }
    }
}
