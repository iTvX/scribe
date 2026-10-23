import ScribeCore
import Testing

@Test func parsesActionSteps() throws {
    let script = try ReplayScript("""
        @status-message long
        !commit-composition
        !select 2
        !page down
        !page up
        !caret start
        !caret end
        !tick
        @notifications never
        !notify option !ascii_mode => status none
        !notify schema luna/朙月拼音 => status "朙月拼音"
        a => caret 1
        """)
    #expect(script.steps.map(\.input) == [
        .action(.commitComposition), .action(.select(2)), .action(.page(.down)), .action(.page(.up)),
        .action(.caret(.towardStart)), .action(.caret(.towardEnd)), .action(.tick),
        .action(.notify(type: "option", value: "!ascii_mode")), .action(.notify(type: "schema", value: "luna/朙月拼音")),
        .key(KeyEvent(0x61)),
    ])
    #expect(script.steps[0].messageType == .long)
    #expect(script.steps[0].notifications == .appropriate)
    #expect(script.steps[7].notifications == .never)
    #expect(script.steps[7].expectations == [.status(nil)])
    #expect(script.steps[8].expectations == [.status("朙月拼音")])
    #expect(script.steps[9].expectations == [.caret(1)])
}

@Test func rejectsUnknownActions() {
    #expect(throws: ReplayScript.ParseError.self) { try ReplayScript("!bogus") }
    #expect(throws: ReplayScript.ParseError.self) { try ReplayScript("!page sideways") }
    #expect(throws: ReplayScript.ParseError.self) { try ReplayScript("@status-message loud") }
}
