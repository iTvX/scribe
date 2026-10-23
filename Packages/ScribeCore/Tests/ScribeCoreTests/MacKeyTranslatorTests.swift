import ScribeCore
import Testing

@Test func lettersUseTheTypedCharacter() {
    #expect(MacKeyTranslator.keyDown(keyCode: 0x00, charactersIgnoringModifiers: "a", flags: []) == KeyEvent(0x61))
    #expect(MacKeyTranslator.keyDown(keyCode: 0x00, charactersIgnoringModifiers: "A", flags: .shift) == KeyEvent(0x41, modifiers: .shift))
    #expect(MacKeyTranslator.keyDown(keyCode: 0x12, charactersIgnoringModifiers: "!", flags: .shift) == KeyEvent(0x21, modifiers: .shift))
}

@Test func modifiersMapToRimeMasks() {
    let key = MacKeyTranslator.keyDown(keyCode: 0x08, charactersIgnoringModifiers: "c", flags: [.command, .option, .control, .capsLock])
    #expect(key == KeyEvent(0x63, modifiers: [.super, .alt, .control, .capsLock]))
}

private let positionalKeys: [(UInt16, Int32)] = [
    (0x24, Keysym.return),
    (0x31, Keysym.space),
    (0x33, Keysym.backSpace),
    (0x35, Keysym.escape),
    (0x30, Keysym.tab),
    (0x75, Keysym.delete),
    (0x74, Keysym.pageUp),
    (0x79, Keysym.pageDown),
    (0x7b, Keysym.left),
    (0x7e, Keysym.up),
    (0x4c, Keysym.keypadEnter),
    (0x52, Keysym.keypad(0)),
    (0x5c, Keysym.keypad(9)),
    (0x7a, Keysym.function(1)),
]

@Test(arguments: positionalKeys)
func positionalKeysIgnoreTheirCharacters(keyCode: UInt16, keysym: Int32) {
    // AppKit reports control characters or private-use code points for these.
    #expect(MacKeyTranslator.keyDown(keyCode: keyCode, charactersIgnoringModifiers: "\u{F700}", flags: []) == KeyEvent(keysym))
}

@Test func keysWithoutCharactersAreIgnored() {
    #expect(MacKeyTranslator.keyDown(keyCode: 0x3f, charactersIgnoringModifiers: "", flags: []) == nil)
    #expect(MacKeyTranslator.keyDown(keyCode: 0x0a, charactersIgnoringModifiers: nil, flags: []) == nil)
}

@Test func modifierPressAndRelease() {
    #expect(MacKeyTranslator.flagsChanged(keyCode: 0x38, from: [], to: .shift) == [KeyEvent(Keysym.shiftL, modifiers: .shift)])
    #expect(MacKeyTranslator.flagsChanged(keyCode: 0x38, from: .shift, to: []) == [KeyEvent(Keysym.shiftL, modifiers: [.shift, .release])])
    #expect(MacKeyTranslator.flagsChanged(keyCode: 0x3c, from: [], to: .shift) == [KeyEvent(Keysym.shiftR, modifiers: .shift)])
    #expect(MacKeyTranslator.flagsChanged(keyCode: 0x3b, from: .shift, to: [.shift, .control]) == [KeyEvent(Keysym.controlL, modifiers: [.shift, .control])])
    #expect(MacKeyTranslator.flagsChanged(keyCode: 0x37, from: .command, to: []) == [KeyEvent(Keysym.superL, modifiers: [.super, .release])])
}

@Test func capsLockTogglesWithPressAndRelease() {
    #expect(MacKeyTranslator.flagsChanged(keyCode: 0x39, from: [], to: .capsLock) == [
        KeyEvent(Keysym.capsLock, modifiers: .capsLock),
        KeyEvent(Keysym.capsLock, modifiers: [.capsLock, .release]),
    ])
    #expect(MacKeyTranslator.flagsChanged(keyCode: 0x39, from: .capsLock, to: []) == [
        KeyEvent(Keysym.capsLock),
        KeyEvent(Keysym.capsLock, modifiers: .release),
    ])
}

@Test func unchangedOrUnknownModifiersProduceNothing() {
    #expect(MacKeyTranslator.flagsChanged(keyCode: 0x38, from: .shift, to: .shift).isEmpty)
    #expect(MacKeyTranslator.flagsChanged(keyCode: 0x3f, from: [], to: []).isEmpty)
}
