import AppKit
import InputMethodKit
import RimeKit

@main
enum ScribeApp {
    @MainActor
    static func main() {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        Log.app.notice("Scribe \(version, privacy: .public) with librime \(Librime.version ?? "unknown", privacy: .public)")

        guard let bundleIdentifier = bundle.bundleIdentifier else {
            print("Scribe must run from its app bundle")
            exit(1)
        }

        let installer = InputSourceInstaller(system: CarbonInputSources())
        switch Command(arguments: CommandLine.arguments) {
        case .install:
            exit(installer.register(bundleURL: bundle.bundleURL) ? 0 : 1)
        case .enableInputSource(let modes):
            installer.enable(modes)
            exit(0)
        case .disableInputSource(let modes):
            installer.disable(modes)
            exit(0)
        case .selectInputSource(let mode):
            installer.select(mode)
            exit(0)
        case .build:
            let directory = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
            exit(LibrimeEngine.shared.buildWorkspace(in: directory) ? 0 : 1)
        case .ascii(let on):
            post(RimeService.setASCIIModeNotification, object: on ? "ascii" : "nascii")
            exit(0)
        case .getASCII:
            print(askASCIIMode() ?? "nascii")
            exit(0)
        case .quit:
            quitRunningInstances(bundleIdentifier: bundleIdentifier)
            exit(0)
        case .reload:
            post(RimeService.reloadNotification)
            exit(0)
        case .sync:
            post(RimeService.syncNotification)
            exit(0)
        case .selfTest:
            exit(SelfTest.run() ? 0 : 1)
        case .replay(let file):
            exit(ReplayCommand.run(file: file) ? 0 : 1)
        case .help:
            print(Command.usage)
            exit(0)
        case .invalid(let arguments):
            FileHandle.standardError.write(Data("Unknown option: \(arguments)\n\n\(Command.usage)\n".utf8))
            exit(2)
        case .runServer:
            runServer(bundle: bundle, bundleIdentifier: bundleIdentifier)
        }
    }

    @MainActor
    private static func runServer(bundle: Bundle, bundleIdentifier: String) -> Never {
        guard let connectionName = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String,
              let server = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier)
        else {
            Log.app.fault("Could not start the input method server")
            exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        RimeService.useSharedDataAsWorkingDirectory(bundle: bundle)
        RimeService.shared.start()
        SoftwareUpdater.shared.start()
        Log.app.notice("Input method server listening on \(connectionName, privacy: .public)")
        withExtendedLifetime(server) {
            app.run()
        }
        exit(0)
    }

    /// Delivered at once, even though Scribe runs in the background.
    private static func post(_ name: Notification.Name, object: String? = nil) {
        DistributedNotificationCenter.default().postNotificationName(name, object: object, userInfo: nil, deliverImmediately: true)
    }

    /// Asks the running Scribe for the active client's ASCII mode and waits up
    /// to two seconds for "ascii" or "nascii".
    @MainActor
    private static func askASCIIMode() -> String? {
        nonisolated(unsafe) var answer: String?
        let center = DistributedNotificationCenter.default()
        let observer = center.addObserver(forName: RimeService.asciiModeResponseNotification, object: nil, queue: .main) { notification in
            answer = notification.object as? String
        }
        defer { center.removeObserver(observer) }
        post(RimeService.getASCIIModeNotification)
        let deadline = Date(timeIntervalSinceNow: 2)
        while answer == nil, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        return answer
    }

    @MainActor
    private static func quitRunningInstances(bundleIdentifier: String) {
        let current = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        where app.processIdentifier != current {
            app.terminate()
        }
    }
}
