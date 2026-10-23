import Foundation
import ScribeConfig
import Testing

struct PatchRenderingTests {
    /// The patch an empty file gets for one entry.
    private func rendered(_ key: String, _ value: ConfigNode) throws -> String {
        var editor = try CustomPatchEditor(text: "")
        editor.set(key, to: value)
        return editor.text
    }

    @Test(arguments: [
        ("rime_ice", "rime_ice"),
        ("Control+grave", "Control+grave"),
        ("mode/a", "mode/a"),
        ("lua_translator@date_translator", "lua_translator@date_translator"),
        ("0xFFFFFF", "0xFFFFFF"),
        ("5", "5"),
        ("1.5", "1.5"),
        ("true", "true"),
        ("_private", "_private"),
        ("null", "\"null\""),
        ("Null", "\"Null\""),
        ("NULL", "\"NULL\""),
        ("~", "\"~\""),
        ("", "\"\""),
        ("#comment", "\"#comment\""),
        ("a: b", "\"a: b\""),
        ("a #b", "\"a #b\""),
        (" leading", "\" leading\""),
        ("trailing ", "\"trailing \""),
        ("-1", "\"-1\""),
        ("- item", "\"- item\""),
        ("[x", "\"[x\""),
        ("{x", "\"{x\""),
        ("*alias", "\"*alias\""),
        ("&anchor", "\"&anchor\""),
        ("!tag", "\"!tag\""),
        ("中文", "\"中文\""),
        ("〔方案选单〕", "\"〔方案选单〕\""),
        ("say \"hi\" \\ bye", "\"say \\\"hi\\\" \\\\ bye\""),
        ("line\nbreak\ttab\rreturn", "\"line\\nbreak\\ttab\\rreturn\""),
        ("bell\u{7}", "\"bell\\x07\""),
        ("next\u{85}line", "\"next\\u0085line\""),
    ])
    func quotesScalarsWhenNeeded(value: String, written: String) throws {
        #expect(try rendered("key", .scalar(value)) == "patch:\n  key: \(written)\n")
    }

    @Test func quotesNewKeysTheSameWay() throws {
        #expect(try rendered("menu/page_size", 5) == "patch:\n  menu/page_size: 5\n")
        #expect(try rendered("schema_list/+", []) == "patch:\n  schema_list/+: []\n")
        #expect(try rendered("a b", 1) == "patch:\n  \"a b\": 1\n")
        #expect(try rendered("style/中文", 1) == "patch:\n  \"style/中文\": 1\n")
        #expect(try rendered("", 1) == "patch:\n  \"\": 1\n")
    }

    @Test func writesNullsAndEmptyCollectionsInline() throws {
        #expect(try rendered("a", nil) == "patch:\n  a: ~\n")
        #expect(try rendered("a", []) == "patch:\n  a: []\n")
        #expect(try rendered("a", [:]) == "patch:\n  a: {}\n")
        #expect(try rendered("a", [nil, [], [:], "x"]) == """
            patch:
              a:
                - ~
                - []
                - {}
                - x

            """)
        #expect(try rendered("a", ["empty": [:], "list": [], "none": nil]) == """
            patch:
              a:
                empty: {}
                list: []
                none: ~

            """)
    }

    @Test func writesListsOfMapsInBlockStyle() throws {
        #expect(try rendered("schema_list", [["schema": "rime_ice"], ["schema": "luna_pinyin", "case": ["mode/a", "mode/b"]]]) == """
            patch:
              schema_list:
                - schema: rime_ice
                - case:
                    - mode/a
                    - mode/b
                  schema: luna_pinyin

            """)
        #expect(try rendered("key_binder/bindings", [["when": "has_menu", "accept": "minus", "send": "Page_Up"]]) == """
            patch:
              key_binder/bindings:
                - accept: minus
                  send: Page_Up
                  when: has_menu

            """)
    }

    @Test func writesNestedListsAndMaps() throws {
        #expect(try rendered("a", [["x", "y"], "z", [["k": "v"]]]) == """
            patch:
              a:
                - - x
                  - y
                - z
                - - k: v

            """)
        #expect(try rendered("ascii_composer/switch_key", ["Shift_L": "commit_code", "Caps_Lock": "clear", "Control_L": "noop"]) == """
            patch:
              ascii_composer/switch_key:
                Caps_Lock: clear
                Control_L: noop
                Shift_L: commit_code

            """)
        #expect(try rendered("a", ["outer": ["inner": ["deep": "1"]]]) == """
            patch:
              a:
                outer:
                  inner:
                    deep: 1

            """)
    }

    @Test func sortsMapKeysByUTF8LikeLibrime() throws {
        #expect(try rendered("a", ["中": 1, "b": 2, "B": 3, "_": 4, "a1": 5, "a": 6]) == """
            patch:
              a:
                B: 3
                _: 4
                a: 6
                a1: 5
                b: 2
                "中": 1

            """)
    }
}
