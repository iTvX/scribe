import Foundation
import RimeKit
@testable import ScribeConfig
import Testing

/// Saves through real librime. Everything that runs the engine happens in
/// one synchronous main-actor test, which leaves it stopped.
@MainActor
@Suite("custom patch writer", .serialized)
struct CustomPatchWriterTests {
    static let shared = FakeRimeDirectory.fixture.deletingLastPathComponent().appending(path: "rime", directoryHint: .isDirectory)

    static let defaultCustom = """
        # 中书测试：手写的 default.custom.yaml
        patch:
          # 方案
          schema_list:
          - schema: scribe_test
          # - schema: luna_pinyin
          menu: {page_size: 5}
          schema_list/+:
            - schema: scribe_test
          switcher/hotkeys:
            - F4
        # 结尾的注释

        """

    @Test func savesOnlyWhatLibrimeConfirms() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "ScribeConfigTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let user = root.appending(path: "Scribe", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: user, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let file = user.appending(path: "default.custom.yaml")
        try Data(Self.defaultCustom.utf8).write(to: file)
        let engine = LibrimeEngine.shared
        #expect(!engine.isRunning)
        defer { engine.stop() }

        // What librime makes of the file now: schema_list/+ appends a duplicate.
        let before = try RimeDefaults.load(userDirectory: user, sharedDirectory: Self.shared)
        #expect(before.schemaIDs == ["scribe_test", "scribe_test"])
        #expect(before.pageSize == 5)
        #expect(before.switcherHotkeys == ["F4"])
        #expect(before.switchKey.isEmpty)
        #expect(before.customText == Self.defaultCustom)
        #expect(!engine.isRunning)

        // Set four keys; schema_list/+ is superseded, menu: {page_size: 5} stays.
        let writer = CustomPatchWriter(userDirectory: user, sharedDirectory: Self.shared)
        let result = try writer.save("default", changes: [
            .set("schema_list", [["schema": "scribe_test"]]),
            .set("menu/page_size", 8),
            .set("switcher/hotkeys", ["Control+grave", "F4"]),
            .set("ascii_composer/switch_key", ["Shift_L": "commit_code", "Caps_Lock": "clear"]),
        ], expectedOriginal: before.customText)
        #expect(result.supersededKeys == ["schema_list/+"])
        #expect(result.file.path(percentEncoded: false) == CustomPatchWriter.resolvedFile(file).path(percentEncoded: false))
        let saved = """
            # 中书测试：手写的 default.custom.yaml
            patch:
              # 方案
              schema_list:
                - schema: scribe_test
              # - schema: luna_pinyin
              menu: {page_size: 5}
              switcher/hotkeys:
                - Control+grave
                - F4
              menu/page_size: 8
              ascii_composer/switch_key:
                Caps_Lock: clear
                Shift_L: commit_code
            # 结尾的注释

            """
        #expect(try String(contentsOf: file, encoding: .utf8) == saved)
        let after = try RimeDefaults.load(userDirectory: user, sharedDirectory: Self.shared)
        #expect(after.schemaIDs == ["scribe_test"])
        #expect(after.pageSize == 8)
        #expect(after.switcherHotkeys == ["Control+grave", "F4"])
        #expect(after.switchKey == ["Shift_L": "commit_code", "Caps_Lock": "clear"])
        #expect(!engine.isRunning)
        let leftovers = try fileManager.contentsOfDirectory(atPath: user.path(percentEncoded: false))
        #expect(leftovers == ["default.custom.yaml"])

        // A file that changed since the page loaded it is left alone.
        #expect(throws: PatchSaveError.changedOnDisk) {
            try writer.save("default", changes: [.set("menu/page_size", 9)], expectedOriginal: Self.defaultCustom)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == saved)

        // A value librime cannot apply is rejected before anything is written:
        // patching inside a list fails, so default.yaml does not build at all.
        let conflict = saved.replacingOccurrences(of: "menu: {page_size: 5}", with: "menu: [oops]")
        try Data(conflict.utf8).write(to: file)
        #expect(throws: PatchSaveError.notEffective(key: "menu/page_size", expected: "9", actual: nil)) {
            try writer.save("default", changes: [.set("menu/page_size", 9)], expectedOriginal: conflict)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == conflict)

        // A layout the editor refuses.
        let flow = "patch: {menu/page_size: 5}\n"
        try Data(flow.utf8).write(to: file)
        #expect(throws: PatchSaveError.unsupportedLayout(line: 1, reason: .flowPatch)) {
            try writer.save("default", changes: [.set("menu/page_size", 9)], expectedOriginal: flow)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == flow)

        // The checks need the engine to themselves.
        engine.start(RimeConfiguration(sharedDataDirectory: Self.shared, userDataDirectory: user, minimumLogLevel: 2))
        #expect(throws: PatchSaveError.engineBusy) {
            try writer.save("default", changes: [.set("menu/page_size", 9)], expectedOriginal: flow)
        }
        engine.stop()

        // A symbolic link: the target changes and the link stays a link.
        let dotfiles = root.appending(path: "dotfiles", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        let target = dotfiles.appending(path: "default.custom.yaml")
        try Data(Self.defaultCustom.utf8).write(to: target)
        try fileManager.removeItem(at: file)
        try fileManager.createSymbolicLink(atPath: file.path(percentEncoded: false), withDestinationPath: "../dotfiles/default.custom.yaml")
        let linked = try writer.save("default", changes: [.set("menu/page_size", 7)], expectedOriginal: Self.defaultCustom)
        #expect(try fileManager.destinationOfSymbolicLink(atPath: file.path(percentEncoded: false)) == "../dotfiles/default.custom.yaml")
        #expect(linked.file.path(percentEncoded: false) == CustomPatchWriter.resolvedFile(target).path(percentEncoded: false))
        #expect(try String(contentsOf: target, encoding: .utf8).contains("  menu/page_size: 7\n"))
        #expect(try RimeDefaults.load(userDirectory: user, sharedDirectory: Self.shared).pageSize == 7)

        // A user directory with no custom file gets a new one.
        try fileManager.removeItem(at: file)
        let created = try writer.save("default", changes: [.set("menu/page_size", 6)], expectedOriginal: nil)
        #expect(created.supersededKeys.isEmpty)
        #expect(try String(contentsOf: file, encoding: .utf8) == "patch:\n  menu/page_size: 6\n")
        #expect(!engine.isRunning)
    }
}

