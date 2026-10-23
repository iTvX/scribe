import Foundation
import RimeKit

/// A schema a user can select, from its `*.schema.yaml`.
public struct SchemaInfo: Equatable, Sendable, Identifiable {
    public var id: String
    /// `schema/name`, or the ID when there is none.
    public var name: String
    public var authors: [String]
    public var description: String?
    /// Whether it comes from the user directory rather than the shared one.
    public var isInUserDirectory: Bool
}

/// What a selected schema sets itself, which wins over default.yaml.
public struct SchemaOverride: Equatable, Sendable {
    public var schemaID: String
    public var pageSize: Int?
    /// Nil when the schema leaves `ascii_composer/switch_key` to default.yaml.
    public var switchKey: [String: String]?
}

/// The schemas in the user and shared directories, found the way levers'
/// SwitcherSettings finds them. Parses text only, so librime need not run.
@MainActor
public enum SchemaCatalog {
    /// Every `*.schema.yaml` with a `schema/schema_id`, sorted by ID; on the
    /// same ID the user directory wins.
    public static func scan(userDirectory: URL, sharedDirectory: URL, engine: LibrimeEngine = .shared) -> [SchemaInfo] {
        var schemas: [String: SchemaInfo] = [:]
        for (directory, isUser) in [(sharedDirectory, false), (userDirectory, true)] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
            for name in names.sorted() where name.hasSuffix(".schema.yaml") {
                guard let text = text(of: directory.appending(path: name)),
                      let info = engine.withConfig(.yaml(text), { schema(from: $0, isInUserDirectory: isUser) }) ?? nil
                else { continue }
                schemas[info.id] = info
            }
        }
        return schemas.values.sorted { $0.id.utf8.lexicographicallyPrecedes($1.id.utf8) }
    }

    /// `var/previously_selected_schema` in the user directory's user.yaml.
    public static func activeSchema(userDirectory: URL, engine: LibrimeEngine = .shared) -> String? {
        guard let text = text(of: userDirectory.appending(path: "user.yaml")) else { return nil }
        return engine.withConfig(.yaml(text)) { $0.string(at: "var/previously_selected_schema") } ?? nil
    }

    /// The page size and switch keys that each schema's deployed file sets,
    /// for schemas that set either. Schemas never deployed are skipped.
    public static func overrides(for schemaIDs: [String], userDirectory: URL,
                                 engine: LibrimeEngine = .shared) -> [SchemaOverride] {
        schemaIDs.compactMap { id in
            let file = userDirectory.appending(path: "build/\(id).schema.yaml")
            guard let text = text(of: file) else { return nil }
            let override = engine.withConfig(.yaml(text)) { reader in
                SchemaOverride(
                    schemaID: id,
                    pageSize: reader.int(at: "menu/page_size"),
                    switchKey: reader.mapKeys(at: "ascii_composer/switch_key") == nil
                        ? nil
                        : ConfigNode(snapshotOf: reader, at: "ascii_composer/switch_key").scalarMap
                )
            }
            guard let override, override.pageSize != nil || override.switchKey != nil else { return nil }
            return override
        }
    }

    private static func schema(from reader: RimeConfigReader, isInUserDirectory: Bool) -> SchemaInfo? {
        guard let id = reader.string(at: "schema/schema_id"), !id.isEmpty else { return nil }
        let author = ConfigNode(snapshotOf: reader, at: "schema/author")
        let authors: [String] = switch author {
        case .scalar(let name): [name]
        default: author.scalars
        }
        return SchemaInfo(
            id: id,
            name: reader.string(at: "schema/name") ?? id,
            authors: authors,
            description: reader.string(at: "schema/description"),
            isInUserDirectory: isInUserDirectory
        )
    }

    private static func text(of file: URL) -> String? {
        FileManager.default.contents(atPath: file.path(percentEncoded: false)).map { String(decoding: $0, as: UTF8.self) }
    }
}
