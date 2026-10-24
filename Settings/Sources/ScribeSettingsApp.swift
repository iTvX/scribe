import AppKit
import RimeKit
import SwiftUI

@main
struct ScribeSettingsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var importModel: ImportModel
    @State private var defaults: DefaultsModel
    @State private var looks: LooksModel

    init() {
        if CommandLine.arguments.contains("--self-test") {
            Self.selfTest()
        }
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

    /// `ScribeSettings --self-test`: prints where librime and the shared data
    /// come from, without opening a window. Inside Scribe.app, librime is
    /// the outer bundle's.
    private static func selfTest() -> Never {
        guard let version = Librime.version else {
            print("librime: not loaded")
            exit(1)
        }
        print("librime \(version)")
        print("shared data: \(SettingsDirectories().shared?.path(percentEncoded: false) ?? "none")")
        exit(0)
    }

    private func launch() {
        let refresh = { [defaults, looks] in
            defaults.load()
            looks.load(activeSchema: defaults.activeSchema,
                       schemaName: defaults.activeSchema.map { defaults.name(ofSchema: $0) })
        }
        importModel.onImported = refresh
        refresh()
        // -ScribeConvertOnLaunch YES, for smoke tests in an overridden user directory.
        if UserDefaults.standard.bool(forKey: "ScribeConvertOnLaunch") {
            looks.convertOnLaunch()
        }
        importModel.launch()
    }
}

/// Quits with the window: the app has nothing else to show.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
