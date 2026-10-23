import Carbon
import Foundation
import ScribeCore

/// Registers Scribe with the Text Input Sources manager.
///
/// Registering only makes the input sources available in System Settings;
/// enabling and selecting them is left to the user.
enum InputSourceInstaller {
    /// Registers the input sources of the app at `bundleURL`, unless the user
    /// has already enabled one of Scribe's modes, as Squirrel does.
    static func register(bundleURL: URL, bundleIdentifier: String) -> Bool {
        let enabled = enabledModes(bundleIdentifier: bundleIdentifier)
        if !enabled.isEmpty {
            let ids = enabled.map { $0.inputSourceID(bundleIdentifier: bundleIdentifier) }.joined(separator: ", ")
            print("Scribe input sources already enabled: \(ids)")
            Log.installer.notice("Skipped registration, already enabled: \(ids, privacy: .public)")
            return true
        }
        let status = TISRegisterInputSource(bundleURL as CFURL)
        guard status == noErr else {
            print("Failed to register input sources from \(bundleURL.path) (error \(status))")
            Log.installer.error("TISRegisterInputSource failed for \(bundleURL.path, privacy: .public): \(status)")
            return false
        }
        print("Registered input sources from \(bundleURL.path)")
        Log.installer.notice("Registered input sources from \(bundleURL.path, privacy: .public)")
        return true
    }

    /// Scribe's modes that the user has enabled in System Settings.
    ///
    /// Asks only for enabled sources rather than checking each mode's
    /// `kTISPropertyInputSourceIsEnabled`: a mode reports its default state
    /// there even while Scribe itself is disabled.
    private static func enabledModes(bundleIdentifier: String) -> [InputMode] {
        let filter = [kTISPropertyBundleID as String: bundleIdentifier] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return sources.compactMap { source in
            guard let id = stringProperty(source, kTISPropertyInputSourceID) else { return nil }
            return InputMode(inputSourceID: id, bundleIdentifier: bundleIdentifier)
        }
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }
}
