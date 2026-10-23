/// The modifier keys of a macOS key event, independent of AppKit.
public struct MacModifierFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = MacModifierFlags(rawValue: 1 << 0)
    public static let control = MacModifierFlags(rawValue: 1 << 1)
    public static let option = MacModifierFlags(rawValue: 1 << 2)
    public static let command = MacModifierFlags(rawValue: 1 << 3)
    public static let capsLock = MacModifierFlags(rawValue: 1 << 4)

    var keyModifiers: KeyModifiers {
        var modifiers: KeyModifiers = []
        if contains(.shift) { modifiers.insert(.shift) }
        if contains(.control) { modifiers.insert(.control) }
        if contains(.option) { modifiers.insert(.alt) }
        if contains(.command) { modifiers.insert(.super) }
        if contains(.capsLock) { modifiers.insert(.capsLock) }
        return modifiers
    }
}

/// Translates macOS key events, identified by their virtual key codes, into
/// the keys librime expects.
public enum MacKeyTranslator {
    /// A key press. Keys that produce text are identified by the character
    /// they type without modifiers other than Shift, so that the keyboard
    /// layout is respected; other keys by their position.
    public static func keyDown(keyCode: UInt16, charactersIgnoringModifiers: String?, flags: MacModifierFlags) -> KeyEvent? {
        let modifiers = flags.keyModifiers
        if let keysym = positionalKeys[keyCode] {
            return KeyEvent(keysym, modifiers: modifiers)
        }
        guard let scalar = charactersIgnoringModifiers?.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7f else {
            return nil
        }
        return KeyEvent(Keysym.character(scalar), modifiers: modifiers)
    }

    /// A change of modifier keys. Returns the press or release of the
    /// modifier key that changed; Caps Lock, which toggles, gives both.
    public static func flagsChanged(keyCode: UInt16, from old: MacModifierFlags, to new: MacModifierFlags) -> [KeyEvent] {
        guard let (keysym, flag) = modifierKeys[keyCode] else { return [] }
        if flag == .capsLock {
            guard old.contains(.capsLock) != new.contains(.capsLock) else { return [] }
            return [
                KeyEvent(keysym, modifiers: new.keyModifiers),
                KeyEvent(keysym, modifiers: new.keyModifiers.union(.release)),
            ]
        }
        switch (old.contains(flag), new.contains(flag)) {
        case (false, true):
            return [KeyEvent(keysym, modifiers: new.keyModifiers)]
        case (true, false):
            return [KeyEvent(keysym, modifiers: old.keyModifiers.union(.release))]
        default:
            return []
        }
    }

    /// Keys identified by position rather than by the character they type.
    static let positionalKeys: [UInt16: Int32] = {
        var keys: [UInt16: Int32] = [
            0x24: Keysym.return,
            0x30: Keysym.tab,
            0x31: Keysym.space,
            0x33: Keysym.backSpace,
            0x35: Keysym.escape,
            0x75: Keysym.delete,
            0x73: Keysym.home,
            0x77: Keysym.end,
            0x74: Keysym.pageUp,
            0x79: Keysym.pageDown,
            0x7b: Keysym.left,
            0x7c: Keysym.right,
            0x7d: Keysym.down,
            0x7e: Keysym.up,
            0x4c: Keysym.keypadEnter,
            0x41: 0xffae,  // keypad decimal
            0x43: 0xffaa,  // keypad multiply
            0x45: 0xffab,  // keypad plus
            0x4b: 0xffaf,  // keypad divide
            0x4e: 0xffad,  // keypad minus
            0x51: 0xffbd,  // keypad equals
        ]
        let keypadDigits: [UInt16] = [0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5b, 0x5c]
        for (digit, keyCode) in keypadDigits.enumerated() {
            keys[keyCode] = Keysym.keypad(digit)
        }
        let functionKeys: [UInt16] = [0x7a, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6d, 0x67, 0x6f]
        for (index, keyCode) in functionKeys.enumerated() {
            keys[keyCode] = Keysym.function(index + 1)
        }
        return keys
    }()

    static let modifierKeys: [UInt16: (Int32, MacModifierFlags)] = [
        0x38: (Keysym.shiftL, .shift),
        0x3c: (Keysym.shiftR, .shift),
        0x3b: (Keysym.controlL, .control),
        0x3e: (Keysym.controlR, .control),
        0x3a: (Keysym.altL, .option),
        0x3d: (Keysym.altR, .option),
        0x37: (Keysym.superL, .command),
        0x36: (Keysym.superR, .command),
        0x39: (Keysym.capsLock, .capsLock),
    ]
}
