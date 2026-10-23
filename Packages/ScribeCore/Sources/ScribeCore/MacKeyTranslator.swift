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
/// the keys librime expects, the way Squirrel does.
public enum MacKeyTranslator {
    /// A key press, or nil for keys that go to the client untouched: Command
    /// shortcuts and keys with no Rime equivalent.
    ///
    /// Function and editing keys are identified by position. Other keys by
    /// the ASCII character they type, which respects the keyboard layout;
    /// layouts that type non-ASCII characters fall back to the key's
    /// position on an ANSI keyboard.
    public static func keyDown(
        keyCode: UInt16,
        characters: String?,
        charactersIgnoringModifiers: String?,
        flags: MacModifierFlags
    ) -> KeyEvent? {
        guard !flags.contains(.command) else { return nil }
        let modifiers = flags.keyModifiers
        if let keysym = positionalKeys[keyCode] {
            return KeyEvent(keysym, modifiers: modifiers)
        }

        // With only Shift or Caps Lock held, symbols come from the characters
        // actually typed; with other modifiers, the base character, unless
        // the layout makes it non-ASCII.
        var character = charactersIgnoringModifiers?.first
        let onlyCapitalizing = flags.isSubset(of: [.shift, .capsLock])
        if let base = character, onlyCapitalizing ? !base.isLetter : !base.isASCII {
            character = characters?.first
        }
        if let character, character.isASCII, let keysym = asciiKeysym(
            character,
            capitalized: flags.contains(.shift) != flags.contains(.capsLock)
        ) {
            return KeyEvent(keysym, modifiers: modifiers)
        }
        return ansiKeys[keyCode].map { KeyEvent($0, modifiers: modifiers) }
    }

    /// A change of modifier keys, from `old` to `new`.
    ///
    /// Each changed modifier becomes a press or a release of the modifier key
    /// that sent the event, carrying the new modifier state. A release that
    /// arrives with the next press goes first. A Caps Lock change goes before
    /// everything, carrying the lock state from before the toggle, as Rime
    /// expects. Some remote desktop tools send these events without a
    /// modifier key code; the key is then inferred from what changed.
    public static func flagsChanged(keyCode: UInt16, from old: MacModifierFlags, to new: MacModifierFlags) -> [KeyEvent] {
        let changes = old.symmetricDifference(new)
        guard let keysym = modifierKeys[keyCode] ?? inferredModifierKey(changes) else { return [] }
        var modifiers = new.keyModifiers
        var events: [KeyEvent] = []
        if changes.contains(.capsLock) {
            modifiers.formSymmetricDifference(.capsLock)
            events.append(KeyEvent(keysym, modifiers: modifiers))
        }
        var releases: [KeyEvent] = []
        var presses: [KeyEvent] = []
        for flag in [MacModifierFlags.shift, .control, .option, .command] where changes.contains(flag) {
            if new.contains(flag) {
                presses.append(KeyEvent(keysym, modifiers: modifiers))
            } else {
                releases.insert(KeyEvent(keysym, modifiers: modifiers.union(.release)), at: 0)
            }
        }
        return events + releases + presses
    }

    private static func asciiKeysym(_ character: Character, capitalized: Bool) -> Int32? {
        if capitalized, character.isLowercase, let upper = character.uppercased().unicodeScalars.first {
            return Int32(upper.value)
        }
        guard let value = character.unicodeScalars.first?.value else { return nil }
        switch value {
        case 0x20...0x7e:
            return Int32(value)
        // Control+[, Control+\, Control+] and Control+- type these.
        case 0x1b:
            return 0x5b
        case 0x1c:
            return 0x5c
        case 0x1d:
            return 0x5d
        case 0x1f:
            return 0x2d
        default:
            return nil
        }
    }

    private static func inferredModifierKey(_ changes: MacModifierFlags) -> Int32? {
        if changes.contains(.capsLock) { return Keysym.capsLock }
        if changes.contains(.shift) { return Keysym.shiftL }
        if changes.contains(.control) { return Keysym.controlL }
        if changes.contains(.option) { return Keysym.altL }
        if changes.contains(.command) { return Keysym.superL }
        return nil
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
            0x72: 0xff6a,  // Help
            0x73: Keysym.home,
            0x77: Keysym.end,
            0x74: Keysym.pageUp,
            0x79: Keysym.pageDown,
            0x7b: Keysym.left,
            0x7c: Keysym.right,
            0x7d: Keysym.down,
            0x7e: Keysym.up,
            0x4c: Keysym.keypadEnter,
            0x47: 0xff0b,  // keypad Clear
            0x41: 0xffae,  // keypad decimal
            0x43: 0xffaa,  // keypad multiply
            0x45: 0xffab,  // keypad plus
            0x4b: 0xffaf,  // keypad divide
            0x4e: 0xffad,  // keypad minus
            0x51: 0xffbd,  // keypad equals
            0x0a: 0xa7,    // ISO section
            0x5d: 0xa5,    // JIS yen
            0x5e: 0x5f,    // JIS underscore
            0x5f: 0x2c,    // JIS keypad comma
            0x66: 0xff2f,  // JIS Eisu
            0x68: 0xff2e,  // JIS Kana
        ]
        let keypadDigits: [UInt16] = [0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5b, 0x5c]
        for (digit, keyCode) in keypadDigits.enumerated() {
            keys[keyCode] = Keysym.keypad(digit)
        }
        let functionKeys: [UInt16] = [
            0x7a, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6d,
            0x67, 0x6f, 0x69, 0x6b, 0x71, 0x6a, 0x40, 0x4f, 0x50, 0x5a,
        ]
        for (index, keyCode) in functionKeys.enumerated() {
            keys[keyCode] = Keysym.function(index + 1)
        }
        return keys
    }()

    /// What each key types on an ANSI keyboard, for layouts that type
    /// non-ASCII characters.
    static let ansiKeys: [UInt16: Int32] = {
        let letters: [(UInt16, Character)] = [
            (0x00, "a"), (0x0b, "b"), (0x08, "c"), (0x02, "d"), (0x0e, "e"), (0x03, "f"), (0x05, "g"),
            (0x04, "h"), (0x22, "i"), (0x26, "j"), (0x28, "k"), (0x25, "l"), (0x2e, "m"), (0x2d, "n"),
            (0x1f, "o"), (0x23, "p"), (0x0c, "q"), (0x0f, "r"), (0x01, "s"), (0x11, "t"), (0x20, "u"),
            (0x09, "v"), (0x0d, "w"), (0x07, "x"), (0x10, "y"), (0x06, "z"),
            (0x1d, "0"), (0x12, "1"), (0x13, "2"), (0x14, "3"), (0x15, "4"), (0x17, "5"), (0x16, "6"),
            (0x1a, "7"), (0x1c, "8"), (0x19, "9"),
            (0x1e, "]"), (0x21, "["), (0x2b, ","), (0x32, "`"), (0x2f, "."), (0x29, ";"),
            (0x27, "'"), (0x2a, "\\"), (0x1b, "-"), (0x2c, "/"), (0x18, "="),
        ]
        return Dictionary(uniqueKeysWithValues: letters.map { ($0.0, Int32($0.1.unicodeScalars.first!.value)) })
    }()

    static let modifierKeys: [UInt16: Int32] = [
        0x38: Keysym.shiftL,
        0x3c: Keysym.shiftR,
        0x3b: Keysym.controlL,
        0x3e: Keysym.controlR,
        0x3a: Keysym.altL,
        0x3d: Keysym.altR,
        0x37: Keysym.superL,
        0x36: Keysym.superR,
        0x39: Keysym.capsLock,
    ]
}
