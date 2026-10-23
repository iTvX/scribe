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

        switch Command(arguments: CommandLine.arguments) {
        case .install:
            exit(InputSourceInstaller.register(bundleURL: bundle.bundleURL, bundleIdentifier: bundleIdentifier) ? 0 : 1)
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
        // OpenCC resolves its dictionaries relative to the working directory.
        FileManager.default.changeCurrentDirectoryPath(RimeService.sharedDataDirectory(bundle: bundle).path(percentEncoded: false))
        RimeService.shared.start()
        Log.app.notice("Input method server listening on \(connectionName, privacy: .public)")
        withExtendedLifetime(server) {
            app.run()
        }
        exit(0)
    }

    /// Delivered at once, even though Scribe runs in the background.
    private static func post(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
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
