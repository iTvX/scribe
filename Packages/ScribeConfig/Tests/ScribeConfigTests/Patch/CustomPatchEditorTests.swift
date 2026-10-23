import Foundation
@testable import ScribeConfig
import Testing

/// A rime-ice style default.custom.yaml: header comment, an include, a
/// compact schema list with a commented-out schema, quoted keys, a flow map
/// and a trailing section of commented-out settings.
struct CustomPatchEditorTests {
    static let defaultCustom = """
        # default.custom.yaml
        # 雾凇拼音的全局设置，部署后生效。

        patch:
          __include: rime_ice_suggestion:/
          # 方案列表
          schema_list:
          - schema: rime_ice
          # - schema: luna_pinyin
          - schema: double_pinyin_flypy
          "menu/page_size": 7  # 候选个数
          'switcher/hotkeys':
            - Control+grave
          menu: {page_size: 5}
          key_binder/bindings/+:
            - { when: has_menu, accept: minus, send: Page_Up }

        # 以下是备用设置
        #  ascii_composer/switch_key/Shift_L: commit_code

        """

    @Test func listsKeysAsLibrimeReadsThem() throws {
        let editor = try CustomPatchEditor(text: Self.defaultCustom)
        #expect(editor.keys == ["__include", "schema_list", "menu/page_size", "switcher/hotkeys", "menu", "key_binder/bindings/+"])
        #expect(editor.text == Self.defaultCustom)
    }

    @Test func setReplacesACompactSequenceAndKeepsItsComments() throws {
        try expectEdit(.set("schema_list", [["schema": "rime_ice"], ["schema": "luna_pinyin", "case": ["mode/a"]]]),
                       in: Self.defaultCustom, gives: """
            # default.custom.yaml
            # 雾凇拼音的全局设置，部署后生效。

            patch:
              __include: rime_ice_suggestion:/
              # 方案列表
              schema_list:
                - schema: rime_ice
                - case:
                    - mode/a
                  schema: luna_pinyin
                # - schema: luna_pinyin
              "menu/page_size": 7  # 候选个数
              'switcher/hotkeys':
                - Control+grave
              menu: {page_size: 5}
              key_binder/bindings/+:
                - { when: has_menu, accept: minus, send: Page_Up }

            # 以下是备用设置
            #  ascii_composer/switch_key/Shift_L: commit_code

            """)
    }

    @Test func setKeepsTheKeySpellingAndTrailingComment() throws {
        try expectEdit(.set("menu/page_size", 9), in: Self.defaultCustom, gives: Self.defaultCustom.replacingOccurrences(
            of: "  \"menu/page_size\": 7  # 候选个数\n", with: "  \"menu/page_size\": 9  # 候选个数\n"))
        try expectEdit(.set("switcher/hotkeys", ["Control+grave", "F4"]), in: Self.defaultCustom,
                       gives: Self.defaultCustom.replacingOccurrences(
                           of: "    - Control+grave\n", with: "    - Control+grave\n    - F4\n"))
    }

    @Test func setOnANewKeyAppendsBeforeTrailingComments() throws {
        try expectEdit(.set("ascii_composer/switch_key", ["Shift_L": "commit_code", "Caps_Lock": "clear"]),
                       in: Self.defaultCustom, gives: Self.defaultCustom.replacingOccurrences(
                           of: "    - { when: has_menu, accept: minus, send: Page_Up }\n",
                           with: """
                               - { when: has_menu, accept: minus, send: Page_Up }
                             ascii_composer/switch_key:
                               Caps_Lock: clear
                               Shift_L: commit_code

                           """))
    }

    @Test func removeDeletesTheSpanAndKeepsItsComments() throws {
        try expectEdit(.remove("switcher/hotkeys"), in: Self.defaultCustom, gives: Self.defaultCustom.replacingOccurrences(
            of: "  'switcher/hotkeys':\n    - Control+grave\n", with: ""))
        try expectEdit(.remove("schema_list"), in: Self.defaultCustom, gives: Self.defaultCustom.replacingOccurrences(
            of: "  schema_list:\n  - schema: rime_ice\n  # - schema: luna_pinyin\n  - schema: double_pinyin_flypy\n",
            with: "  # - schema: luna_pinyin\n"))
        try expectEdit(.remove("style/color_scheme"), in: Self.defaultCustom, gives: Self.defaultCustom)
    }

