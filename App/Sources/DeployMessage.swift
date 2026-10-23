import Foundation
import UserNotifications

/// What Scribe tells the user about a deploy, as Squirrel does: a quiet
/// notification, which needs no permission prompt.
enum DeployMessage: CaseIterable {
    case start
    case success
    case failure

    /// From librime's "deploy" notification.
    init?(event: String) {
        switch event {
        case "start": self = .start
        case "success": self = .success
        case "failure": self = .failure
        default: return nil
        }
    }

    /// The key in Localizable.strings.
    var key: String {
        switch self {
        case .start: "deploy_start"
        case .success: "deploy_success"
        case .failure: "deploy_failure"
        }
    }

    /// Each message replaces the one before.
    private static let identifier = "io.github.itvx.inputmethod.Scribe.deploy"

    func post(bundle: Bundle = .main) {
        let title = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String ?? "Scribe"
        let text = bundle.localizedString(forKey: key, value: nil, table: nil)
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .provisional])
            let settings = await center.notificationSettings()
            guard [.authorized, .provisional].contains(settings.authorizationStatus), settings.alertSetting == .enabled else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.subtitle = text
            content.interruptionLevel = .active
            try? await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil))
        }
    }
}
