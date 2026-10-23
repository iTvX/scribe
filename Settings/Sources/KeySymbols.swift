import AppKit
import ScribeCore

/// Rime key names, such as "Control+grave", shown the way macOS menus show
/// keys, such as "⌃`".
enum KeySymbols {
    static func display(_ name: String) -> String {
        guard let event = KeyEvent(name: name) else { return name }
        var text = event.modifiers.contains(.release) ? "松开 " : ""
        let modifiers: [(KeyModifiers, String)] = [(.control, "⌃"), (.alt, "⌥"), (.shift, "⇧"), (.super, "⌘"), (.capsLock, "⇪")]
        for (modifier, symbol) in modifiers where event.modifiers.contains(modifier) {
            text += symbol
        }
        let key = keyName(of: event)
        return text + (symbols[key] ?? (key.count == 1 ? key.uppercased() : key))
    }

    /// The Rime name of the key a key-down event types, or nil for keys Rime
    /// has no name for and Command shortcuts.
    static func rimeName(of event: NSEvent) -> String? {
        var flags: MacModifierFlags = []
        if event.modifierFlags.contains(.shift) { flags.insert(.shift) }
        if event.modifierFlags.contains(.control) { flags.insert(.control) }
        if event.modifierFlags.contains(.option) { flags.insert(.option) }
        if event.modifierFlags.contains(.command) { flags.insert(.command) }
        // Caps Lock changes letters, not the key; Rime names it without Lock.
        return MacKeyTranslator.keyDown(
            keyCode: event.keyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            flags: flags
        )?.description
    }

    /// The key without its modifiers, as KeyEvent names it.
    private static func keyName(of event: KeyEvent) -> String {
        var name = event.description[...]
        for prefix in ["Release+", "Control+", "Alt+", "Super+", "Shift+", "Lock+"] where name.hasPrefix(prefix) {
            name = name.dropFirst(prefix.count)
        }
        return String(name)
    }

    private static let symbols: [String: String] = [
        "grave": "`", "asciitilde": "~", "minus": "-", "equal": "=", "plus": "+", "underscore": "_",
        "bracketleft": "[", "bracketright": "]", "braceleft": "{", "braceright": "}",
        "backslash": "\\", "bar": "|", "semicolon": ";", "colon": ":", "apostrophe": "'", "quotedbl": "\"",
        "comma": ",", "period": ".", "slash": "/", "less": "<", "greater": ">", "question": "?",
        "exclam": "!", "at": "@", "numbersign": "#", "dollar": "$", "percent": "%", "asciicircum": "^",
        "ampersand": "&", "asterisk": "*", "parenleft": "(", "parenright": ")",
        "space": "空格", "Return": "↩", "KP_Enter": "⌤", "Tab": "⇥", "Escape": "⎋", "BackSpace": "⌫", "Delete": "⌦",
        "Home": "↖", "End": "↘", "Page_Up": "⇞", "Page_Down": "⇟",
        "Left": "←", "Right": "→", "Up": "↑", "Down": "↓",
        "Shift_L": "左⇧", "Shift_R": "右⇧", "Control_L": "左⌃", "Control_R": "右⌃",
        "Alt_L": "左⌥", "Alt_R": "右⌥", "Super_L": "左⌘", "Super_R": "右⌘",
        "Caps_Lock": "⇪", "Eisu_toggle": "英数",
    ]
}
