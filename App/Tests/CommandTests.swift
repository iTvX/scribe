import ScribeCore
import Testing

private let hans = "io.github.itvx.inputmethod.Scribe.Hans"
private let hant = "io.github.itvx.inputmethod.Scribe.Hant"

@Test(arguments: [
    ([String](), Command.runServer),
    (["--install"], .install),
    (["--register-input-source"], .install),
    (["--quit"], .quit),
    (["--reload"], .reload),
    (["--sync"], .sync),
    (["--build"], .build),
    (["--ascii"], .ascii(true)),
    (["--nascii"], .ascii(false)),
    (["--getascii"], .getASCII),
    (["--self-test"], .selfTest),
    (["--help"], .help),
    (["--enable-input-source"], .enableInputSource([])),
    (["--enable-input-source", hant, hans], .enableInputSource([.hant, .hans])),
    (["--disable-input-source"], .disableInputSource([])),
    (["--disable-input-source", hans], .disableInputSource([.hans])),
    (["--select-input-source"], .selectInputSource(nil)),
    (["--select-input-source", hant], .selectInputSource(.hant)),
])
func parsesOptions(arguments: [String], command: Command) {
    #expect(Command(arguments: ["Scribe"] + arguments) == command)
}

@Test func parsesReplayWithItsFile() {
    #expect(Command(arguments: ["Scribe", "--replay", "typing.replay"]) == .replay(file: "typing.replay"))
}

@Test(arguments: [
    ["--bogus"], ["reload"], ["--reload", "extra"], ["-x"], ["--replay"], ["--replay", "a", "b"],
    ["--enable-input-source", "com.apple.keylayout.ABC"], ["--select-input-source", hans, hant],
    ["--select-input-source", "Hans"],
])
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
    for option in [
        "--install", "--register-input-source", "--enable-input-source", "--disable-input-source",
        "--select-input-source", "--quit", "--reload", "--sync", "--build", "--ascii", "--nascii",
        "--getascii", "--self-test", "--replay", "--help",
    ] {
        #expect(Command.usage.contains(option), "\(option)")
    }
}