    @Test func removeDescendantsLeavesTheAncestor() throws {
        try expectEdit(.removeDescendants("menu"), in: Self.defaultCustom, gives: Self.defaultCustom.replacingOccurrences(
            of: "  \"menu/page_size\": 7  # 候选个数\n", with: ""))
        try expectEdit(.removeDescendants("key_binder/bindings"), in: Self.defaultCustom,
                       gives: Self.defaultCustom.replacingOccurrences(
                           of: "  key_binder/bindings/+:\n    - { when: has_menu, accept: minus, send: Page_Up }\n", with: ""))
        try expectEdit(.removeDescendants("schema_list"), in: Self.defaultCustom, gives: Self.defaultCustom)
    }

    @Test func opaqueEntriesChangeOnlyByTheirExactKey() throws {
        let text = """
            patch:
              __include: rime_ice_suggestion:/
              schema_list/+:
                - schema: wubi86
              schema_list/@0: {schema: luna_pinyin}
              schema_list:
                - schema: rime_ice

            """
        var editor = try CustomPatchEditor(text: text)
        editor.set("schema_list", to: [["schema": "rime_ice"], ["schema": "double_pinyin"]])
        #expect(editor.keys == ["__include", "schema_list/+", "schema_list/@0", "schema_list"])
        let removedDescendants = editor.removeDescendants(of: "schema_list")
        #expect(removedDescendants == ["schema_list/+", "schema_list/@0"])
        editor.set("__include", to: "rime_ice_suggestion:/patch")
        #expect(editor.text == """
            patch:
              __include: "rime_ice_suggestion:/patch"
              schema_list:
                - schema: rime_ice
                - schema: double_pinyin

            """)
    }

    @Test func commentsInsideAValueSurviveRepeatedSets() throws {
        var editor = try CustomPatchEditor(text: Self.defaultCustom)
        editor.set("schema_list", to: [["schema": "rime_ice"]])
        let once = editor.text
        editor.set("schema_list", to: [["schema": "rime_ice"]])
        #expect(editor.text == once)
        editor.set("schema_list", to: [["schema": "luna_pinyin"], ["schema": "rime_ice"]])
        editor.set("schema_list", to: [["schema": "rime_ice"]])
        #expect(editor.text == once)
        #expect(once.components(separatedBy: "# - schema: luna_pinyin").count == 2)
        #expect(once.contains("""
              schema_list:
                - schema: rime_ice
                # - schema: luna_pinyin
              "menu/page_size": 7
            """))
    }

    @Test func editsChain() throws {
        var editor = try CustomPatchEditor(text: Self.defaultCustom)
        editor.set("menu/page_size", to: 9)
        editor.set("ascii_composer/switch_key", to: ["Caps_Lock": "clear", "Shift_L": "commit_code"])
        let removed = editor.remove("switcher/hotkeys")
        let removedDescendants = editor.removeDescendants(of: "key_binder/bindings")
        #expect(removed)
        #expect(removedDescendants == ["key_binder/bindings/+"])
        #expect(editor.keys == ["__include", "schema_list", "menu/page_size", "menu", "ascii_composer/switch_key"])
        #expect(editor.text == """
            # default.custom.yaml
            # 雾凇拼音的全局设置，部署后生效。

            patch:
              __include: rime_ice_suggestion:/
              # 方案列表
              schema_list:
              - schema: rime_ice
              # - schema: luna_pinyin
              - schema: double_pinyin_flypy
              "menu/page_size": 9  # 候选个数
              menu: {page_size: 5}
              ascii_composer/switch_key:
                Caps_Lock: clear
                Shift_L: commit_code

            # 以下是备用设置
            #  ascii_composer/switch_key/Shift_L: commit_code

            """)
        #expect(try CustomPatchEditor(text: editor.text) == editor)
    }
}
