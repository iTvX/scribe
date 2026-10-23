import AppKit
import SwiftUI

@main
struct ScribeSettingsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var importModel: ImportModel
    @State private var defaults: DefaultsModel
    @State private var looks: LooksModel

    init() {
        let directories = SettingsDirectories()
        _importModel = State(initialValue: ImportModel(directories: directories))
        _defaults = State(initialValue: DefaultsModel(directories: directories))
        _looks = State(initialValue: LooksModel(directories: directories))
    }

    var body: some Scene {
        Window("中书设置", id: "settings") {
            SettingsView(importModel: importModel, defaults: defaults, looks: looks)
                .task { launch() }
        }
        .windowResizability(.contentMinSize)
    }

    private func launch() {
        let refresh = { [defaults, looks] in
            defaults.load()
            looks.load(activeSchema: defaults.activeSchema)
        }
        importModel.onImported = refresh
        refresh()
        importModel.launch()
    }
}

/// Quits with the window: the app has nothing else to show.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
