import ScribeCore
import Testing

@Test func parsesKeysAndExpectations() throws {
    let script = try ReplayScript("""
        # A comment
        @engines fake

        n
        i      => marked "ni"; candidates "你" "泥"; highlighted 0; page 0
        space  => commit "你"; candidates none; handled   # trailing comment
        Return => commit none; unhandled
        """)
    #expect(script.engines == ["fake"])
    #expect(script.steps.map(\.input) == [.key(KeyEvent(0x6e)), .key(KeyEvent(0x69)), .key(KeyEvent(Keysym.space)), .key(KeyEvent(Keysym.return))])
    #expect(script.steps.map(\.line) == [4, 5, 6, 7])
    #expect(script.steps[0].expectations.isEmpty)
    #expect(script.steps[1].expectations == [.marked("ni"), .candidates(["你", "泥"]), .highlighted(0), .page(0)])
    #expect(script.steps[2].expectations == [.commit("你"), .candidates(nil), .handled(true)])
    #expect(script.steps[3].expectations == [.commit(nil), .handled(false)])
}

@Test func quotedTextMayContainSeparators() throws {
    let script = try ReplayScript(#"a => marked "a # b; c""#)
    #expect(script.steps[0].expectations == [.marked("a # b; c")])
}

@Test func reportsTheLineOfAnError() {
    #expect(throws: ReplayScript.ParseError(line: 2, message: "unknown key \"nosuchkey\"")) {
        try ReplayScript("a\nnosuchkey")
    }
    #expect(throws: ReplayScript.ParseError(line: 1, message: "unknown expectation \"bogus 1\"")) {
        try ReplayScript("a => bogus 1")
    }
}
