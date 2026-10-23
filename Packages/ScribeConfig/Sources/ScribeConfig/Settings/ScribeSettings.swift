/// The keyboard layout to use while Scribe is active, from `keyboard_layout`.
public enum KeyboardLayout: Equatable, Sendable {
    /// Keep the last used layout.
    case last
    /// An input source ID such as "com.apple.keylayout.ABC".
    case named(String)

    /// "" or "last" keep the last layout, "default" is ABC, and any other
    /// value is a keylayout ID with or without its "com.apple.keylayout." prefix.
    public init(squirrel value: String) {
        let prefix = "com.apple.keylayout."
        switch value {
        case "", "last":
            self = .last
        case "default":
            self = .named(prefix + "ABC")
        case _ where value.hasPrefix(prefix):
            self = .named(value)
        default:
            self = .named(prefix + value)
        }
    }
}

/// When to post notifications, from `show_notifications_when`. Squirrel only
/// distinguishes `never` from the rest.
public enum NotificationPolicy: String, Sendable {
    case always, appropriate, never
}

/// Option values per app, from `app_options`, which Squirrel sets on each
/// new session for that app.
public struct AppOptions: Equatable, Sendable {
    public var byBundleID: [String: [String: Bool]]

    public init(byBundleID: [String: [String: Bool]] = [:]) {
        self.byBundleID = byBundleID
    }

    /// The options for a bundle ID, matched exactly and case-sensitively.
    public func options(for bundleID: String) -> [String: Bool] {
        byBundleID[bundleID] ?? [:]
    }

    /// Every app listed under `app_options` with the entries that read as
    /// bools; other values are dropped, as in Squirrel's getAppOptions.
    public init(source: some ConfigSource) {
        var byBundleID: [String: [String: Bool]] = [:]
        for bundleID in source.mapKeys(at: "app_options") ?? [] {
            let path = "app_options/\(bundleID)"
            var options: [String: Bool] = [:]
            for option in source.mapKeys(at: path) ?? [] {
                options[option] = source.bool(at: "\(path)/\(option)")
            }
            byBundleID[bundleID] = options
        }
        self.byBundleID = byBundleID
    }
}

/// Scribe's global settings from squirrel.yaml. A schema never changes these.
public struct ScribeSettings: Equatable, Sendable {
    public var configVersion: String?
    public var keyboardLayout: KeyboardLayout
    /// Seconds to wait for more keys of a chord.
    public var chordDuration: Double
    public var notificationPolicy: NotificationPolicy
    public var showsNotifications: Bool { notificationPolicy != .never }
    public var showsStatusIcon: Bool
    /// Whether to tell librime the client's bundle ID (`client_app`).
    public var reportsBundleID: Bool
    public var appOptions: AppOptions
    /// The themes without a schema's `style`.
    public var appearance: Appearance

    public init(squirrel: some ConfigSource) {
        configVersion = squirrel.string(at: "config_version")
        keyboardLayout = KeyboardLayout(squirrel: squirrel.string(at: "keyboard_layout") ?? "")
        if let duration = squirrel.double(at: "chord_duration"), duration > 0 {
            chordDuration = duration
        } else {
            chordDuration = 0.1
        }
        notificationPolicy = switch squirrel.string(at: "show_notifications_when") {
        case "never": .never
        case "always": .always
        default: .appropriate
        }
        showsStatusIcon = squirrel.bool(at: "status_icon/show") ?? true
        reportsBundleID = squirrel.bool(at: "unsafe/report_bundleid") ?? false
        appOptions = AppOptions(source: squirrel)
        appearance = Appearance(squirrel: squirrel)
    }
}
