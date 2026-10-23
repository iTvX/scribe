import ScribeConfig
import Testing

@Suite("Scribe compatibility")
struct ScribeCompatibilityTests {
    @Test(arguments: [
        (ConfigNode.null, false),
        (true, true),
        ("True", true),
        (false, false),
        ("yes", false),
        (["nested": true], false),
    ] as [(ConfigNode, Bool)])
    func reportAsSquirrel(value: ConfigNode, expected: Bool) {
        let compatibility = ScribeCompatibility(scribe: ConfigNode.map(["compatibility": ["report_as_squirrel": value]]))
        #expect(compatibility.reportsAsSquirrel == expected)
    }

    @Test func absentSection() {
        #expect(ScribeCompatibility(scribe: ConfigNode.map([:])) == ScribeCompatibility())
    }

    @Test func distributionNames() {
        let scribe = ScribeCompatibility(reportsAsSquirrel: false)
        #expect(scribe.distributionCodeName == "Scribe")
        #expect(scribe.distributionName == "Scribe")
        let squirrel = ScribeCompatibility(reportsAsSquirrel: true)
        #expect(squirrel.distributionCodeName == "Squirrel")
        #expect(squirrel.distributionName == "鼠鬚管")
    }
}
