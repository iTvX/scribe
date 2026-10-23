import Foundation
@testable import ScribeConfig
import Testing

struct MigrationNoticeTests {
    @Test func flagsFrontendChecksOtherFrontendsAndUnsyncedDictionaries() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        // rime.lua mentions Squirrel only in a comment, so it is not flagged.
        #expect(report.notices == [
            .otherFrontendConfig(file: "hamster.yaml"),
            .luaChecksFrontend(file: "lua/cold_word_drop/processor.lua", line: 8,
                               text: "if rime_api.get_distribution_name() == '鼠鬚管' then"),
            .otherFrontendConfig(file: "weasel.yaml"),
            .userDictionariesNotSynced(["rime_ice", "wubi86"]),
        ])
    }

    @Test func luaScannerSkipsCommentsAndCountsLines() {
        let text = """
            -- Squirrel only
              -- 鼠须管 too\r
            local name = rime_api.get_distribution_name()\r

            if name == "Squirrel" then -- a trailing comment does not hide the code
            \tlocal traditional = name == "鼠鬚管"
            print("Weasel")
            """
        #expect(LuaFrontendScanner.notices(in: text, file: "rime.lua") == [
            .luaChecksFrontend(file: "rime.lua", line: 5,
                               text: #"if name == "Squirrel" then -- a trailing comment does not hide the code"#),
            .luaChecksFrontend(file: "rime.lua", line: 6, text: #"local traditional = name == "鼠鬚管""#),
        ])
    }

    @Test(arguments: [
        ("luna_pinyin.schema.yaml", ImportedFileKind.schema),
        ("cn_dicts/8105.dict.yaml", .dictionary),
        ("en_dicts/en.dict.yaml", .dictionary),
        ("default.custom.yaml", .customPatch),
        ("luna_pinyin.custom.yaml", .customPatch),
        ("squirrel.yaml", .squirrelConfig),
        ("squirrel.custom.yaml", .squirrelConfig),
        ("weasel.yaml", .otherFrontendConfig),
        ("weasel.custom.yaml", .otherFrontendConfig),
        ("hamster.yaml", .otherFrontendConfig),
        ("hamster.custom.yaml", .otherFrontendConfig),
        ("ibus_rime.yaml", .otherFrontendConfig),
        ("ibus_rime.custom.yaml", .otherFrontendConfig),
        ("trime.yaml", .otherFrontendConfig),
        ("trime.custom.yaml", .otherFrontendConfig),
        ("tongwenfeng.trime.yaml", .otherFrontendConfig),
        ("tongwenfeng.trime.custom.yaml", .otherFrontendConfig),
        ("default.yaml", .sharedConfig),
        ("symbols.yaml", .sharedConfig),
        ("user.yaml", .sharedConfig),
        ("installation.yaml", .installation),
        ("rime.lua", .lua),
        ("lua/date_translator.lua", .lua),
        ("lua/cold_word_drop/processor.lua", .lua),
        ("lua/README.md", .lua),
        ("opencc/emoji.json", .opencc),
        ("opencc/emoji.txt", .opencc),
        ("custom_phrase.txt", .customPhrase),
        ("custom_phrase_double.txt", .customPhrase),
        ("zh-hans-t-essay-bgw.gram", .languageModel),
        (".git", .gitRepository),
        ("README.md", .other),
        ("LICENSE", .other),
        ("others/rime.lua", .other),
        ("scripts/build.lua", .other),
        ("config.yml", .other),
        (".gitignore", .other),
    ])
    func classifiesPaths(path: String, kind: ImportedFileKind) {
        #expect(ImportedFileKind(path: path) == kind)
    }
}
