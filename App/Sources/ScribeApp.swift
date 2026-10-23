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
        case .help:
            print(Command.usage)
            exit(0)
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
        Log.app.notice("Input method server listening on \(connectionName, privacy: .public)")
        withExtendedLifetime(server) {
            app.run()
        }
        exit(0)
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
