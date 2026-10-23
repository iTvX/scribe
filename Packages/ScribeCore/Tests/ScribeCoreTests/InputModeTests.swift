import ScribeCore
import Testing

private let bundleIdentifier = "io.github.itvx.inputmethod.Scribe"

@Test func inputSourceIDs() {
    #expect(InputMode.hans.inputSourceID(bundleIdentifier: bundleIdentifier) == "io.github.itvx.inputmethod.Scribe.Hans")
    #expect(InputMode.hant.inputSourceID(bundleIdentifier: bundleIdentifier) == "io.github.itvx.inputmethod.Scribe.Hant")
}

@Test(arguments: InputMode.allCases)
func inputSourceIDRoundTrips(mode: InputMode) {
    let id = mode.inputSourceID(bundleIdentifier: bundleIdentifier)
    #expect(InputMode(inputSourceID: id, bundleIdentifier: bundleIdentifier) == mode)
}

@Test func otherInputSourcesAreRejected() {
    #expect(InputMode(inputSourceID: "im.rime.inputmethod.Squirrel.Hans", bundleIdentifier: bundleIdentifier) == nil)
    #expect(InputMode(inputSourceID: "io.github.itvx.inputmethod.Scribe", bundleIdentifier: bundleIdentifier) == nil)
}
