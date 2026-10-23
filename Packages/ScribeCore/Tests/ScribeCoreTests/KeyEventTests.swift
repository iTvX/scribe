import ScribeCore
import Testing

@Test(arguments: [
    ("a", KeyEvent(0x61)),
    ("A", KeyEvent(0x41)),
    ("1", KeyEvent(0x31)),
    ("space", KeyEvent(Keysym.space)),
    ("Return", KeyEvent(Keysym.return)),
    ("Page_Down", KeyEvent(Keysym.pageDown)),
    ("numbersign", KeyEvent(0x23)),
    ("Shift+Return", KeyEvent(Keysym.return, modifiers: .shift)),
    ("Control+Shift+a", KeyEvent(0x61, modifiers: [.control, .shift])),
    ("Release+Shift_L", KeyEvent(Keysym.shiftL, modifiers: .release)),
    ("F12", KeyEvent(Keysym.function(12))),
    ("KP_5", KeyEvent(Keysym.keypad(5))),
    ("Shift++", KeyEvent(0x2b, modifiers: .shift)),
])
func parsesKeyNames(name: String, key: KeyEvent) {
    #expect(KeyEvent(name: name) == key)
}

@Test(arguments: ["", "Hyper+a", "nosuchkey", "ab", "Shift+"])
func rejectsUnknownNames(name: String) {
    #expect(KeyEvent(name: name) == nil)
}

@Test(arguments: ["a", "space", "Return", "Control+Shift+a", "Release+Shift_L", "Page_Up"])
func descriptionRoundTrips(name: String) throws {
    let key = try #require(KeyEvent(name: name))
    #expect(key.description == name)
    #expect(KeyEvent(name: key.description) == key)
}

@Test func nonLatinCharactersUseUnicodeKeysyms() {
    #expect(Keysym.character("é") == 0xe9)
    #expect(Keysym.character("中") == 0x0100_4e2d)
}
