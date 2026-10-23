import Foundation
@testable import ScribeConfig
import Testing

/// Each layout gets set on an existing key, set on a new key, remove and
/// removeDescendants.
struct CustomPatchLayoutTests {
    @Test func crlfLineEndings() throws {
        let text = "patch:\r\n  menu/page_size: 5\r\n  # 备注\r\n  switcher/caption: 〔方案选单〕\r\n  menu/alternative_select_keys: \"123456789\"\r\n"
        try expectEdit(.set("menu/page_size", 9), in: text, gives: text.replacingOccurrences(of: "page_size: 5", with: "page_size: 9"))
        try expectEdit(.set("style/inline_preedit", true), in: text, gives: text + "  style/inline_preedit: true\r\n")
        try expectEdit(.set("switcher/hotkeys", ["F4"]), in: text, gives: text + "  switcher/hotkeys:\r\n    - F4\r\n")
        try expectEdit(.remove("switcher/caption"), in: text, gives: text.replacingOccurrences(
            of: "  switcher/caption: 〔方案选单〕\r\n", with: ""))
        try expectEdit(.removeDescendants("menu"), in: text,
                       gives: "patch:\r\n  # 备注\r\n  switcher/caption: 〔方案选单〕\r\n")
    }

    @Test func byteOrderMarkAndDocumentStart() throws {
        let text = "\u{FEFF}---\n# 中书\npatch:\n  menu/page_size: 5\n"
        try expectEdit(.set("menu/page_size", 6), in: text, gives: "\u{FEFF}---\n# 中书\npatch:\n  menu/page_size: 6\n")
        try expectEdit(.set("menu", ["page_size": 6]), in: text,
                       gives: "\u{FEFF}---\n# 中书\npatch:\n  menu/page_size: 5\n  menu:\n    page_size: 6\n")
        try expectEdit(.remove("menu/page_size"), in: text, gives: "\u{FEFF}---\n# 中书\npatch:\n")
        try expectEdit(.removeDescendants("menu"), in: text, gives: "\u{FEFF}---\n# 中书\npatch:\n")
    }

    @Test func noFinalNewline() throws {
        let text = "patch:\n  menu/page_size: 5\n  switcher/hotkeys:\n    - F4"
        try expectEdit(.set("switcher/hotkeys", ["F4", "Control+grave"]), in: text,
                       gives: "patch:\n  menu/page_size: 5\n  switcher/hotkeys:\n    - F4\n    - Control+grave")
        try expectEdit(.set("style/color_scheme", "aqua"), in: text, gives: text + "\n  style/color_scheme: aqua")
        try expectEdit(.remove("switcher/hotkeys"), in: text, gives: "patch:\n  menu/page_size: 5")
        try expectEdit(.removeDescendants("switcher"), in: text, gives: "patch:\n  menu/page_size: 5")
        try expectEdit(.set("menu/page_size", 9), in: "patch:", gives: "patch:\n  menu/page_size: 9")
        try expectEdit(.set("menu/page_size", 9), in: "# 注释", gives: "# 注释\npatch:\n  menu/page_size: 9")
    }

    @Test func emptyText() throws {
        try expectEdit(.set("menu/page_size", 9), in: "", gives: "patch:\n  menu/page_size: 9\n")
        try expectEdit(.remove("menu/page_size"), in: "", gives: "")
        try expectEdit(.removeDescendants("menu"), in: "", gives: "")
        #expect(try CustomPatchEditor(text: "").keys.isEmpty)
    }

    @Test func commentsOnly() throws {
        let text = "# 中书的补丁\n# patch:\n#   menu/page_size: 9\n\n"
        try expectEdit(.set("menu/page_size", 9), in: text, gives: text + "patch:\n  menu/page_size: 9\n")
        try expectEdit(.remove("menu/page_size"), in: text, gives: text)
        try expectEdit(.removeDescendants("menu"), in: text, gives: text)
    }

    @Test func patchWithATrailingComment() throws {
        let text = "patch:  # 中书设置写的\n  menu/page_size: 5\n  menu/alternative_select_labels: [①, ②, ③]\n"
        try expectEdit(.set("menu/page_size", 3), in: text,
                       gives: "patch:  # 中书设置写的\n  menu/page_size: 3\n  menu/alternative_select_labels: [①, ②, ③]\n")
        try expectEdit(.set("menu/alternative_select_labels", ["一", "二", "三"]), in: text, gives: """
            patch:  # 中书设置写的
              menu/page_size: 5
              menu/alternative_select_labels:
                - "一"
                - "二"
                - "三"

            """)
        try expectEdit(.set("key_binder/select_first_character", "bracketleft"), in: text,
                       gives: text + "  key_binder/select_first_character: bracketleft\n")
        try expectEdit(.remove("menu/page_size"), in: text,
                       gives: "patch:  # 中书设置写的\n  menu/alternative_select_labels: [①, ②, ③]\n")
        try expectEdit(.removeDescendants("menu"), in: text, gives: "patch:  # 中书设置写的\n")
    }

