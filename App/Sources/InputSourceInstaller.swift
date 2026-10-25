import Foundation
import ScribeCore

/// What the Text Input Sources manager knows about one input source.
struct InputSourceState: Equatable {
    /// Reported as enabled. The input menu can still hold a stale list after
    /// an app update, so this is not proof that the menu displays the source.
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
    /// An installed, disabled Apple ASCII keyboard layout suitable for a
    /// reversible enabled-list change. Never an input method or user layout.
    var disabledKeyboardLayoutForRefresh: String? { get }
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

    /// Always registers this bundle: an update replaces the app at the same
    /// path, so a matching path does not mean its registration is current.
    /// Never enables or selects a source.
    func register(bundleURL: URL) -> Bool {
        let status = system.register(bundleURL)
        guard status == noErr else {
            report("Failed to register input sources from \(bundleURL.path) (error \(status))")
            return false
        }
        report("Registered input sources from \(bundleURL.path)")
        return true
    }

    /// Causes the system to rebuild its enabled-source menu after replacing
    /// the app. On macOS 27, re-registration alone can leave Scribe absent
    /// from that menu. A real keyboard-layout change refreshes it. Unlike
    /// input modes, keyboard layouts can still be enabled through TIS.
    /// Runs only in the install helper, never in the input-event process.
    func refreshMenu(settle: (() -> Void)? = nil) -> Bool {
        guard !enabledModes.isEmpty else {
            report("No enabled Scribe modes; input menu refresh is unnecessary")
            return true
        }
        guard system.currentInputSourceID != nil,
              let layout = system.disabledKeyboardLayoutForRefresh,
              let before = system.state(of: layout), before.isSelectable, !before.isEnabled, !before.isSelected
        else {
            report("No inactive system keyboard layout is available for input menu refresh")
            return false
        }

        let enabled = system.enable(layout)
        guard system.state(of: layout)?.isEnabled == true else {
            report("Could not temporarily enable \(layout) (error \(enabled))")
            return false
        }
        if enabled == noErr {
            if let settle {
                settle()
            } else {
                // Let the system consume the intermediate list before
                // restoring it, even if this command has no run-loop sources.
                let deadline = Date(timeIntervalSinceNow: 1)
                while Date() < deadline {
                    if !RunLoop.current.run(mode: .default, before: deadline) {
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                }
            }
        }
        // If the user deliberately chose the temporary layout while it was
        // available, keep their selection instead of switching their input.
        guard system.currentInputSourceID != layout,
              system.state(of: layout)?.isSelected != true else {
            report("Keeping \(layout) because the user selected it during refresh")
            return false
        }
        // Also undo a partial enable that changed state despite an error.
        let disabled = system.disable(layout)
        let restored = system.state(of: layout)?.isEnabled == false
        guard enabled == noErr, disabled == noErr, restored else {
            report("Input menu refresh failed (enable \(enabled), disable \(disabled), restored \(restored))")
            return false
        }
        report("Refreshed the input-source list and removed the temporary keyboard layout")
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
