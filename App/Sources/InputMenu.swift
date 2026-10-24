import AppKit

/// The menu Scribe adds to the input menu while it is active.
enum InputMenu {
    enum Command: CaseIterable {
        case deploy
        case sync
        /// Scribe Settings, which ships inside Scribe.app.
        case openSettings
        case openLogs
        case openUserFolder
        case openHelp
        /// Only in release builds that update themselves.
        case checkForUpdates

        /// The English title, also the key into Localizable.strings.
        var title: String {
            switch self {
            case .deploy: "Deploy"
            case .sync: "Sync user data"
            case .openSettings: "Settings…"
            case .openLogs: "Logs…"
            case .openUserFolder: "User folder…"
            case .openHelp: "Help…"
            case .checkForUpdates: "Check for updates…"
            }
        }

        /// Implemented by the input controller, which InputMethodKit sends
        /// menu actions to.
        var action: Selector {
            switch self {
            case .deploy: Selector(("deploy:"))
            case .sync: Selector(("syncUserData:"))
            case .openSettings: Selector(("openSettings:"))
            case .openLogs: Selector(("openLogs:"))
            case .openUserFolder: Selector(("openUserFolder:"))
            case .openHelp: Selector(("openHelp:"))
            case .checkForUpdates: Selector(("checkForUpdates:"))
            }
        }
    }

    @MainActor
    static func make(target: AnyObject, offersUpdates: Bool = false) -> NSMenu {
        let menu = NSMenu()
        for command in Command.allCases where offersUpdates || command != .checkForUpdates {
            let item = NSMenuItem(title: Bundle.main.localizedString(forKey: command.title, value: nil, table: nil), action: command.action, keyEquivalent: "")
            item.target = target
            if command == .deploy {
                // As in Squirrel.
                item.keyEquivalent = "`"
                item.keyEquivalentModifierMask = [.control, .option]
            }
            menu.addItem(item)
        }
        return menu
    }
}
