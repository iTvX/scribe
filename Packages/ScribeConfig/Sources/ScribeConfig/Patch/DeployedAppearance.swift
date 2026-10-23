import Foundation
import RimeKit

/// The themes Scribe shows for a schema, with the names of their colour schemes.
public struct DeployedAppearance: Equatable, Sendable {
    public var appearance: Appearance
    /// `preset_color_schemes/<id>/name` for the themes' colour schemes.
    public var colorSchemeNames: [String: String]
}

extension Appearance {
    /// The themes Scribe shows for a schema, from the deployed squirrel.yaml
    /// and schema in `<userDirectory>/build`. librime reads copies in a
    /// temporary directory, so it never opens the real one. Nil when
    /// squirrel.yaml has not been deployed yet.
    @MainActor
    public static func loadDeployed(userDirectory: URL, sharedDirectory: URL, schemaID: String,
                                    engine: LibrimeEngine = .shared) throws(PatchSaveError) -> DeployedAppearance? {
        guard !engine.isRunning else { throw .engineBusy }
        let fileManager = FileManager.default
        let build = userDirectory.appending(path: "build", directoryHint: .isDirectory)
        guard let squirrel = fileManager.contents(atPath: build.appending(path: "squirrel.yaml").path(percentEncoded: false))
        else { return nil }
        let temporary = fileManager.temporaryDirectory
            .appending(path: "scribe-appearance-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: temporary) }
        do {
            let temporaryBuild = temporary.appending(path: "build", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: temporaryBuild, withIntermediateDirectories: true)
            try squirrel.write(to: temporaryBuild.appending(path: "squirrel.yaml"))
            let schemaFile = "\(schemaID).schema.yaml"
            if !schemaID.isEmpty, !schemaID.contains("/"),
               let schema = fileManager.contents(atPath: build.appending(path: schemaFile).path(percentEncoded: false)) {
                try schema.write(to: temporaryBuild.appending(path: schemaFile))
            }
        } catch {
            throw .deployFailed(error.localizedDescription)
        }
        engine.start(RimeConfiguration(sharedDataDirectory: sharedDirectory, userDataDirectory: temporary, minimumLogLevel: 2))
        defer { engine.stop() }
        guard let appearance = load(from: engine, schemaID: schemaID) else { return nil }
        let ids = [appearance.light.colorSchemeID, appearance.dark?.colorSchemeID].compactMap(\.self)
        let names = engine.withConfig(.deployed("squirrel")) { squirrel in
            ids.reduce(into: [String: String]()) { names, id in
                names[id] = PresetColorScheme(id: id, source: squirrel)?.name
            }
        } ?? [:]
        return DeployedAppearance(appearance: appearance, colorSchemeNames: names)
    }
}
