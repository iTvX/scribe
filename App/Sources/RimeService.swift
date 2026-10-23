import AppKit
import RimeKit
import ScribeConfig
import ScribeCore
import ScribeUI

extension CandidatePanel: CandidatePresenting {}

/// How Scribe names itself to librime. Schemas and Lua scripts may check the
/// code name; a compatibility setting will let users report "Squirrel".
struct DistributionIdentity: Equatable {
    var name: String
    var codeName: String

    static let scribe = DistributionIdentity(name: "Scribe", codeName: "Scribe")
}

extension RimeService: MaintenanceEngine {
    var isInMaintenance: Bool {
        engine.isInMaintenance
    }

    /// Restarts librime and deploys everything again. Open sessions are
    /// dropped; each client starts a new one on its next key.
    func reload() {
        Log.app.notice("Redeploying")
        engine.stop()
        engine.start(Self.configuration(identity: identity))
        startMaintenance(fullCheck: true)
    }

    /// librime closes all sessions before syncing; each client starts a new
    /// one on its next key.
    func startSync() -> Bool {
        Log.app.notice("Syncing user data")
        return engine.syncUserData()
    }
}

/// The process's Rime engine and candidate window, shared by every client.
@MainActor
final class RimeService {
    static let shared = RimeService()

    static let reloadNotification = Notification.Name(ServerNotification.reload)
    static let syncNotification = Notification.Name(ServerNotification.sync)
    static let setASCIIModeNotification = Notification.Name(ServerNotification.setASCIIMode)
    static let getASCIIModeNotification = Notification.Name(ServerNotification.getASCIIMode)
    static let asciiModeResponseNotification = Notification.Name(ServerNotification.asciiModeResponse)

    let engine = LibrimeEngine.shared
    let candidatePanel = CandidatePanel()

    private lazy var maintenance = MaintenanceQueue(engine: self)
    /// Checks for finished maintenance while tasks wait in the queue.
    private var maintenanceTimer: Timer?

    private init() {}

    /// The distribution librime reports to schemas and plugins.
    var identity = DistributionIdentity.scribe

    /// Starts librime and deploys if the user's files changed. After a crash
    /// at startup it starts without librime, so the user can still type and
    /// fix the configuration; a reload starts librime again.
    func start() {
        if let logDirectory = Self.defaultLogDirectory {
            try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            // Plugins such as librime-lua log here too.
            setenv("RIME_LOG_DIR", logDirectory.path(percentEncoded: false), 1)
        }
        observeServerNotifications()
        if LaunchGuard.standard.isRelaunchTooSoon() {
            Log.app.fault("Relaunched within two seconds; starting without Rime")
            Self.speak(Bundle.main.localizedString(forKey: LaunchGuard.warningKey, value: nil, table: nil))
            return
        }
        engine.notificationHandler = { notification in
            Self.log(notification)
            switch notification.type {
            case "deploy":
                RimeService.shared.resumeMaintenance()
            case "option", "schema":
                RimeService.shared.announce(notification)
            default:
                break
            }
        }
        engine.start(Self.configuration(identity: identity))
        startMaintenance(fullCheck: false)
    }

    /// Squirrel's and Scribe's own config files. They are not part of the
    /// workspace librime deploys, so the frontend deploys them itself.
    static let frontendConfigFiles = ["squirrel.yaml", "scribe.yaml"]

    /// Starts maintenance and, as Squirrel does, deploys the frontend's
    /// config files with the user's patches while it runs. Settings apps
    /// change scribe.custom.yaml and ask only for a reload, so every deploy
    /// goes through here.
    func startMaintenance(fullCheck: Bool) {
        guard engine.startMaintenance(fullCheck: fullCheck) else { return }
        for file in Self.frontendConfigFiles {
            _ = engine.deployConfigFile(file, versionKey: "config_version")
        }
    }

