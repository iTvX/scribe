import Foundation
import RimeKit

/// Where an `appearance` value in scribe.yaml comes from.
public enum KeyProvenance: Equatable, Sendable {
    /// The scribe config has no value here.
    case squirrelOrDefault
    /// scribe.custom.yaml has exactly this patch key: 恢复默认 removes it.
    case ownEntry
    /// Set through an ancestor entry such as `appearance` or `appearance/font`.
    case insideEntry(String)
}

/// What the 外观 page shows and edits: the deployed squirrel.yaml and
/// scribe.yaml, the active schema's `style`, and scribe.custom.yaml.
public struct AppearanceSettings: Equatable, Sendable {
    /// The deployed squirrel.yaml.
    public var squirrel: ConfigNode
    /// The deployed scribe.yaml.
    public var scribe: ConfigNode
    /// The active schema's `style` map, if it has one.
    public var schemaStyle: ConfigNode?
    /// scribe.custom.yaml if it is valid UTF-8; a save passes it as `expectedOriginal`.
    public var customText: String?
    /// The patch keys of scribe.custom.yaml; empty without a file.
    public var customKeys: [String]
    /// Why scribe.custom.yaml cannot be edited, such as `.notUTF8`.
    public var editProblem: PatchSaveError?
    public var themes: [ThemeInfo]
    public var diagnostics: [ConfigDiagnostic]
    /// The Squirrel-format settings that could move to scribe.custom.yaml;
    /// nil when Scribe's own squirrel.yaml is missing or unreadable.
    public var conversion: ScribeConversion?

    /// `written` is scribe.yaml as the user wrote it, for the diagnostics;
    /// it defaults to `scribe`.
    public init(squirrel: ConfigNode, scribe: ConfigNode, schemaStyle: ConfigNode? = nil, customText: String? = nil,
                customKeys: [String] = [], editProblem: PatchSaveError? = nil, written: ConfigNode? = nil,
                conversion: ScribeConversion? = nil) {
        self.conversion = conversion
        self.squirrel = squirrel
        self.scribe = scribe
        self.schemaStyle = schemaStyle
        self.customText = customText
        self.customKeys = customKeys
        self.editProblem = editProblem
        themes = availableThemes(scribe: scribe, squirrel: squirrel)
        diagnostics = ConfigDiagnostics.check(scribe: written ?? scribe, squirrel: squirrel)
    }

    /// Reads everything from a deploy of a temporary copy of the user
    /// directory, so it is right even before Scribe has deployed it.
    @MainActor
    public static func load(userDirectory: URL, sharedDirectory: URL, schemaID: String?,
                            engine: LibrimeEngine = .shared) throws(PatchSaveError) -> AppearanceSettings {
        let custom = CustomFile(userDirectory: userDirectory, configID: "scribe")
        let deploy = TemporaryDeploy(engine: engine, userDirectory: userDirectory, sharedDirectory: sharedDirectory)
        let deployed = try deploy.run(["squirrel", "scribe"], schemaID: schemaID) { engine throws(PatchSaveError) in
            guard let squirrel = engine.withConfig(.deployed("squirrel"), { ConfigNode(snapshotOf: $0) }),
                  let scribe = engine.withConfig(.deployed("scribe"), { ConfigNode(snapshotOf: $0) })
            else { throw .deployFailed("librime 打不开部署后的 squirrel.yaml 或 scribe.yaml") }
            // Converted against Scribe's own squirrel.yaml, keeping what the
            // deployed scribe.yaml already sets.
            let baseline = FileManager.default.contents(atPath: sharedDirectory.appending(path: "squirrel.yaml").path(percentEncoded: false))
                .flatMap(CustomPatchWriter.utf8Text)
            let conversion = baseline.flatMap { ScribeConversion.load(from: engine, baselineYAML: $0) }
            var style: ConfigNode?
            if let schemaID, !schemaID.isEmpty, !schemaID.hasPrefix(".") {
                style = engine.withConfig(.schema(schemaID)) { schema in
                    schema.mapKeys(at: "style") == nil ? nil : ConfigNode(snapshotOf: schema, at: "style")
                } ?? nil
            }
            return (squirrel, scribe, style, conversion)
        }
        // librime drops null values when it applies a patch, so an unquoted
        // "#RRGGBB" (a YAML comment) leaves no trace in the deployed config.
        // The diagnostics see the entries as written.
        let written = writtenEntries(of: custom.text ?? "", engine: engine).reduce(deployed.1) { config, entry in
            config.setting(entry.key, to: entry.value)
        }
        return AppearanceSettings(squirrel: deployed.0, scribe: deployed.1, schemaStyle: deployed.2, customText: custom.text,
                                  customKeys: custom.keys, editProblem: custom.problem, written: written,
                                  conversion: deployed.3)
    }

