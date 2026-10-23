import AppKit
import InputMethodKit

/// The InputMethodKit controller, one per client text input session.
///
/// Scribe cannot type yet: every event goes back to the client unhandled.
@objc(ScribeInputController)
final class ScribeInputController: IMKInputController {
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        Log.input.debug("Passing event through: type \(event.type.rawValue), key code \(event.keyCode, privacy: .private)")
        return false
    }

    override func activateServer(_ sender: Any!) {
        Log.input.info("Activated for \(Self.clientIdentifier(sender), privacy: .public)")
    }

    override func deactivateServer(_ sender: Any!) {
        Log.input.info("Deactivated for \(Self.clientIdentifier(sender), privacy: .public)")
    }

    private static func clientIdentifier(_ sender: Any?) -> String {
        (sender as? any IMKTextInput)?.bundleIdentifier() ?? "unknown client"
    }
}
