import AppKit
import SwiftUI

@main
struct ScribeSettingsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = ImportModel()

    var body: some Scene {
        Window("中书设置", id: "settings") {
            SettingsView(model: model)
                .task { model.importOnLaunchIfRequested() }
        }
        .windowResizability(.contentMinSize)
    }
}

/// Quits with the window: the app has nothing else to show.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