    /// The patch entries of a custom file with plain map paths, each value
    /// parsed from its own lines: librime paths cannot address a patch key
    /// that contains "/".
    @MainActor
    static func writtenEntries(of text: String, engine: LibrimeEngine) -> [(key: String, value: ConfigNode)] {
        guard let document = try? PatchDocument(parsing: text) else { return [] }
        return document.entries.compactMap { entry in
            guard !entry.key.hasPrefix("__"), !entry.key.contains("@"),
                  !entry.key.hasSuffix("/+"), !entry.key.hasSuffix("/=")
            else { return nil }
            let keyLine = document.lines[entry.start].content
            var lines = ["v" + keyLine.dropFirst(entry.indent + entry.rawKey.count)]
            if entry.end > entry.start {
                lines += document.lines[(entry.start + 1)...entry.end].map(\.content)
            }
            return engine.withConfig(.yaml(lines.joined(separator: "\n") + "\n")) { reader in
                (entry.key, ConfigNode(snapshotOf: reader, at: "v"))
            }
        }
    }

    /// scribe.yaml with pending edits applied at their Scribe paths; a nil
    /// value removes. scribe.yaml itself sets no `appearance` value, so a
    /// removed entry falls back to Squirrel's.
    public func scribe(with pending: [String: ConfigNode?]) -> ConfigNode {
        pending.keys.sorted().reduce(scribe) { config, path in
            if let value = pending[path] ?? nil {
                config.setting(path, to: value)
            } else {
                config.removing(path)
            }
        }
    }

    /// The themes with pending edits applied at Scribe paths (nil value = remove), schema style on top.
    public func appearance(with pending: [String: ConfigNode?] = [:]) -> Appearance {
        let edited = scribe(with: pending)
        guard let schemaStyle else { return Appearance(squirrel: squirrel, scribe: edited) }
        return Appearance(squirrel: squirrel, scribe: edited, schema: ConfigNode.map(["style": schemaStyle]))
    }

    public func provenance(of scribePath: String) -> KeyProvenance {
        if customKeys.contains(where: { $0.utf8.elementsEqual(scribePath.utf8) }) {
            return .ownEntry
        }
        if let ancestor = customKeys.first(where: { scribePath.utf8.starts(with: ($0 + "/").utf8) }) {
            return .insideEntry(ancestor)
        }
        return .squirrelOrDefault
    }

    /// Whether the active schema's `style` sets the key, which wins over
    /// scribe.yaml in that schema.
    public func isOverriddenBySchema(_ scribePath: String) -> Bool {
        guard let schemaStyle,
              let squirrelPath = ScribeKeyMap.squirrelPath(forScribe: scribePath), squirrelPath.hasPrefix("style/")
        else { return false }
        return schemaStyle.node(at: String(squirrelPath.dropFirst("style/".count))) != nil
    }

