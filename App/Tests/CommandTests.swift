import Testing

@Test(arguments: [
    ([String](), Command.runServer),
    (["--install"], .install),
    (["--quit"], .quit),
    (["--reload"], .reload),
    (["--sync"], .sync),
    (["--self-test"], .selfTest),
    (["--help"], .help),
])
func parsesOptions(arguments: [String], command: Command) {
    #expect(Command(arguments: ["Scribe"] + arguments) == command)
}

@Test(arguments: [["--bogus"], ["reload"], ["--reload", "extra"], ["-x"]])
func rejectsUnknownArguments(arguments: [String]) {
    #expect(Command(arguments: ["Scribe"] + arguments) == .invalid(arguments.joined(separator: " ")))
}

/// Arguments Cocoa adds when launching an app never stop the server from
/// starting.
@Test(arguments: [["-psn_0_12345"], ["-NSDocumentRevisionsDebugMode", "YES"], ["-AppleLanguages", "(en)"]])
func ignoresLaunchArguments(arguments: [String]) {
    #expect(Command(arguments: ["Scribe"] + arguments) == .runServer)
}

@Test func usageNamesEveryOption() {
    for option in ["--install", "--quit", "--reload", "--sync", "--self-test", "--help"] {
        #expect(Command.usage.contains(option))
    }
}
