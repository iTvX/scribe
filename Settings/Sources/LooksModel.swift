import Foundation
import Observation
import ScribeConfig

/// 外观: the themes Scribe draws its candidate panel with, read-only for now.
@MainActor @Observable
final class LooksModel {
    enum Phase {
        case loading
        case loaded(DeployedAppearance)
        case unavailable(String)
    }

    let directories: SettingsDirectories
    private(set) var phase = Phase.loading
    private(set) var schemaID: String?

    init(directories: SettingsDirectories) {
        self.directories = directories
    }

    func load(activeSchema: String?) {
        schemaID = activeSchema
        guard let shared = directories.shared else {
            phase = .unavailable("找不到中书，没法读取外观")
            return
        }
        do {
            if let deployed = try Appearance.loadDeployed(userDirectory: directories.user, sharedDirectory: shared,
                                                          schemaID: activeSchema ?? "") {
                phase = .loaded(deployed)
                let light = deployed.appearance.light.colorSchemeID ?? "native"
                let dark = deployed.appearance.dark?.colorSchemeID ?? "none"
                emit("Appearance loaded: light \(light), dark \(dark), schema \(activeSchema ?? "none")")
            } else {
                phase = .unavailable("中书还没有部署过这个目录，部署后才能看到外观")
                emit("Appearance unavailable: no build/squirrel.yaml")
            }
        } catch {
            phase = .unavailable(DefaultsModel.message(for: error))
            emit("Appearance failed: \(error)")
        }
    }

    private func emit(_ line: String) {
        Log.settings.notice("\(line, privacy: .public)")
        print(line)
        fflush(nil)
    }
}