    /// The colour schemes of the current light and dark themes that set the
    /// key themselves, such as "wechat" and "wechat:dark". A theme's own
    /// value wins over `appearance`, so editing it shows only in other themes.
    public func themesSetting(_ scribePath: String, with pending: [String: ConfigNode?] = [:]) -> [String] {
        guard scribePath.hasPrefix("appearance/"),
              let presetPath = ScribeKeyMap.squirrelPath(forScribe: "themes/x/style/\(scribePath.dropFirst("appearance/".count))"),
              presetPath.hasPrefix("preset_color_schemes/x/")
        else { return [] }
        let key = presetPath.dropFirst("preset_color_schemes/x/".count)
        let appearance = appearance(with: pending)
        let merged = MergedConfigSource(squirrel: squirrel, scribe: scribe(with: pending))
        var ids: [String] = []
        for theme in [appearance.light, appearance.dark].compactMap(\.self) where !theme.isNative {
            guard let id = theme.colorSchemeID, !ids.contains(id) else { continue }
            let path = "preset_color_schemes/\(id)/\(key)"
            if merged.string(at: path) != nil || merged.mapKeys(at: path) != nil {
                ids.append(id)
            }
        }
        return ids
    }

    /// The value at a Scribe path before any edit: scribe.yaml's, or else
    /// Squirrel's at the path it stands for.
    public func loadedValue(at scribePath: String) -> ConfigNode? {
        effectiveValue(at: scribePath, with: [:])
    }

    /// As `loadedValue(at:)`, with pending edits applied.
    public func effectiveValue(at scribePath: String, with pending: [String: ConfigNode?]) -> ConfigNode? {
        if let value = scribe(with: pending).node(at: scribePath) {
            return value
        }
        return ScribeKeyMap.squirrelPath(forScribe: scribePath).flatMap { squirrel.node(at: $0) }
    }
}

/// Edits to scribe.custom.yaml waiting to be saved, by Scribe path.
public struct AppearanceEdits: Equatable, Sendable, Codable {
    private enum Edit: Equatable, Sendable, Codable {
        case set(ConfigNode)
        case remove
    }

    private var edits: [String: Edit] = [:]

    public init() {}

    public var isEmpty: Bool { edits.isEmpty }

    /// For `AppearanceSettings.appearance(with:)`: nil removes the entry.
    public var pending: [String: ConfigNode?] {
        edits.mapValues { if case .set(let value) = $0 { value } else { nil } }
    }

    /// Stages a value; setting a path back to what was loaded drops its edit.
    public mutating func set(_ path: String, to value: ConfigNode, loaded settings: AppearanceSettings) {
        if value.sameValue(as: settings.loadedValue(at: path)) {
            edits.removeValue(forKey: path)
        } else {
            edits[path] = .set(value)
        }
    }

    /// 恢复默认: stages removing the path's own entry, or drops a pending value.
    public mutating func reset(_ path: String, loaded settings: AppearanceSettings) {
        if settings.provenance(of: path) == .ownEntry {
            edits[path] = .remove
        } else {
            edits.removeValue(forKey: path)
        }
    }

    public mutating func discard() {
        edits = [:]
    }

    /// One change per path, in path order.
    public var changes: [PatchChange] {
        var result: [PatchChange] = []
        for path in edits.keys.sorted() {
            // Creating a personal theme then editing one of its fields must
            // validate the final whole theme, not the superseded original.
            if let index = result.firstIndex(where: {
                if case .set(let parent, _) = $0 { return path.hasPrefix(parent + "/") }
                return false
            }), case .set(let parent, let node) = result[index] {
                let child = String(path.dropFirst(parent.count + 1))
                switch edits[path] {
                case .set(let value): result[index] = .set(parent, node.setting(child, to: value))
                case .remove, nil: result[index] = .set(parent, node.removing(child))
                }
                continue
            }
            switch edits[path] {
            case .set(let value): result.append(.set(path, value))
            case .remove, nil: result.append(.remove(path))
            }
        }
        return result
    }

    /// A number written minimally: "16", "0.85".
    public static func number(_ value: Double) -> ConfigNode {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return .scalar(String(Int(value)))
        }
        return .scalar("\(value)")
    }

    public static func flag(_ value: Bool) -> ConfigNode {
        .scalar(value ? "true" : "false")
    }
}
