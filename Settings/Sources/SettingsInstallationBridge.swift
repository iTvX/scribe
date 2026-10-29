import AppKit

/// A one-shot command launched after the install receipt is committed. Old
/// releases have no draft-export protocol: never terminate those processes.
@MainActor
enum SettingsInstallationBridge {
    static let completedNotification = "io.github.itvx.scribe.settingsInstallationFinished"
    static let installedPath = "/Library/Input Methods/Scribe.app/Contents/Helpers/ScribeSettings.app"

    struct Running {
        var process: SettingsProcess
        var build: String? // nil means legacy, without a matching protocol lease
    }

    static func legacyToOpen(_ running: [Running], currentBuild: String) -> [Int32] {
        // A cooperative instance owns its own handoff, even when a much older
        // legacy window is also still open. Never start a competing receiver.
        guard !running.contains(where: { $0.build != nil }) else { return [] }
        return running.filter { $0.build == nil }.map(\.process.pid)
    }

    static func run() -> Never {
        let directories = SettingsDirectories()
        let runtime = NativeSettingsUpdateRuntime(directories: directories)
        guard getuid() != 0, directories.isLive,
              runtime.identifier == SettingsDirectories.scribeBundleIdentifier + ".Settings",
              runtime.appURL.path == installedPath else {
            print("Settings installation refresh ignored: not the installed application")
            exit(0)
        }
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(completedNotification), object: runtime.identifier, userInfo: nil, deliverImmediately: true)
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: runtime.identifier)
            .filter { $0.processIdentifier != runtime.process.pid && $0.bundleURL?.standardizedFileURL == runtime.appURL }
        let processes = running.map { app -> Running in
            let process = NativeSettingsUpdateRuntime.identity(app)
            return Running(process: process, build: (try? runtime.store.lease(for: process))?.build)
        }
        let legacy = legacyToOpen(processes, currentBuild: runtime.loadedBuild)
        if !legacy.isEmpty, (try? runtime.store.claimLegacyLaunch(build: runtime.loadedBuild)) == true {
            let command = Process()
            command.executableURL = URL(filePath: "/usr/bin/open")
            command.arguments = ["-n", "-a", runtime.appURL.path, "--args", "--legacy-settings", legacy.map(String.init).joined(separator: ",")]
            do {
                try command.run()
                command.waitUntilExit()
                exit(command.terminationStatus)
            } catch { exit(1) }
        }
        // Cooperative instances detect replacement with their own timer, also
        // covering users who were not the console user during installation.
        exit(0)
    }
}
