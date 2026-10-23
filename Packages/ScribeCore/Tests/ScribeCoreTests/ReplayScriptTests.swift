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

@Test func parsesTheStyleAndTheClientApp() throws {
    let script = try ReplayScript("""
        @style inline_preedit false
        @app com.apple.Terminal ascii_mode=true no_inline=true
        n   => panel-preedit "n‸"
        @style linear true
        i   => panel-preedit none
        """)
    #expect(script.steps[0].presentation == InputSession.Presentation(inlinePreedit: false))
    #expect(script.steps[0].app == ReplayScript.App(bundleID: "com.apple.Terminal", options: ["ascii_mode": true, "no_inline": true]))
    #expect(script.steps[0].expectations == [.panelPreedit("n‸")])
    #expect(script.steps[1].presentation == InputSession.Presentation(inlinePreedit: false, linear: true))
    #expect(script.steps[1].app == nil)
    #expect(script.steps[1].expectations == [.panelPreedit(nil)])
}

@Test func rejectsUnknownStyles() {
    #expect(throws: ReplayScript.ParseError(line: 1, message: "expected \"@style inline_preedit|inline_candidate|linear|vertical true|false\"")) {
        try ReplayScript("@style color_scheme true")
    }
    #expect(throws: ReplayScript.ParseError(line: 1, message: "expected \"@app BUNDLE_ID [OPTION=true|false ...]\"")) {
        try ReplayScript("@app com.apple.Terminal ascii_mode")
    }
}

@Test func parsesCommentMarks() throws {
    let script = try ReplayScript("""
        n => accent-comments 1 3; warning-comments none
        """)
    #expect(script.steps[0].expectations == [.accentComments([1, 3]), .warningComments([])])
}
