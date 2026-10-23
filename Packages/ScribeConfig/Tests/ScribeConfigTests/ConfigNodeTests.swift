import ScribeConfig
import Testing

@Suite("ConfigNode paths")
struct ConfigNodePathTests {
    let config: ConfigNode = [
        "style": ["color_scheme": "aqua", "font_point": 16],
        "list": ["a", "b", "c"],
        "empty_list": [],
        "": "empty key",
        "@": "at sign",
        "@-1": "not an index",
        "nested": [["name": "first"], ["name": "second"]],
    ]

    @Test(arguments: [
        ("style/color_scheme", "aqua"),
        ("/style/color_scheme", "aqua"),
        ("///style/color_scheme", "aqua"),
        ("nested/@1/name", "second"),
        ("nested/@last/name", "second"),
        ("@", "at sign"),
        ("@-1", "not an index"),
    ])
    func mapKeysAndListItems(path: String, expected: String) {
        #expect(config.string(at: path) == expected)
    }

    @Test func emptyPathAndSlashAreTheRoot() {
        let keys = ["", "@", "@-1", "empty_list", "list", "nested", "style"]
        #expect(config.mapKeys(at: "") == keys)
        #expect(config.mapKeys(at: "/") == keys)
        #expect(ConfigNode.scalar("x").string(at: "") == "x")
    }

    @Test func emptySegmentsAreEmptyKeys() {
        // "//" is not the root: the leading slashes are trimmed and "" remains.
        #expect(config.string(at: "//") == "empty key")
        #expect(config.string(at: "style//color_scheme") == nil)
        #expect(config.string(at: "style/color_scheme/") == nil)
        #expect(ConfigNode.map(["a": ["": "x"]]).string(at: "a/") == "x")
    }

    @Test(arguments: [
        ("list/@0", "a"),
        ("list/@1", "b"),
        ("list/@2", "c"),
        ("list/@last", "c"),
        ("list/@1x", "b"),
        ("list/@abc", "a"),
        ("list/@lastly", "c"),
        ("list/@before 1", "b"),
        ("list/@before last", "c"),
        ("list/@after 0", "b"),
        ("list/@after1", "c"),
        ("list/@4294967297", "b"),
    ] as [(String, String)])
    func listReferences(path: String, expected: String) {
        #expect(config.string(at: path) == expected)
    }

    @Test(arguments: [
        "list/@3",
        "list/@next",
        "list/@after last",
        "list/@after 2",
        "list/@before -1",
        "empty_list/@0",
        "empty_list/@last",
        "style/@0",
        "list/0",
        "missing/@0",
    ])
    func unresolvedListReferences(path: String) {
        #expect(config.string(at: path) == nil)
    }

    @Test func listCountOfEmptyList() {
        #expect(config.listCount(at: "empty_list") == 0)
        #expect(config.listCount(at: "list") == 3)
    }

    @Test func keysCompareByteForByte() {
        let decomposed = "e\u{301}"
        let config: ConfigNode = [decomposed: "decomposed"]
        #expect(config.string(at: decomposed) == "decomposed")
        #expect(config.string(at: "\u{E9}") == nil)
    }
}

@Suite("ConfigNode getters")
struct ConfigNodeGetterTests {
    @Test func stringIsScalarOnly() {
        let config: ConfigNode = ["scalar": "x", "empty": "", "map": ["a": 1], "list": [1], "null": nil]
        #expect(config.string(at: "scalar") == "x")
        #expect(config.string(at: "empty") == "")
        #expect(config.string(at: "map") == nil)
        #expect(config.string(at: "list") == nil)
        #expect(config.string(at: "null") == nil)
        #expect(config.string(at: "missing") == nil)
    }

    @Test(arguments: [
        ("true", true), ("TRUE", true), ("True", true), ("false", false), ("FaLsE", false),
    ])
    func bool(value: String, expected: Bool) {
        #expect(ConfigNode.scalar(value).bool(at: "") == expected)
    }

    @Test(arguments: ["", "yes", "no", "1", "0", " true", "true ", "truex", "\u{130}"])
    func notBool(value: String) {
        #expect(ConfigNode.scalar(value).bool(at: "") == nil)
    }

