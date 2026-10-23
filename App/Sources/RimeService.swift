import AppKit
import RimeKit
import ScribeConfig
import ScribeCore
import ScribeUI

extension CandidatePanel: CandidatePresenting {}

extension RimeService: MaintenanceEngine {
    var isInMaintenance: Bool {
        engine.isInMaintenance
    }

    /// Restarts librime and deploys everything again. Open sessions are
    /// dropped; each client starts a new one on its next key.
    func reload() {
        Log.app.notice("Redeploying")
        engine.stop()
        engine.start(Self.configuration())
        engine.startMaintenance(fullCheck: true)
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

    let engine = LibrimeEngine.shared
    let candidatePanel = CandidatePanel()

    private lazy var maintenance = MaintenanceQueue(engine: self)
    /// Checks for finished maintenance while tasks wait in the queue.
    private var maintenanceTimer: Timer?

    private init() {}

    /// Starts librime and deploys if the user's files changed.
    func start() {
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
        engine.start(Self.configuration())
        engine.startMaintenance(fullCheck: false)
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
    static func configuration(bundle: Bundle = .main, userDirectory: URL? = nil, logDirectory: URL? = defaultLogDirectory) -> RimeConfiguration {
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
            distributionName: "Scribe",
            distributionCodeName: "Scribe",
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
