/// Rime's modifier mask bits.
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let capsLock = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)
    public static let alt = KeyModifiers(rawValue: 1 << 3)
    public static let `super` = KeyModifiers(rawValue: 1 << 26)
    public static let release = KeyModifiers(rawValue: 1 << 30)

    /// In the order used when naming a key, such as "Control+Shift+a".
    static let named: [(String, KeyModifiers)] = [
        ("Release", .release),
        ("Control", .control),
        ("Alt", .alt),
        ("Super", .super),
        ("Shift", .shift),
        ("Lock", .capsLock),
    ]
}

/// A key as librime sees it: an X11 keysym plus Rime modifier bits.
public struct KeyEvent: Hashable, Sendable, CustomStringConvertible {
    public var keycode: Int32
    public var modifiers: KeyModifiers

    public init(_ keycode: Int32, modifiers: KeyModifiers = []) {
        self.keycode = keycode
        self.modifiers = modifiers
    }

    /// Parses a key written as in Rime's configuration: an optional
    /// "Modifier+" prefix followed by a keysym name or a single printable
    /// character, such as "a", "space", "Page_Down" or "Release+Shift_L".
    public init?(name: String) {
        var parts = name.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // A trailing "+" names the plus key itself, as in "Shift++".
        if name.hasSuffix("++") {
            parts.removeLast(2)
            parts.append("+")
        }
        guard let keyName = parts.popLast(), let keycode = Keysym.code(named: keyName) else { return nil }
        var modifiers: KeyModifiers = []
        for part in parts {
            guard let modifier = KeyModifiers.named.first(where: { $0.0 == part })?.1 else { return nil }
            modifiers.insert(modifier)
        }
        self.init(keycode, modifiers: modifiers)
    }

    public var description: String {
        let prefix = KeyModifiers.named.filter { modifiers.contains($0.1) }.map { "\($0.0)+" }.joined()
        return prefix + Keysym.name(of: keycode)
    }
}

/// The X11 keysyms Scribe uses.
public enum Keysym {
    public static let space: Int32 = 0x0020
    public static let backSpace: Int32 = 0xff08
    public static let tab: Int32 = 0xff09
    public static let `return`: Int32 = 0xff0d
    public static let escape: Int32 = 0xff1b
    public static let delete: Int32 = 0xffff
    public static let home: Int32 = 0xff50
    public static let left: Int32 = 0xff51
    public static let up: Int32 = 0xff52
    public static let right: Int32 = 0xff53
    public static let down: Int32 = 0xff54
    public static let pageUp: Int32 = 0xff55
    public static let pageDown: Int32 = 0xff56
    public static let end: Int32 = 0xff57
    public static let keypadEnter: Int32 = 0xff8d
    public static let shiftL: Int32 = 0xffe1
    public static let shiftR: Int32 = 0xffe2
    public static let controlL: Int32 = 0xffe3
    public static let controlR: Int32 = 0xffe4
    public static let capsLock: Int32 = 0xffe5
    public static let altL: Int32 = 0xffe9
    public static let altR: Int32 = 0xffea
    public static let superL: Int32 = 0xffeb
    public static let superR: Int32 = 0xffec

    /// Keypad digits KP_0 through KP_9.
    public static func keypad(_ digit: Int) -> Int32 {
        0xffb0 + Int32(digit)
    }

    /// Function keys F1 through F35.
    public static func function(_ number: Int) -> Int32 {
        0xffbd + Int32(number)
    }

    /// The keysym of a character: its code point for Latin-1, otherwise the
    /// Unicode keysym range.
    public static func character(_ scalar: Unicode.Scalar) -> Int32 {
        scalar.value < 0x100 ? Int32(scalar.value) : 0x0100_0000 | Int32(scalar.value)
    }

    static let names: [String: Int32] = {
        var names: [String: Int32] = [
            "space": space, "BackSpace": backSpace, "Tab": tab, "Return": `return`,
            "Escape": escape, "Delete": delete, "Home": home, "Left": left, "Up": up,
            "Right": right, "Down": down, "Page_Up": pageUp, "Page_Down": pageDown,
            "End": end, "KP_Enter": keypadEnter, "Shift_L": shiftL, "Shift_R": shiftR,
            "Control_L": controlL, "Control_R": controlR, "Caps_Lock": capsLock,
            "Alt_L": altL, "Alt_R": altR, "Super_L": superL, "Super_R": superR,
            "KP_Decimal": 0xffae, "KP_Add": 0xffab, "KP_Subtract": 0xffad,
            "KP_Multiply": 0xffaa, "KP_Divide": 0xffaf, "KP_Equal": 0xffbd,
            // Printable characters that are awkward to write on their own.
            "numbersign": 0x23, "semicolon": 0x3b, "equal": 0x3d, "minus": 0x2d,
            "comma": 0x2c, "period": 0x2e, "slash": 0x2f, "grave": 0x60,
            "apostrophe": 0x27, "bracketleft": 0x5b, "bracketright": 0x5d, "backslash": 0x5c,
        ]
        for digit in 0...9 {
            names["KP_\(digit)"] = keypad(digit)
        }
        for number in 1...12 {
            names["F\(number)"] = function(number)
        }
        return names
    }()

    static func code(named name: String) -> Int32? {
        if let code = names[name] {
            return code
        }
        let scalars = name.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first, scalar.value > 0x20, scalar.value != 0x7f else { return nil }
        return character(scalar)
    }

    static func name(of code: Int32) -> String {
        if code > 0x20, code < 0x7f, let scalar = Unicode.Scalar(UInt32(code)) {
            return String(scalar)
        }
        if let name = names.filter({ $0.value == code }).map(\.key).min() {
            return name
        }
        if code & 0x0100_0000 != 0, let scalar = Unicode.Scalar(UInt32(code & 0x00ff_ffff)) {
            return String(scalar)
        }
        return "0x" + String(code, radix: 16)
    }
}
