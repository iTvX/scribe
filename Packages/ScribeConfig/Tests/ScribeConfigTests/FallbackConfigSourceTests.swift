import ScribeConfig
import Testing

@Suite("FallbackConfigSource")
struct FallbackConfigSourceTests {
    let source = FallbackConfigSource(
        primary: ConfigNode.map([
            "string": "primary",
            "bool": "maybe",
            "true": true,
            "int": "x",
            "double": "abc",
            "point": 20,
            "color": "red",
            "good_color": "0x000000",
            "map": ["a": 1],
            "list": [1],
            "shape": ["a": 1],
        ]),
        fallback: ConfigNode.map([
            "string": "fallback",
            "bool": false,
            "true": false,
            "int": 7,
            "double": 1.5,
            "point": 16,
            "color": "0xFFFFFF",
            "good_color": "0xFFFFFF",
            "only_fallback": "here",
            "map": ["b": 2],
            "list": [1, 2],
            "shape": "scalar",
        ])
    )

    @Test func primaryWins() {
        #expect(source.string(at: "string") == "primary")
        #expect(source.bool(at: "true") == true)
        #expect(source.double(at: "point") == 20)
        #expect(source.mapKeys(at: "map") == ["a"])
        #expect(source.listCount(at: "list") == 1)
    }

    @Test func unparsablePrimaryFallsBack() {
        #expect(source.bool(at: "bool") == false)
        #expect(source.int(at: "int") == 7)
        #expect(source.double(at: "double") == 1.5)
    }

    @Test func parsedFallsBackWhenThePrimaryDoesNotParse() {
        let parse = { (value: String) in RGBAColor(squirrel: value, colorSpace: .sRGB) }
        #expect(source.parsed(at: "color", parse)?.hex == "#FFFFFFFF")
        #expect(source.parsed(at: "good_color", parse)?.hex == "#000000FF")
        #expect(source.parsed(at: "missing", parse) == nil)
    }

    @Test func missingKeysFallBack() {
        #expect(source.string(at: "only_fallback") == "here")
        #expect(source.string(at: "missing") == nil)
    }

    @Test func eachGetterFallsBackOnItsOwnType() {
        #expect(source.string(at: "shape") == "scalar")
        #expect(source.mapKeys(at: "shape") == ["a"])
    }
}
