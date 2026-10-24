import Foundation
import ScribeCore

/// What the Text Input Sources manager knows about one input source.
struct InputSourceState: Equatable {
    /// Turned on by the user, so it appears in the input menu.
    var isEnabled: Bool
    var isSelectable: Bool
    var isSelected: Bool
    /// The app the input source comes from, when the system says.
    var bundlePath: String?

    /// The app bundle around a file in it, such as an input mode's icon.
    static func bundlePath(containing url: URL) -> String? {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard let app = path.range(of: ".app/") else { return nil }
        return String(path[..<app.lowerBound]) + ".app"
    }
}

/// The Text Input Sources manager, behind a protocol so tests never touch the
/// real one.
@MainActor
protocol InputSourceSystem {
    /// Nil when the input source is not registered.
    func state(of id: String) -> InputSourceState?
    func register(_ bundleURL: URL) -> OSStatus
    func enable(_ id: String) -> OSStatus
    func disable(_ id: String) -> OSStatus
    func select(_ id: String) -> OSStatus
    /// The selected keyboard input source.
    var currentInputSourceID: String? { get }
}

/// Registers, enables, disables and selects Scribe's input sources, with
/// Squirrel's rules for its command line options.
@MainActor
struct InputSourceInstaller {
    nonisolated static let bundleIdentifier = "io.github.itvx.inputmethod.Scribe"
    nonisolated static let primaryMode = InputMode.hans

    let system: InputSourceSystem

    var enabledModes: [InputMode] {
        InputMode.allCases.filter { system.state(of: id($0))?.isEnabled == true }
    }

    /// Whether one of Scribe's modes is the selected input source.
    var isScribeCurrent: Bool {
        guard let id = system.currentInputSourceID else { return false }
        return id == Self.bundleIdentifier || id.hasPrefix(Self.bundleIdentifier + ".")
    }

    /// Registers the input sources of the app at `bundleURL`, unless Scribe's
    /// modes are already registered from it. Squirrel skips registering once
    /// a mode is enabled, but that mode may come from another copy, such as a
    /// development build replaced by the release. Never enables or selects.
    func register(bundleURL: URL) -> Bool {
        let path = bundleURL.standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/")
        let here = InputMode.allCases.filter { system.state(of: id($0))?.bundlePath?.trimmingSuffix("/") == path }
        if !here.isEmpty {
            report("Scribe input sources already registered from \(path): \(ids(here))")
            return true
        }
        let status = system.register(bundleURL)
        guard status == noErr else {
            report("Failed to register input sources from \(bundleURL.path) (error \(status))")
            return false
        }
        report("Registered input sources from \(bundleURL.path)")
        return true
    }

    /// Enables `modes`; with none, enables the primary mode unless the user
    /// already enabled some mode, which is kept as it is.
    func enable(_ modes: [InputMode]) {
        if modes.isEmpty, !enabledModes.isEmpty {
            report("Scribe input sources already enabled: \(ids(enabledModes))")
            return
        }
        for mode in modes.isEmpty ? [Self.primaryMode] : modes where system.state(of: id(mode))?.isEnabled == false {
            let status = system.enable(id(mode))
            report("Enabling \(id(mode)) \(status == noErr ? "succeeded" : "failed (error \(status))")")
        }
    }

    /// Disables `modes`, or every mode.
    func disable(_ modes: [InputMode]) {
        for mode in modes.isEmpty ? InputMode.allCases : modes where system.state(of: id(mode))?.isEnabled == true {
            let status = system.disable(id(mode))
            report("Disabling \(id(mode)) \(status == noErr ? "succeeded" : "failed (error \(status))")")
        }
    }

    /// Selects `mode`, enabling it first; without a mode, selects the primary
    /// mode if the user has enabled it.
    func select(_ mode: InputMode?) {
        let target = mode ?? Self.primaryMode
        if !enabledModes.contains(target) {
            guard mode != nil else {
                report("The primary input source is not enabled: \(id(target))")
                return
            }
            enable([target])
        }
        guard let state = system.state(of: id(target)), state.isEnabled, state.isSelectable, !state.isSelected else {
            report("Not selecting \(id(target)): not enabled, not selectable or already selected")
            return
        }
        let status = system.select(id(target))
        report("Selecting \(id(target)) \(status == noErr ? "succeeded" : "failed (error \(status))")")
    }

    private func id(_ mode: InputMode) -> String {
        mode.inputSourceID(bundleIdentifier: Self.bundleIdentifier)
    }

    private func ids(_ modes: [InputMode]) -> String {
        modes.map(id).joined(separator: ", ")
    }

    private func report(_ message: String) {
        print(message)
        Log.installer.notice("\(message, privacy: .public)")
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
