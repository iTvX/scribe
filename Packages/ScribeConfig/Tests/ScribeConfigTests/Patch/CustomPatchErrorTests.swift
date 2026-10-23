import Foundation
import ScribeConfig
import Testing

struct CustomPatchErrorTests {
    @Test(arguments: [
        ("patch: {menu/page_size: 5}\n", 1, UnsupportedLayout.flowPatch),
        ("# 说明\npatch:  {\n  menu/page_size: 5}\n", 2, .flowPatch),
        ("patch:\n\tmenu/page_size: 5\n", 2, .tabIndentation),
        ("patch:\n  schema_list:\n  \t- schema: rime_ice\n", 3, .tabIndentation),
        ("patch:\n  menu/page_size: &size 5\n", 2, .anchorOrAlias),
        ("patch:\n  menu/page_size: 5\n  menu/alternative_select_keys: *keys\n", 3, .anchorOrAlias),
        ("patch:\n  schema_list:\n    - &rime {schema: rime_ice}\n", 3, .anchorOrAlias),
        ("customization:\n  generator: &g Scribe\npatch:\n  menu/page_size: 5\n", 2, .anchorOrAlias),
        ("patch:\n  menu/page_size: !!int 5\n", 2, .tag),
        ("patch:\n  switcher/hotkeys: [F4, !str Control+grave]\n", 2, .tag),
        ("patch:\n  menu/page_size: 5\n  menu/page_size: 6\n", 3, .duplicateKey),
        ("patch:\n  \"menu/page_size\": 5\n  'menu/page_size': 6\n", 3, .duplicateKey),
        ("patch:\n  menu/page_size: 5\npatch:\n  menu/page_size: 6\n", 3, .duplicateKey),
        ("patch:\n  ? menu/page_size\n  : 5\n", 2, .complexKey),
        ("patch:\n  menu/page_size: 5\n---\npatch:\n  menu/page_size: 6\n", 3, .multipleDocuments),
        ("patch:\n  menu/page_size: 5\n...\n", 3, .multipleDocuments),
        ("---\n---\npatch:\n", 2, .multipleDocuments),
        ("  patch:\n    menu/page_size: 5\n", 1, .indentedPatch),
        ("# 缩进的文件\n  customization:\n    generator: Scribe\n", 2, .indentedPatch),
        ("patch:\n    menu/page_size: 5\n  switcher/hotkeys: [F4]\n", 3, .inconsistentIndentation),
        ("patch:\n  menu/page_size: 5\n menu/alternative_select_keys: \"123\"\n", 3, .inconsistentIndentation),
        ("patch: 5\n", 1, .invalidEntry),
        ("patch: []\n", 1, .invalidEntry),
        ("patch:\n  - menu/page_size: 5\n", 2, .invalidEntry),
        ("patch:\n  menu/page_size: 5\n  - 6\n", 3, .invalidEntry),
        ("patch:\n  switcher:\n    caption: x\n  - F4\n", 4, .invalidEntry),
        ("patch:\n  menu/page_size 5\n", 2, .invalidEntry),
        ("patch:\n  \"unterminated: 5\n", 2, .invalidEntry),
        ("--- extra\npatch:\n", 1, .invalidEntry),
        ("- not a map\n", 1, .invalidEntry),
    ])
    func rejectsLayouts(text: String, line: Int, reason: UnsupportedLayout) {
        #expect(throws: CustomPatchError.unsupportedLayout(line: line, reason: reason)) {
            try CustomPatchEditor(text: text)
        }
    }

    @Test(arguments: [
        "patch:\n  menu/alternative_select_keys: \"&*!\"\n",
        "patch:\n  menu/alternative_select_keys: '!@#'\n",
        "patch:\n  menu/page_size: 5  # &not *an !anchor\n",
        "# &comment *only !here\npatch:\n  a&b: c*d!\n",
        "patch:\n  key_binder/bindings/+:\n    - {when: always, accept: Control+exclam, send: \"!\"}\n",
        "patch:\n  translator/preedit_format: |\n    &not an anchor\n    ? not a key\n    ---\n",
        "\u{FEFF}--- # 文档开始\npatch:\n",
    ])
    func acceptsLookalikes(text: String) throws {
        let editor = try CustomPatchEditor(text: text)
        #expect(editor.text == text)
    }
}
