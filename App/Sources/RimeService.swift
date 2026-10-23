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

    /// The distribution librime reports to schemas and plugins, as the last
    /// deploy's scribe.yaml chose it.
    var identity = DistributionIdentity.stored(in: .standard)

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
        modeStatusItem.isScribeCurrent = InputSourceInstaller(system: CarbonInputSources()).isScribeCurrent
        if LaunchGuard.standard.isRelaunchTooSoon() {
            Log.app.fault("Relaunched within two seconds; starting without Rime")
            Self.speak(Bundle.main.localizedString(forKey: LaunchGuard.warningKey, value: nil, table: nil))
            return
        }
        engine.notificationHandler = { notification in
            Self.log(notification)
            switch notification.type {
            case "deploy":
                DeployMessage(event: notification.value)?.post()
                RimeService.shared.resumeMaintenance()
                if notification.value != "start" {
                    RimeService.shared.updateIdentity()
                    // Schemas, and their styles, are deployed now.
                    RimeService.shared.loadAppearance()
                }
            case "option", "schema", "property":
                RimeService.shared.announce(notification)
            default:
                break
            }
        }
        engine.start(Self.configuration(identity: identity))
        startMaintenance(fullCheck: false)
    }

    /// Starts maintenance, deploying the frontend's config files on the way,
    /// and reads them again.
    func startMaintenance(fullCheck: Bool) {
        let started = FrontendConfig.startMaintenance(engine, fullCheck: fullCheck)
        settings = ScribeSettings.load(from: engine)
        modeStatusItem.isEnabled = settings?.showsStatusIcon ?? true
        if !started {
            loadAppearance()
        }
    }

    /// From the deployed squirrel.yaml.
    private var settings: ScribeSettings?
    /// The schema whose style the candidate window follows: the one a
    /// session started using last.
    private var schemaID = ""
    /// What sessions take from the settings and the schema's style.
    private var configuration = SessionConfiguration()

    /// Reads the current schema's style and hands the result to the
    /// candidate window and every session. While librime deploys, schemas
    /// are being rewritten; the deploy's end brings us back.
    func loadAppearance() {
        guard let settings, !engine.isInMaintenance,
              let appearance = Appearance.load(from: engine, schemaID: schemaID)
        else { return }
        candidatePanel.appearance = appearance
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        configuration = SessionConfiguration(settings: settings, theme: appearance.theme(isDark: isDark))
        adapters.removeAll { $0.adapter == nil }
        for adapter in adapters.compactMap(\.adapter) {
            adapter.configuration = configuration
        }
    }

    /// Applies scribe.yaml's `compatibility/report_as_squirrel` after a
    /// deploy. librime takes the names when it starts, so a change is kept
    /// for the next launch and librime starts again now; clients start new
    /// sessions on their next keys.
    private func updateIdentity() {
        guard let compatibility = ScribeCompatibility.load(from: engine) else { return }
        let identity = DistributionIdentity(compatibility)
        guard identity != self.identity else { return }
        Log.app.notice("Restarting librime as \(identity.codeName, privacy: .public)")
        identity.store(in: .standard)
        self.identity = identity
        engine.stop()
        engine.start(Self.configuration(identity: identity))
        startMaintenance(fullCheck: false)
    }

    private func schemaChanged(to schemaID: String) {
        guard schemaID != self.schemaID else { return }
        self.schemaID = schemaID
        loadAppearance()
    }

    private func observeServerNotifications() {
        // Closes librime cleanly, so user dictionaries are written out, when
        // the Mac logs out or shuts down and when Scribe quits, as Squirrel
        // does before logging out.
        let finalize: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated {
                RimeService.shared.finalize()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main, using: finalize)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main, using: finalize)

        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: CarbonInputSources.selectionChanged, object: nil, queue: .main) { _ in
            // Once the switch has settled, as Squirrel does.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    RimeService.shared.inputSourceChanged()
                }
            }
        }
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

    /// macOS 26 does not deactivate Scribe when another process switches the
    /// input source, as tools such as macism do (rime/squirrel#1140). Commit
    /// what was typed then, as deactivating would.
    private func inputSourceChanged() {
        let isScribeCurrent = InputSourceInstaller(system: CarbonInputSources()).isScribeCurrent
        modeStatusItem.isScribeCurrent = isScribeCurrent
        guard !isScribeCurrent else { return }
        activeAdapter?.finishComposition()
    }

    func activated(_ adapter: InputAdapter) {
        activeAdapter = adapter
        modeStatusItem.isScribeCurrent = true
        if let indicator = adapter.modeIndicator {
            modeStatusItem.title = indicator
        }
    }

    let modeStatusItem = ModeStatusItem()

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

    private func finalize() {
        Log.app.notice("Finalizing librime")
        candidatePanel.hide()
        engine.stop()
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
        adapter.configuration = configuration
        adapter.onSchemaChange = { RimeService.shared.schemaChanged(to: $0) }
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
            adapter.handle(notification)
            if notification.type == "option", notification.value.hasSuffix("ascii_mode"),
               adapter.owns(notification), let indicator = adapter.modeIndicator {
                modeStatusItem.title = indicator
            }
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
