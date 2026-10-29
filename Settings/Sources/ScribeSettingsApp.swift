import AppKit
import RimeKit
import SwiftUI

@main
struct ScribeSettingsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var importModel: ImportModel
    @State private var defaults: DefaultsModel
    @State private var looks: LooksModel
    @State private var session: SettingsSession
    private let updates: SettingsUpdateCoordinator

    init() {
        if CommandLine.arguments.contains("--self-test") {
            Self.selfTest()
        }
        if CommandLine.arguments.contains("--installation-finished") { SettingsInstallationBridge.run() }
        let directories = SettingsDirectories()
        #if DEBUG
            // UI checks may force this test application's appearance, never the
            // system's or a live settings session's appearance.
            if !directories.isLive, let appearance = UserDefaults.standard.string(forKey: "ScribeTestAppearance") {
                NSApplication.shared.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            }
        #endif
        let importer = ImportModel(directories: directories)
        let defaults = DefaultsModel(directories: directories)
        let looks = LooksModel(directories: directories)
        let session = SettingsSession()
        session.isFrozen = Self.argument("--settings-handoff") != nil
        if let legacy = Self.argument("--legacy-settings") {
            session.legacyPIDs = legacy.split(separator: ",").compactMap { Int32($0) }
            session.updateMessage = "新版设置已打开。旧窗口已保留，以免丢失其中未保存的修改。"
        }
        let runtime = NativeSettingsUpdateRuntime(directories: directories)
        updates = SettingsUpdateCoordinator(runtime: runtime, store: runtime.store, session: session,
                                            defaults: defaults, looks: looks, importer: importer)
        _importModel = State(initialValue: importer)
        _defaults = State(initialValue: defaults)
        _looks = State(initialValue: looks)
        _session = State(initialValue: session)
    }

    var body: some Scene {
        Window("中书设置", id: "settings") {
            SettingsView(importModel: importModel, defaults: defaults, looks: looks, session: session, updates: updates)
                .task { launch() }
        }
        .defaultSize(width: 1020, height: 760)
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

    private static func argument(_ name: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }

    private func launch() {
        guard delegate.updates == nil else { return }
        delegate.updates = updates
        let refresh = { [defaults, looks] in
            defaults.load()
            looks.load(
                activeSchema: defaults.activeSchema,
                schemaName: defaults.activeSchema.map { defaults.name(ofSchema: $0) })
        }
        importModel.onImported = refresh
        refresh()
        let restored = updates.start(token: Self.argument("--settings-handoff").flatMap(UUID.init(uuidString:)))
        guard !restored else { return }
        // -ScribeConvertOnLaunch YES, for smoke tests in an overridden user directory.
        if UserDefaults.standard.bool(forKey: "ScribeConvertOnLaunch") {
            looks.convertOnLaunch()
        }
        importModel.launch()
    }
}

/// Quits with the window: the app has nothing else to show.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var updates: SettingsUpdateCoordinator?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        updates?.prepareToQuit() == false ? .terminateCancel : .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