    @Test(arguments: [
        ("12", 12),
        ("12abc", 12),
        ("1.5", 1),
        (" 8", 8),
        ("\t\n8", 8),
        ("-3", -3),
        ("+3", 3),
        ("007", 7),
        ("2147483647", 2_147_483_647),
        ("-2147483648", -2_147_483_648),
        ("0x10", 16),
        ("0x1F", 31),
        ("0x1f", 31),
        ("0x7FFFFFFF", 2_147_483_647),
        ("0xFFFFFFFF", -1),
        ("0x100000010", 16),
        ("0x1G", 0),
        ("0x", 0),
        ("0xZ", 0),
        ("0X10", 0),
        ("0x10 ", 0),
    ])
    func int(value: String, expected: Int) {
        #expect(ConfigNode.scalar(value).int(at: "") == expected)
    }

    @Test(arguments: ["", " ", "abc", "x1", "2147483648", "-2147483649", "99999999999999999999"])
    func notInt(value: String) {
        #expect(ConfigNode.scalar(value).int(at: "") == nil)
    }

    @Test(arguments: [
        ("16", 16.0),
        ("16px", 16.0),
        ("1.5", 1.5),
        (" 8", 8.0),
        ("-0.5", -0.5),
        ("1e3", 1000.0),
        ("0x10", 16.0),
        ("inf", Double.infinity),
        ("-INFINITY", -Double.infinity),
        (".5", 0.5),
    ])
    func double(value: String, expected: Double) {
        #expect(ConfigNode.scalar(value).double(at: "") == expected)
    }

    @Test func nanIsADouble() {
        #expect(ConfigNode.scalar("nan").double(at: "")?.isNaN == true)
    }

    @Test(arguments: ["", " ", "abc", "px16", "1e400", "-1e400"])
    func notDouble(value: String) {
        #expect(ConfigNode.scalar(value).double(at: "") == nil)
    }

    @Test func mapKeysAreSortedByUTF8Bytes() {
        let config: ConfigNode = ["a": 1, "B": 2, "_": 3, "e\u{301}": 4, "f": 5, "null": nil]
        // Bytes: "B" 0x42 < "_" 0x5F < "a" 0x61 < "e\u{301}" 0x65 < "f" 0x66 < "null" 0x6E.
        #expect(config.mapKeys(at: "") == ["B", "_", "a", "e\u{301}", "f", "null"])
    }

    @Test func mapKeysAndListCountNeedTheRightType() {
        let config: ConfigNode = ["map": ["a": 1], "list": [1, nil, 3], "scalar": "x", "null": nil]
        #expect(config.mapKeys(at: "map") == ["a"])
        #expect(config.mapKeys(at: "list") == nil)
        #expect(config.mapKeys(at: "scalar") == nil)
        #expect(config.mapKeys(at: "null") == nil)
        #expect(config.listCount(at: "list") == 3)
        #expect(config.listCount(at: "map") == nil)
        #expect(config.listCount(at: "scalar") == nil)
        #expect(config.listCount(at: "null") == nil)
    }

    @Test func nullValues() {
        let config: ConfigNode = ["null": nil, "list": [nil, "x"]]
        #expect(config.mapKeys(at: "") == ["list", "null"])
        #expect(config.string(at: "null") == nil)
        #expect(config.bool(at: "null") == nil)
        #expect(config.int(at: "null") == nil)
        #expect(config.double(at: "null") == nil)
        #expect(config.string(at: "null/x") == nil)
        #expect(config.string(at: "list/@0") == nil)
        #expect(config.string(at: "list/@1") == "x")
        #expect(ConfigNode.null.mapKeys(at: "") == nil)
    }

    @Test func literals() {
        let config: ConfigNode = ["bool": true, "int": 16, "negative": -2, "double": 1.5, "string": "x", "null": nil]
        #expect(config == .map([
            "bool": .scalar("true"),
            "int": .scalar("16"),
            "negative": .scalar("-2"),
            "double": .scalar("1.5"),
            "string": .scalar("x"),
            "null": .null,
        ]))
        let list: ConfigNode = [false, 0.25]
        #expect(list == .list([.scalar("false"), .scalar("0.25")]))
    }
}