    @Test func emptyPatch() throws {
        try expectEdit(.set("menu/page_size", 9), in: "patch:\n", gives: "patch:\n  menu/page_size: 9\n")
        // New entries go right after `patch:`, never after comments that may
        // belong to what follows.
        let commented = "patch:\n  # menu/page_size: 9\n\n# 以下不用\nother: 1\n"
        try expectEdit(.set("menu/page_size", 7), in: commented,
                       gives: "patch:\n  menu/page_size: 7\n  # menu/page_size: 9\n\n# 以下不用\nother: 1\n")
        try expectEdit(.remove("menu/page_size"), in: commented, gives: commented)
        try expectEdit(.removeDescendants("menu"), in: commented, gives: commented)
    }

    @Test func customizationBeforePatch() throws {
        let text = """
            customization:
              distribution_code_name: Weasel
              generator: "Weasel::UIStyleSettings"
              modified_time: "Thu Oct 23 09:30:00 2025"
            patch:
              "style/color_scheme": aqua
              "style/font_point": 14

            """
        try expectEdit(.set("style/color_scheme", "lost_temple"), in: text,
                       gives: text.replacingOccurrences(of: "\": aqua", with: "\": lost_temple"))
        try expectEdit(.set("style/horizontal", false), in: text,
                       gives: text.replacingOccurrences(of: "14\n", with: "14\n  style/horizontal: false\n"))
        try expectEdit(.remove("style/color_scheme"), in: text,
                       gives: text.replacingOccurrences(of: "  \"style/color_scheme\": aqua\n", with: ""))
        try expectEdit(.removeDescendants("style"), in: text, gives: text.replacingOccurrences(
            of: "  \"style/color_scheme\": aqua\n  \"style/font_point\": 14\n", with: ""))
    }

    @Test func customizationAfterPatch() throws {
        let text = """
            patch:
              schema_list:
                - schema: luna_pinyin
            customization:
              generator: "Rime::SwitcherSettings"
              modified_time: "Thu Oct 23 09:30:00 2025"

            """
        try expectEdit(.set("schema_list", [["schema": "rime_ice"]]), in: text,
                       gives: text.replacingOccurrences(of: "luna_pinyin", with: "rime_ice"))
        try expectEdit(.set("switcher/hotkeys", ["F4"]), in: text, gives: text.replacingOccurrences(
            of: "customization:", with: "  switcher/hotkeys:\n    - F4\ncustomization:"))
        try expectEdit(.remove("schema_list"), in: text,
                       gives: text.replacingOccurrences(of: "  schema_list:\n    - schema: luna_pinyin\n", with: ""))
        try expectEdit(.removeDescendants("schema_list"), in: text, gives: text)
        // With no patch at all, one goes at the end.
        let noPatch = "customization:\n  generator: \"Rime::SwitcherSettings\"\n"
        try expectEdit(.set("menu/page_size", 9), in: noPatch, gives: noPatch + "patch:\n  menu/page_size: 9\n")
    }

    @Test func compactSequencesUnderOtherTopLevelKeys() throws {
        let text = """
            __patch:
            - rime_ice_suggestion:/
            - key_bindings:/emacs_editing
              # 第二个补丁
            patch:
              menu/page_size: 5
            customization:
              list:
              - a

            """
        #expect(try CustomPatchEditor(text: text).keys == ["menu/page_size"])
        try expectEdit(.set("menu/page_size", 6), in: text, gives: text.replacingOccurrences(of: "size: 5", with: "size: 6"))
        try expectEdit(.set("switcher/hotkeys", ["F4"]), in: text, gives: text.replacingOccurrences(
            of: "  menu/page_size: 5\n", with: "  menu/page_size: 5\n  switcher/hotkeys:\n    - F4\n"))
        try expectEdit(.remove("menu/page_size"), in: text, gives: text.replacingOccurrences(of: "  menu/page_size: 5\n", with: ""))
        try expectEdit(.removeDescendants("menu"), in: text, gives: text.replacingOccurrences(of: "  menu/page_size: 5\n", with: ""))
    }

    @Test func fourSpaceIndentation() throws {
        let text = """
            patch:
                schema_list:
                    - schema: rime_ice
                menu/page_size: 5

            """
        try expectEdit(.set("schema_list", [["schema": "rime_ice", "case": ["a"]]]), in: text, gives: """
            patch:
                schema_list:
                    - case:
                          - a
                      schema: rime_ice
                menu/page_size: 5

            """)
        try expectEdit(.set("ascii_composer/switch_key", ["Shift_L": "commit_code"]), in: text, gives: text + """
                ascii_composer/switch_key:
                    Shift_L: commit_code

            """)
        try expectEdit(.remove("schema_list"), in: text, gives: "patch:\n    menu/page_size: 5\n")
        try expectEdit(.removeDescendants("menu"), in: text,
                       gives: "patch:\n    schema_list:\n        - schema: rime_ice\n")
    }

    @Test func blockScalarsAreValues() throws {
        let text = """
            patch:
              translator/preedit_format: |
                xform/([nl])v/$1ü/
                # not a comment: part of the text
              menu/page_size: 5

            """
        let editor = try CustomPatchEditor(text: text)
        #expect(editor.keys == ["translator/preedit_format", "menu/page_size"])
        try expectEdit(.set("translator/preedit_format", ["xform/([nl])v/$1ü/"]), in: text, gives: """
            patch:
              translator/preedit_format:
                - "xform/([nl])v/$1ü/"
              menu/page_size: 5

            """)
        try expectEdit(.remove("translator/preedit_format"), in: text, gives: "patch:\n  menu/page_size: 5\n")
    }
}