@MainActor
@Suite("deployed appearance", .serialized)
struct DeployedAppearanceTests {
    @Test func readsBuildFilesFromACopy() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "ScribeConfigTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let build = root.appending(path: "Scribe/build", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: build, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let user = build.deletingLastPathComponent()
        let shared = CustomPatchWriterTests.shared

        #expect(try Appearance.loadDeployed(userDirectory: user, sharedDirectory: shared, schemaID: "scribe_test") == nil)

        let squirrel = FakeRimeDirectory.fixture.deletingLastPathComponent().appending(path: "config/rime-ice/squirrel.yaml")
        try fileManager.copyItem(at: squirrel, to: build.appending(path: "squirrel.yaml"))
        try Data("schema:\n  schema_id: scribe_test\nstyle:\n  color_scheme: lost_temple\n".utf8)
            .write(to: build.appending(path: "scribe_test.schema.yaml"))
        let before = try snapshot(of: user)

        let plain = try #require(try Appearance.loadDeployed(userDirectory: user, sharedDirectory: shared, schemaID: ""))
        #expect(plain.appearance.light.colorSchemeID == "purity_of_form_custom")
        #expect(plain.colorSchemeNames["purity_of_form_custom"] != nil)
        let styled = try #require(try Appearance.loadDeployed(userDirectory: user, sharedDirectory: shared, schemaID: "scribe_test"))
        #expect(styled.appearance.light.colorSchemeID == "lost_temple")
        #expect(styled.colorSchemeNames["lost_temple"] == "孤寺／Lost Temple")
        #expect(try snapshot(of: user) == before)
        #expect(!LibrimeEngine.shared.isRunning)
    }
}

@MainActor
@Suite("schema catalog", .serialized)
struct SchemaCatalogTests {
    @Test func scansUserAndSharedSchemas() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "ScribeConfigTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let user = root.appending(path: "Scribe", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: user.appending(path: "build"), withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        func write(_ text: String, _ path: String) throws {
            try Data(text.utf8).write(to: user.appending(path: path))
        }
        try write("schema:\n  schema_id: scribe_test\n  name: 用户版\n  author: 中书\n", "scribe_test.schema.yaml")
        try write("schema:\n  schema_id: rime_ice\n  name: 雾凇拼音\n  author:\n    - Dvel\n    - 雾凇\n  description: |\n    测试\n", "rime_ice.schema.yaml")
        try write("schema:\n  name: 没有 ID\n", "broken.schema.yaml")
        try write("not: [a schema\n", "unreadable.schema.yaml")
        try write("var:\n  previously_selected_schema: rime_ice\n", "user.yaml")
        try write("schema:\n  schema_id: rime_ice\nmenu:\n  page_size: 7\nascii_composer:\n  switch_key:\n    Shift_L: commit_code\n",
                  "build/rime_ice.schema.yaml")
        try write("schema:\n  schema_id: scribe_test\n", "build/scribe_test.schema.yaml")

        let schemas = SchemaCatalog.scan(userDirectory: user, sharedDirectory: CustomPatchWriterTests.shared)
        #expect(schemas == [
            SchemaInfo(id: "rime_ice", name: "雾凇拼音", authors: ["Dvel", "雾凇"], description: "测试\n", isInUserDirectory: true),
            SchemaInfo(id: "scribe_test", name: "用户版", authors: ["中书"], description: nil, isInUserDirectory: true),
        ])
        let sharedOnly = SchemaCatalog.scan(userDirectory: root.appending(path: "missing"), sharedDirectory: CustomPatchWriterTests.shared)
        #expect(sharedOnly == [SchemaInfo(id: "scribe_test", name: "Scribe Test", authors: [], description: nil, isInUserDirectory: false)])

        #expect(SchemaCatalog.activeSchema(userDirectory: user) == "rime_ice")
        #expect(SchemaCatalog.activeSchema(userDirectory: root) == nil)
        #expect(SchemaCatalog.overrides(for: ["scribe_test", "rime_ice", "luna_pinyin"], userDirectory: user) == [
            SchemaOverride(schemaID: "rime_ice", pageSize: 7, switchKey: ["Shift_L": "commit_code"]),
        ])
        #expect(!LibrimeEngine.shared.isRunning)
    }
}
