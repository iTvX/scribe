import ScribeCore
import Testing

private func keyDown(_ keyCode: UInt16, _ characters: String?, ignoring: String? = nil, _ flags: MacModifierFlags = []) -> KeyEvent? {
    MacKeyTranslator.keyDown(keyCode: keyCode, characters: characters, charactersIgnoringModifiers: ignoring ?? characters, flags: flags)
}

@Test func lettersUseTheTypedCharacter() {
    #expect(keyDown(0x00, "a") == KeyEvent(0x61))
    #expect(keyDown(0x00, "A", .shift) == KeyEvent(0x41, modifiers: .shift))
}

@Test func capsLockCapitalizesLikeShift() {
    // AppKit ignores Caps Lock in charactersIgnoringModifiers.
    #expect(keyDown(0x00, "A", ignoring: "a", .capsLock) == KeyEvent(0x41, modifiers: .capsLock))
    #expect(keyDown(0x00, "a", ignoring: "A", [.capsLock, .shift]) == KeyEvent(0x41, modifiers: [.capsLock, .shift]))
}

@Test func shiftedSymbolsUseTheTypedCharacter() {
    #expect(keyDown(0x12, "!", ignoring: "1", .shift) == KeyEvent(0x21, modifiers: .shift))
}

@Test func otherModifiersKeepTheBaseCharacter() {
    #expect(keyDown(0x00, "å", ignoring: "a", .option) == KeyEvent(0x61, modifiers: .alt))
    #expect(keyDown(0x08, "\u{3}", ignoring: "c", .control) == KeyEvent(0x63, modifiers: .control))
    #expect(keyDown(0x21, "\u{1b}", ignoring: "[", .control) == KeyEvent(0x5b, modifiers: .control))
}

@Test func controlCharactersMapToTheirKeys() {
    #expect(keyDown(0x21, "\u{1b}", ignoring: "\u{1b}", .control) == KeyEvent(0x5b, modifiers: .control))
    #expect(keyDown(0x2a, "\u{1c}", ignoring: "\u{1c}", .control) == KeyEvent(0x5c, modifiers: .control))
    #expect(keyDown(0x1e, "\u{1d}", ignoring: "\u{1d}", .control) == KeyEvent(0x5d, modifiers: .control))
    #expect(keyDown(0x1b, "\u{1f}", ignoring: "\u{1f}", .control) == KeyEvent(0x2d, modifiers: .control))
}

@Test func nonASCIILayoutsFallBackToKeyPosition() {
    // The French layout types "é" on the key where ANSI has "2".
    #expect(keyDown(0x13, "é") == KeyEvent(0x32))
    #expect(keyDown(0x0c, "ф") == KeyEvent(0x71))
}

@Test func commandShortcutsAreNotTranslated() {
    #expect(keyDown(0x08, "c", .command) == nil)
    #expect(keyDown(0x24, "\r", [.command, .shift]) == nil)
}

private let positionalKeys: [(UInt16, Int32)] = [
    (0x24, Keysym.return), (0x31, Keysym.space), (0x33, Keysym.backSpace), (0x35, Keysym.escape),
    (0x30, Keysym.tab), (0x75, Keysym.delete), (0x74, Keysym.pageUp), (0x79, Keysym.pageDown),
    (0x7b, Keysym.left), (0x7e, Keysym.up), (0x4c, Keysym.keypadEnter), (0x52, Keysym.keypad(0)),
    (0x5c, Keysym.keypad(9)), (0x7a, Keysym.function(1)), (0x5a, Keysym.function(20)),
    (0x72, 0xff6a), (0x47, 0xff0b), (0x0a, 0xa7), (0x5d, 0xa5), (0x5e, 0x5f), (0x5f, 0x2c),
    (0x66, 0xff2f), (0x68, 0xff2e),
]

@Test(arguments: positionalKeys)
func positionalKeysIgnoreTheirCharacters(keyCode: UInt16, keysym: Int32) {
    #expect(keyDown(keyCode, "\u{F700}") == KeyEvent(keysym))
}

@Test func unknownKeysAreNotTranslated() {
    #expect(keyDown(0x3f, "") == nil)
    #expect(keyDown(0x6e, nil) == nil)
}

// MARK: Modifier changes

private func flagsChanged(_ keyCode: UInt16, _ old: MacModifierFlags, _ new: MacModifierFlags) -> [KeyEvent] {
    MacKeyTranslator.flagsChanged(keyCode: keyCode, from: old, to: new)
}

@Test func modifierPressCarriesTheNewState() {
    #expect(flagsChanged(0x38, [], .shift) == [KeyEvent(Keysym.shiftL, modifiers: .shift)])
    #expect(flagsChanged(0x3c, [], .shift) == [KeyEvent(Keysym.shiftR, modifiers: .shift)])
    #expect(flagsChanged(0x3b, .shift, [.shift, .control]) == [KeyEvent(Keysym.controlL, modifiers: [.shift, .control])])
    #expect(flagsChanged(0x3a, [], .option) == [KeyEvent(Keysym.altL, modifiers: .alt)])
    #expect(flagsChanged(0x37, [], .command) == [KeyEvent(Keysym.superL, modifiers: .super)])
}

@Test func modifierReleaseCarriesTheNewStateAndRelease() {
    #expect(flagsChanged(0x38, .shift, []) == [KeyEvent(Keysym.shiftL, modifiers: .release)])
    #expect(flagsChanged(0x3e, [.control, .shift], .shift) == [KeyEvent(Keysym.controlR, modifiers: [.shift, .release])])
}

/// A release can arrive in the same event as the next press; the release
/// goes first.
@Test func releaseComesBeforePressInOneEvent() {
    #expect(flagsChanged(0x3b, .shift, .control) == [
        KeyEvent(Keysym.controlL, modifiers: [.control, .release]),
        KeyEvent(Keysym.controlL, modifiers: .control),
    ])
}

/// Rime expects Caps_Lock with the lock state from before the toggle.
@Test func capsLockCarriesThePreviousLockState() {
    #expect(flagsChanged(0x39, [], .capsLock) == [KeyEvent(Keysym.capsLock)])
    #expect(flagsChanged(0x39, .capsLock, []) == [KeyEvent(Keysym.capsLock, modifiers: .capsLock)])
}

@Test func capsLockGoesFirst() {
    // Shift released and Caps Lock turned on in one event.
    #expect(flagsChanged(0x39, .shift, .capsLock) == [
        KeyEvent(Keysym.capsLock),
        KeyEvent(Keysym.capsLock, modifiers: .release),
    ])
}

/// Some remote desktop tools report modifier changes with key code 0.
@Test func modifierKeyIsInferredWithoutAKeyCode() {
    #expect(flagsChanged(0x00, [], .shift) == [KeyEvent(Keysym.shiftL, modifiers: .shift)])
    #expect(flagsChanged(0x00, .control, []) == [KeyEvent(Keysym.controlL, modifiers: .release)])
    #expect(flagsChanged(0x00, [], .capsLock) == [KeyEvent(Keysym.capsLock)])
}

@Test func unchangedModifiersProduceNothing() {
    #expect(flagsChanged(0x38, .shift, .shift).isEmpty)
    #expect(flagsChanged(0x00, [], []).isEmpty)
}
