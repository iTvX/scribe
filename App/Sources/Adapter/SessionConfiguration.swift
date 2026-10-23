import Foundation
import ScribeConfig
import ScribeCore

/// What each client's session takes from squirrel.yaml and the current
/// schema's style.
struct SessionConfiguration: Equatable {
    var chordDuration: TimeInterval = 0.1
    var notifications = NotificationPolicy.appropriate
    var statusMessageType = StatusMessageType.mix
    var presentation = InputSession.Presentation()
    var appOptions = AppOptions()
    var reportsBundleID = false
    var keyboardLayout = KeyboardLayout.last

    /// Squirrel's defaults, until squirrel.yaml is read.
    init() {}

    init(settings: ScribeSettings, theme: Theme) {
        chordDuration = settings.chordDuration
        notifications = settings.notificationPolicy
        statusMessageType = theme.statusMessageType
        presentation = InputSession.Presentation(
            inlinePreedit: theme.inlinePreedit,
            inlineCandidate: theme.inlineCandidate,
            linear: theme.layout == .linear,
            vertical: theme.orientation == .vertical
        )
        appOptions = settings.appOptions
        reportsBundleID = settings.reportsBundleID
        keyboardLayout = settings.keyboardLayout
    }

    func clientApp(_ bundleID: String) -> InputSession.ClientApp {
        InputSession.ClientApp(bundleID: bundleID, options: appOptions.options(for: bundleID), reportsBundleID: reportsBundleID)
    }
}
