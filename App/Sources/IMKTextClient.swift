import AppKit
import InputMethodKit
import ScribeCore

/// A client application's text field, as InputMethodKit presents it.
///
/// InputMethodKit calls input controllers on the main thread, and this is
/// only used there; it is Sendable so the controller can pass it to the main
/// actor.
struct IMKTextClient: @unchecked Sendable {
    private let client: any IMKTextInput
    /// Gives the attributes that mark the marked text.
    private let controller: IMKInputController

    init?(_ sender: Any?, controller: IMKInputController) {
        guard let client = sender as? any IMKTextInput else { return nil }
        self.client = client
        self.controller = controller
    }

    var bundleIdentifier: String {
        client.bundleIdentifier() ?? "unknown client"
    }

    /// Types with this keyboard layout while Scribe is active, such as
    /// "com.apple.keylayout.ABC".
    func overrideKeyboard(named layout: String) {
        client.overrideKeyboard(withKeyboardNamed: layout)
    }
}

extension IMKTextClient: TextClient {
    private static let noReplacement = NSRange(location: NSNotFound, length: 0)

    func insertText(_ text: String) {
        client.insertText(text, replacementRange: Self.noReplacement)
    }

    func setMarkedText(_ text: MarkedText) {
        client.setMarkedText(
            text.attributedString(marking: controller.markAttributes),
            selectionRange: text.selectionRange,
            replacementRange: Self.noReplacement
        )
    }

    func caretRect() -> NSRect {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        return rect
    }
}