    private func observeServerNotifications() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Self.reloadNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                RimeService.shared.request(.reload)
            }
        }
        center.addObserver(forName: Self.syncNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                RimeService.shared.request(.sync)
            }
        }
        center.addObserver(forName: Self.setASCIIModeNotification, object: nil, queue: .main) { notification in
            guard let mode = notification.object as? String, ["ascii", "nascii"].contains(mode) else { return }
            MainActor.assumeIsolated {
                RimeService.shared.setASCIIMode(mode == "ascii")
            }
        }
        center.addObserver(forName: Self.getASCIIModeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                RimeService.shared.reportASCIIMode()
            }
        }
    }

    /// The adapter of the client that was activated last.
    private weak var activeAdapter: InputAdapter?

    func activated(_ adapter: InputAdapter) {
        activeAdapter = adapter
    }

    /// Sets ASCII mode in every client's session, as Squirrel does.
    private func setASCIIMode(_ on: Bool) {
        adapters.removeAll { $0.adapter == nil }
        for adapter in adapters.compactMap(\.adapter) {
            adapter.setASCIIMode(on)
        }
    }

    private func reportASCIIMode() {
        guard let isASCIIMode = activeAdapter?.isASCIIMode else { return }
        DistributedNotificationCenter.default().postNotificationName(
            Self.asciiModeResponseNotification,
            object: isASCIIMode ? "ascii" : "nascii",
            userInfo: nil,
            deliverImmediately: true
        )
    }

    enum Place {
        case logs
        case userFolder
        case help
    }

    /// Opens a folder in the Finder, or the help in the browser.
    func open(_ place: Place) {
        let url: URL? = switch place {
        case .logs: Self.defaultLogDirectory
        case .userFolder: Self.configuration(logDirectory: nil, identity: identity).userDataDirectory
        case .help: URL(string: "https://github.com/iTvX/scribe#readme")
        }
        if let url {
            if url.isFileURL {
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            NSWorkspace.shared.open(url)
        }
    }

    private static func speak(_ message: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/say")
        process.arguments = [message]
        try? process.run()
    }

    /// Queues a reload or a sync; it starts once librime is not busy.
    func request(_ task: MaintenanceQueue.Task) {
        Log.app.notice("Requested \(task == .reload ? "reload" : "sync", privacy: .public)")
        maintenance.enqueue(task)
        resumeMaintenance()
    }

    private func resumeMaintenance() {
        maintenance.resume()
        if maintenance.pending.isEmpty {
            maintenanceTimer?.invalidate()
            maintenanceTimer = nil
        } else if maintenanceTimer == nil {
            maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                MainActor.assumeIsolated {
                    RimeService.shared.resumeMaintenance()
                }
            }
        }
    }

    func makeAdapter() -> InputAdapter {
        let adapter = InputAdapter(session: InputSession(engine: engine, chordTimer: RunLoopChordTimer()), candidates: candidatePanel)
        adapters.append(WeakAdapter(adapter: adapter))
        return adapter
    }

    private struct WeakAdapter {
        weak var adapter: InputAdapter?
    }

    /// Every client's adapter, for routing notifications to their sessions.
    private var adapters: [WeakAdapter] = []

    /// Shows option and schema changes to the client whose session they
    /// concern.
    private func announce(_ notification: RimeNotification) {
        adapters.removeAll { $0.adapter == nil }
        for adapter in adapters.compactMap(\.adapter) {
            adapter.handle(notification, notifications: .appropriate, messageType: .mix)
        }
    }

    /// Shared data from the app bundle, user data in ~/Library/Scribe, logs
    /// in ~/Library/Logs/Scribe.
    static func configuration(
        bundle: Bundle = .main,
        userDirectory: URL? = nil,
        logDirectory: URL? = defaultLogDirectory,
        identity: DistributionIdentity = .scribe
    ) -> RimeConfiguration {
        let fileManager = FileManager.default
        let userDirectory = userDirectory ?? UserDirectories(home: fileManager.homeDirectoryForCurrentUser).scribe
        for directory in [userDirectory, logDirectory].compactMap(\.self) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return RimeConfiguration(
            sharedDataDirectory: sharedDataDirectory(bundle: bundle),
            userDataDirectory: userDirectory,
            logDirectory: logDirectory,
            minimumLogLevel: logDirectory == nil ? 2 : 0,
            appName: "rime.scribe",
            distributionName: identity.name,
            distributionCodeName: identity.codeName,
            distributionVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        )
    }

    static func sharedDataDirectory(bundle: Bundle = .main) -> URL {
        bundle.sharedSupportURL ?? bundle.bundleURL.appending(path: "Contents/SharedSupport", directoryHint: .isDirectory)
    }

    static let defaultLogDirectory: URL? = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/Scribe", directoryHint: .isDirectory)

    private static func log(_ notification: RimeNotification) {
        switch (notification.type, notification.value) {
        case ("deploy", "start"):
            Log.app.notice("Deploy started")
        case ("deploy", "success"):
            Log.app.notice("Deploy succeeded")
        case ("deploy", "failure"):
            Log.app.error("Deploy failed")
        case ("schema", let schema):
            Log.app.notice("Schema \(schema, privacy: .public)")
        default:
            Log.app.info("Rime \(notification.type, privacy: .public): \(notification.value, privacy: .public)")
        }
    }
}
