import Foundation
import ScribeCore

/// What the Text Input Sources manager knows about one input source.
struct InputSourceState: Equatable {
    /// Turned on by the user, so it appears in the input menu.
    var isEnabled: Bool
    var isSelectable: Bool
    var isSelected: Bool
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

    /// Registers the input sources of the app at `bundleURL`, unless the user
    /// has already enabled one of Scribe's modes.
    func register(bundleURL: URL) -> Bool {
        let enabled = enabledModes
        if !enabled.isEmpty {
            report("Scribe input sources already enabled: \(ids(enabled))")
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
