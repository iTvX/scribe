import AppKit
import Sparkle
import UserNotifications

/// Keeps a release build up to date with Sparkle. Sparkle checks the feed
/// once a day; an input method must never take focus while the user types,
/// so a scheduled check that finds an update only posts a notification, and
/// Sparkle's window appears when the user clicks it or chooses "Check for
/// updates…".
@MainActor
final class SoftwareUpdater: NSObject {
    static let shared = SoftwareUpdater()

    /// Each notification replaces the one before.
    nonisolated private static let notificationIdentifier = "io.github.itvx.inputmethod.Scribe.update"

    private var controller: SPUStandardUpdaterController?
    private var bundle = Bundle.main

    /// Whether this copy updates itself, and so offers "Check for updates…".
    var isAvailable: Bool {
        controller != nil
    }

    func start(bundle: Bundle = .main) {
        guard controller == nil else { return }
        guard let configuration = configuration(bundle: bundle) else {
            Log.app.info("Software updates are off for this build")
            return
        }
        self.bundle = bundle
        UNUserNotificationCenter.current().delegate = self
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        Log.app.notice("Checking for updates at \(configuration.feedURL.absoluteString, privacy: .public)")
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Read again for every check, so changing BetaUpdates needs no restart.
    private func configuration(bundle: Bundle) -> UpdateConfiguration? {
        UpdateConfiguration(infoDictionary: bundle.infoDictionary ?? [:], bundleURL: bundle.bundleURL, defaults: .standard)
    }

    /// A quiet notification, posted as DeployMessage posts its own.
    private func postUpdateNotification(version: String) {
        let title = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String ?? "Scribe"
        let format = bundle.localizedString(forKey: "update_available", value: nil, table: nil)
        Self.post(title: title, subtitle: String.localizedStringWithFormat(format, version))
    }

    nonisolated private static func post(title: String, subtitle: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .provisional])
            let settings = await center.notificationSettings()
            guard [.authorized, .provisional].contains(settings.authorizationStatus), settings.alertSetting == .enabled else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.subtitle = subtitle
            content.interruptionLevel = .active
            try? await center.add(UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: nil))
        }
    }
}

extension SoftwareUpdater: SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        configuration(bundle: bundle)?.allowedChannels ?? []
    }
}

extension SoftwareUpdater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    /// Sparkle never shows a window for a scheduled check on its own.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate {
            // The user asked, so bring Sparkle's window forward, as Squirrel does.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        } else {
            postUpdateNotification(version: update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
    }

    func standardUserDriverWillFinishUpdateSession() {
        NSApp.setActivationPolicy(.accessory)
    }
}

extension SoftwareUpdater: UNUserNotificationCenterDelegate {
    /// Deploy messages keep showing too.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == Self.notificationIdentifier,
              response.actionIdentifier == UNNotificationDefaultActionIdentifier
        else { return }
        await checkForUpdates()
    }
}
