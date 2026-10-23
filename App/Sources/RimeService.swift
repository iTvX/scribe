import AppKit
import RimeKit
import ScribeConfig
import ScribeCore
import ScribeUI

extension CandidatePanel: CandidatePresenting {}

/// The process's Rime engine and candidate window, shared by every client.
@MainActor
final class RimeService {
    static let shared = RimeService()

    /// Posted by `Scribe --reload` to make the running instance redeploy.
    static let reloadNotification = Notification.Name("io.github.itvx.inputmethod.Scribe.reload")

    let engine = LibrimeEngine.shared
    let candidatePanel = CandidatePanel()

    private init() {}

    /// Starts librime and deploys if the user's files changed.
    func start() {
        engine.notificationHandler = Self.log
        engine.start(Self.configuration())
        engine.startMaintenance(fullCheck: false)
        DistributedNotificationCenter.default().addObserver(forName: Self.reloadNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                RimeService.shared.redeploy()
            }
        }
    }

    /// Restarts librime and deploys everything again. Open sessions are
    /// dropped; each client starts a new one on its next key.
    func redeploy() {
        Log.app.notice("Redeploying")
        if engine.isInMaintenance {
            engine.joinMaintenance()
        }
        engine.stop()
        engine.start(Self.configuration())
        engine.startMaintenance(fullCheck: true)
    }

    func makeAdapter() -> InputAdapter {
        InputAdapter(session: InputSession(engine: engine), candidates: candidatePanel)
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
