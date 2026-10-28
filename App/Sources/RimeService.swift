import AppKit
import RimeKit
import ScribeConfig
import ScribeCore
import ScribeUI

@MainActor
protocol FrontendPanel: CandidatePresenting {
    var appearance: Appearance { get set }
    func prepare()
}

extension CandidatePanel: FrontendPanel {}

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
    let candidatePanel: any FrontendPanel
    private let modeStatusItem: ModeStatusItem
    private let isDark: () -> Bool
    private var appearanceObservation: NSKeyValueObservation?
    private var lastIsDark: Bool?

    private lazy var maintenance = MaintenanceQueue(engine: self)
    /// Checks for finished maintenance while tasks wait in the queue.
    private var maintenanceTimer: Timer?

    init(candidatePanel: any FrontendPanel = CandidatePanel(),
         modeStatusItem: ModeStatusItem = ModeStatusItem(),
         isDark: @escaping () -> Bool = {
             NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
         }) {
        self.candidatePanel = candidatePanel
        self.modeStatusItem = modeStatusItem
        self.isDark = isDark
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            // AppKit can deliver KVO during drawing. Finish that transaction
            // before asking the client to replace its marked text.
            DispatchQueue.main.async { self?.systemAppearanceChanged() }
        }
    }

    /// The distribution librime reports to schemas and plugins, as the last
    /// deploy's scribe.yaml chose it.
    var identity = DistributionIdentity.stored(in: .standard)

    /// Starts librime and deploys if the user's files changed. After a crash
    /// at startup it starts without librime, so the user can still type and
    /// fix the configuration; a reload starts librime again.
    func start(launchGuard: LaunchGuard = .standard, logDirectory: URL? = defaultLogDirectory,
               warning: ((String) -> Void)? = nil, now: Date = Date()) {
        if let logDirectory {
            try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            // Plugins such as librime-lua log here too.
            setenv("RIME_LOG_DIR", logDirectory.path(percentEncoded: false), 1)
        }
        observeServerNotifications()
        modeStatusItem.isScribeCurrent = InputSourceInstaller(system: CarbonInputSources()).isScribeCurrent
        // Install routing even when the crash guard defers engine startup:
        // the user's later Redeploy must still receive completion and state.
        engine.notificationHandler = { [weak self] notification in
            guard let self else { return }
            Self.log(notification)
            switch notification.type {
            case "deploy":
                DeployMessage(event: notification.value)?.post()
                self.resumeMaintenance()
                if notification.value != "start" {
                    self.updateIdentity()
                    // Schemas, and their styles, are deployed now.
                    self.loadAppearance()
                }
            case "option", "schema", "property":
                self.announce(notification)
            default:
                break
            }
        }
        if launchGuard.isRelaunchTooSoon(now: now) {
            Log.app.fault("Relaunched within two seconds; starting without Rime")
            let message = Bundle.main.localizedString(forKey: LaunchGuard.warningKey, value: nil, table: nil)
            if let warning { warning(message) } else { Self.speak(message) }
            return
        }
        engine.start(Self.configuration(identity: identity))
        startMaintenance(fullCheck: false)
        candidatePanel.prepare()
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
    /// Parsed once per schema/deploy, never from disk for each typed key.
    private var appearances: [String: Appearance] = [:]
    private var configuration = SessionConfiguration()

    /// A deploy invalidates all cached themes. Each retained session keeps
    /// its own schema's configuration; only the focused one owns the window.
    func loadAppearance() {
        guard !engine.isInMaintenance else { return }
        settings = ScribeSettings.load(from: engine)
        appearances.removeAll()
        lastIsDark = isDark()
        if let settings, let appearance = appearance(for: "") {
            configuration = SessionConfiguration(settings: settings, theme: appearance.theme(isDark: isDark()))
            if activeAdapter == nil { candidatePanel.appearance = appearance }
        }
        adapters.removeAll { $0.adapter == nil }
        for adapter in adapters.compactMap(\.adapter) {
            configure(adapter, schemaID: adapter.currentSchemaID ?? "")
        }
        activeAdapter?.refreshPresentation()
    }

    private func appearance(for schemaID: String) -> Appearance? {
        if let appearance = appearances[schemaID] { return appearance }
        guard !engine.isInMaintenance, let appearance = Appearance.load(from: engine, schemaID: schemaID) else { return nil }
        appearances[schemaID] = appearance
        return appearance
    }

    private func configure(_ adapter: InputAdapter, schemaID: String) {
        guard let settings, let appearance = appearance(for: schemaID) else { return }
        adapter.configuration = SessionConfiguration(settings: settings, theme: appearance.theme(isDark: isDark()))
        if activeAdapter === adapter {
            candidatePanel.appearance = appearance
            updateModeIndicator(adapter)
        }
    }

    func systemAppearanceChanged() {
        let dark = isDark()
        guard dark != lastIsDark else { return }
        lastIsDark = dark
        guard let adapter = activeAdapter else { return }
        configure(adapter, schemaID: adapter.currentSchemaID ?? "")
        adapter.refreshPresentation()
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
        activeAdapter = nil
        candidatePanel.hide()
        candidatePanel.delegate = nil
    }

    func activated(_ adapter: InputAdapter) {
        if activeAdapter !== adapter {
            candidatePanel.hide()
            candidatePanel.delegate = nil
        }
        activeAdapter = adapter
        modeStatusItem.isScribeCurrent = true
        lastIsDark = isDark()
        configure(adapter, schemaID: adapter.currentSchemaID ?? "")
        updateModeIndicator(adapter)
    }

    private func deactivated(_ adapter: InputAdapter) {
        if activeAdapter === adapter { activeAdapter = nil }
    }

    private func prepareForInput(_ adapter: InputAdapter) {
        // IMK may reuse a controller for another input field without the
        // usual activation pair. The client delivering a key owns focus.
        if activeAdapter !== adapter { activated(adapter) }
        systemAppearanceChanged()
    }

    private func updateModeIndicator(_ adapter: InputAdapter) {
        if let indicator = adapter.modeIndicator, indicator != modeStatusItem.title {
            modeStatusItem.title = indicator
        }
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

    /// Scribe Settings, embedded in Scribe.app.
    static let settingsApp = Bundle.main.bundleURL.appending(path: "Contents/Helpers/ScribeSettings.app", directoryHint: .isDirectory)

    func openSettings() {
        NSWorkspace.shared.openApplication(at: Self.settingsApp, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Log.app.error("Could not open Scribe Settings: \(error.localizedDescription, privacy: .public)")
            }
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
        adapter.canPresent = { [weak self, weak adapter] in
            guard let self, let adapter else { return false }
            return self.activeAdapter === adapter
        }
        adapter.onActivate = { [weak self, weak adapter] in
            guard let adapter else { return }
            self?.activated(adapter)
        }
        adapter.onDeactivate = { [weak self, weak adapter] in
            guard let adapter else { return }
            self?.deactivated(adapter)
        }
        adapter.beforeInput = { [weak self, weak adapter] in
            guard let adapter else { return }
            self?.prepareForInput(adapter)
        }
        adapter.onStateChange = { [weak self, weak adapter] in
            guard let self, let adapter, self.activeAdapter === adapter else { return }
            self.updateModeIndicator(adapter)
        }
        adapter.onSchemaChange = { [weak self, weak adapter] schemaID in
            guard let adapter else { return }
            // This can run inside InputSession.update, before its commit and
            // marked-text actions reach the client. Change configuration
            // only; a nested refresh would reorder or lose those actions.
            self?.configure(adapter, schemaID: schemaID)
        }
        adapters.append(WeakAdapter(adapter: adapter))
        return adapter
    }

    private struct WeakAdapter {
        weak var adapter: InputAdapter?
    }

    /// Every client's adapter, for routing notifications to their sessions.
    private var adapters: [WeakAdapter] = []

    /// Queued notifications can arrive after focus or the option changed.
    /// Inactive sessions keep their engine state but cannot change this UI.
    func announce(_ notification: RimeNotification) {
        guard let adapter = activeAdapter, adapter.owns(notification),
              let id = adapter.sessionID, engine.sessionExists(id), !engine.isInMaintenance else { return }
        switch notification.type {
        case "schema":
            let schemaID = String(notification.value.prefix { $0 != "/" })
            guard schemaID == adapter.currentSchemaID else { return }
            configure(adapter, schemaID: schemaID)
            adapter.refreshPresentation()
            updateModeIndicator(adapter)
        case "option":
            let value = !notification.value.hasPrefix("!")
            let option = value ? notification.value : String(notification.value.dropFirst())
            guard engine.option(option, in: id) == value else { return }
            updateModeIndicator(adapter)
        default:
            break
        }
        adapter.handle(notification)
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

    /// OpenCC resolves its dictionaries relative to the working directory,
    /// so librime runs in the shared data directory, as in Squirrel.
    static func useSharedDataAsWorkingDirectory(bundle: Bundle = .main) {
        FileManager.default.changeCurrentDirectoryPath(sharedDataDirectory(bundle: bundle).path(percentEncoded: false))
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
