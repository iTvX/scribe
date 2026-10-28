import Foundation
import RimeKit
@testable import ScribeConfig
import Testing

@MainActor @Suite(.serialized)
struct ConfigIsolationTests {
    private let original = "patch:\n  menu/page_size: 5\n"

    private func workspace(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "scribe-isolation-\(UUID().uuidString)")
        let user = root.appending(path: "Scribe")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, user)
    }

    @Test func savingAnImportedAbsoluteLinkLeavesItsSourceUntouched() throws {
        try workspace { root, user in
            let source = root.appending(path: "Rime")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            let target = source.appending(path: "shared-default.yaml")
            try original.write(to: target, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(at: source.appending(path: "default.custom.yaml"), withDestinationURL: target)
            _ = try RimeDirectoryImporter(source: source, destination: user).run()
            let writer = CustomPatchWriter(userDirectory: user, sharedDirectory: CustomPatchWriterTests.shared)
            _ = try writer.save("default", changes: [.set("menu/page_size", 9)], expectedOriginal: original)
            #expect(try String(contentsOf: target, encoding: .utf8) == original)
            #expect(try RimeDefaults.load(userDirectory: user, sharedDirectory: CustomPatchWriterTests.shared).pageSize == 9)
        }
    }

    @Test func anEditDuringValidationIsReportedAsAConflict() throws {
        try workspace { _, user in
            let file = user.appending(path: "default.custom.yaml")
            try original.write(to: file, atomically: true, encoding: .utf8)
            let external = "# saved by another editor\npatch:\n  menu/page_size: 7\n"
            var writer = CustomPatchWriter(userDirectory: user, sharedDirectory: CustomPatchWriterTests.shared)
            writer.expectation = { _, value in
                try! external.write(to: file, atomically: true, encoding: .utf8)
                return value
            }
            #expect(throws: PatchSaveError.changedOnDisk) {
                try writer.save("default", changes: [.set("menu/page_size", 9)], expectedOriginal: original)
            }
            #expect(try String(contentsOf: file, encoding: .utf8) == external)
        }
    }

    @Test func aRetargetedLinkIsReportedAsAConflictEvenWithIdenticalBytes() throws {
        try workspace { _, user in
            let file = user.appending(path: "default.custom.yaml")
            let first = user.appending(path: "first.yaml"), second = user.appending(path: "second.yaml")
            for target in [first, second] { try original.write(to: target, atomically: true, encoding: .utf8) }
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: first)
            var writer = CustomPatchWriter(userDirectory: user, sharedDirectory: CustomPatchWriterTests.shared)
            writer.expectation = { _, value in
                try! FileManager.default.removeItem(at: file)
                try! FileManager.default.createSymbolicLink(at: file, withDestinationURL: second)
                return value
            }
            #expect(throws: PatchSaveError.changedOnDisk) {
                try writer.save("default", changes: [.set("menu/page_size", 9)], expectedOriginal: original)
            }
            for target in [first, second] { #expect(try String(contentsOf: target, encoding: .utf8) == original) }
        }
    }

    @Test func nestedIncludesMatchTheLiveConfigurationAndSurviveSaving() throws {
        try workspace { _, user in
            try FileManager.default.createDirectory(at: user.appending(path: "nested"), withIntermediateDirectories: true)
            try "page_size: 9\n".write(to: user.appending(path: "nested/menu.yaml"), atomically: true, encoding: .utf8)
            let custom = "patch:\n  menu:\n    __include: nested/menu:/\n"
            try custom.write(to: user.appending(path: "default.custom.yaml"), atomically: true, encoding: .utf8)
            let loaded = try RimeDefaults.load(userDirectory: user, sharedDirectory: CustomPatchWriterTests.shared)
            #expect(loaded.pageSize == 9)
            let writer = CustomPatchWriter(userDirectory: user, sharedDirectory: CustomPatchWriterTests.shared)
            _ = try writer.save("default", changes: [.set("switcher/hotkeys", ["F4"])], expectedOriginal: custom)
            let saved = try RimeDefaults.load(userDirectory: user, sharedDirectory: CustomPatchWriterTests.shared)
            #expect(saved.pageSize == 9)
            #expect(saved.switcherHotkeys == ["F4"])
        }
    }
}

extension ConfigIsolationTests {
    @Test func existingExternalLinksAreReadOnlyBeforeAndDuringSave() throws {
        try workspace { root, user in
            let original = "patch:\n  menu/page_size: 7\n"
            let target = root.appending(path: "squirrel-default.yaml")
            try original.write(to: target, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(at: user.appending(path: "default.custom.yaml"), withDestinationURL: target)
            let loaded = try RimeDefaults.load(userDirectory: user, sharedDirectory: CustomPatchWriterTests.shared)
            let resolved = CustomPatchWriter.resolvedFile(target)
            #expect(loaded.pageSize == 7)
            #expect(loaded.editProblem == .externalLink(resolved))
            let writer = CustomPatchWriter(userDirectory: user, sharedDirectory: CustomPatchWriterTests.shared)
            #expect(throws: PatchSaveError.externalLink(resolved)) {
                try writer.save("default", changes: [.set("menu/page_size", 9)], expectedOriginal: original)
            }
            #expect(try String(contentsOf: target, encoding: .utf8) == original)
        }
    }
}

extension ConfigIsolationTests {
    @Test func cyclicConfigDirectoriesFailWithoutChangingUserFiles() throws {
        try workspace { _, user in
            let file = user.appending(path: "default.custom.yaml")
            try original.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(at: user.appending(path: "cycle"), withDestinationURL: user)
            #expect(throws: PatchSaveError.self) {
                try RimeDefaults.load(userDirectory: user, sharedDirectory: CustomPatchWriterTests.shared)
            }
            #expect(try String(contentsOf: file, encoding: .utf8) == original)
            #expect(!LibrimeEngine.shared.isRunning)
        }
    }
}

extension ConfigIsolationTests {
    @Test func aWriterRacingTheReplacementKeepsBothVersions() throws {
        try workspace { _, user in
            let file = user.appending(path: "default.custom.yaml")
            try original.write(to: file, atomically: true, encoding: .utf8)
            let concurrent = "# other editor\npatch:\n  menu/page_size: 7\n"
            var writer = CustomPatchWriter(userDirectory: user, sharedDirectory: CustomPatchWriterTests.shared)
            writer.beforeReplace = { try concurrent.write(to: file, atomically: true, encoding: .utf8) }
            do {
                _ = try writer.save("default", changes: [.set("menu/page_size", 9)], expectedOriginal: original)
                Issue.record("an uncoordinated replacement must report its conflict")
            } catch PatchSaveError.concurrentWrite(let backup) {
                #expect(try String(contentsOf: backup, encoding: .utf8) == concurrent)
                #expect(try String(contentsOf: file, encoding: .utf8).contains("menu/page_size: 9"))
            }
        }
    }
}
