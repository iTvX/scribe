import Foundation
@testable import ScribeConfig
import Testing

struct RimeDirectoryImporterTests {
    static let expectedImports = [
        ImportedItem(path: ".git", kind: .gitRepository),
        ImportedItem(path: "README.md", kind: .other),
        ImportedItem(path: "cn_dicts/8105.dict.yaml", kind: .dictionary),
        ImportedItem(path: "custom_phrase.txt", kind: .customPhrase),
        ImportedItem(path: "default.custom.yaml", kind: .customPatch),
        ImportedItem(path: "hamster.yaml", kind: .otherFrontendConfig),
        ImportedItem(path: "installation.yaml", kind: .installation),
        ImportedItem(path: "lua/build/keep.lua", kind: .lua),
        ImportedItem(path: "lua/cold_word_drop/processor.lua", kind: .lua),
        ImportedItem(path: "lua/date_translator.lua", kind: .lua),
        ImportedItem(path: "opencc/emoji.json", kind: .opencc),
        ImportedItem(path: "opencc/emoji.txt", kind: .opencc),
        ImportedItem(path: "rime.lua", kind: .lua),
        ImportedItem(path: "rime_ice.custom.yaml", kind: .customPatch),
        ImportedItem(path: "rime_ice.dict.yaml", kind: .dictionary),
        ImportedItem(path: "rime_ice.schema.yaml", kind: .schema),
        ImportedItem(path: "squirrel.custom.yaml", kind: .squirrelConfig),
        ImportedItem(path: "squirrel.yaml", kind: .squirrelConfig),
        ImportedItem(path: "user.yaml", kind: .sharedConfig),
        ImportedItem(path: "weasel.yaml", kind: .otherFrontendConfig),
        ImportedItem(path: "zh-hans-t-essay-bgw.gram", kind: .languageModel),
    ]

    static let expectedSkips = [
        SkippedItem(path: ".DS_Store", reason: .systemFile),
        SkippedItem(path: "build", reason: .buildOutput),
        SkippedItem(path: "lua/.DS_Store", reason: .systemFile),
        SkippedItem(path: "rime_ice.userdb", reason: .userDictionary),
        SkippedItem(path: "rime_ice.userdb.txt", reason: .userDictionary),
        SkippedItem(path: "sync", reason: .syncDirectory),
        SkippedItem(path: "trash", reason: .trash),
        SkippedItem(path: "wubi86.userdb.kct", reason: .userDictionary),
    ]

    // MARK: - Copying

    @Test func copiesEveryKindWithIdenticalBytes() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        #expect(report.source == fake.source)
        #expect(report.destination == fake.destination)
        #expect(report.imported == Self.expectedImports)
        #expect(Set(report.imported.map(\.kind)) == Set(ImportedFileKind.allCases))
        for item in report.imported where item.kind != .installation && item.kind != .gitRepository {
            let original = FileManager.default.contents(atPath: fake.url(item.path).path(percentEncoded: false))
            let copy = FileManager.default.contents(atPath: fake.destination.appending(path: item.path).path(percentEncoded: false))
            #expect(original != nil)
            #expect(copy == original, "\(item.path)")
        }
    }

    @Test func effectsFollowKinds() {
        let expected: [ImportedFileKind: ImportEffect] = [
            .schema: .asIs, .dictionary: .asIs, .customPatch: .asIs, .sharedConfig: .asIs,
            .lua: .asIs, .opencc: .asIs, .customPhrase: .asIs, .languageModel: .asIs,
            .squirrelConfig: .squirrelCompatibility,
            .installation: .regenerated,
            .otherFrontendConfig: .notRead, .gitRepository: .notRead, .other: .notRead,
        ]
        for kind in ImportedFileKind.allCases {
            #expect(kind.effect == expected[kind], "\(kind)")
            #expect(ImportedItem(path: "x", kind: kind).effect == kind.effect)
        }
    }

    @Test func skipsDeployOutputUserDictionariesSyncTrashAndFinderFiles() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        #expect(report.skipped == Self.expectedSkips)
        for item in report.skipped {
            #expect(itemExists(fake.url(item.path)), "\(item.path)")
            #expect(!itemExists(fake.destination.appending(path: item.path)), "\(item.path)")
        }
        #expect(itemExists(fake.destination.appending(path: "lua/build/keep.lua")))
    }

    @Test func copiesGitRepositoryWhole() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        let gitItems = report.imported.filter { $0.path == ".git" || $0.path.hasPrefix(".git/") }
        #expect(gitItems == [ImportedItem(path: ".git", kind: .gitRepository)])
        let copied = fake.destination.appending(path: ".git", directoryHint: .isDirectory)
        #expect(try snapshot(of: copied, dates: false) == snapshot(of: fake.url(".git"), dates: false))
        #expect(itemExists(copied.appending(path: ".DS_Store")))
        let hook = try FileManager.default.attributesOfItem(atPath: copied.appending(path: "hooks/pre-commit").path(percentEncoded: false))
        #expect(hook[.posixPermissions] as? Int == 0o755)
    }

    @Test func copiesGitFileOfAWorktree() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        try FileManager.default.removeItem(at: fake.url(".git"))
        try fake.write("gitdir: /Users/someone/rime-ice/.git/worktrees/Rime\n", to: ".git")

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        #expect(report.imported.first == ImportedItem(path: ".git", kind: .gitRepository))
        #expect(FileManager.default.contents(atPath: fake.destination.appending(path: ".git").path(percentEncoded: false))
                == FileManager.default.contents(atPath: fake.url(".git").path(percentEncoded: false)))
    }

    @Test func leavesSourceUntouched() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        try FileManager.default.createSymbolicLink(atPath: fake.url("lua/date.lua").path(percentEncoded: false),
                                                   withDestinationPath: "date_translator.lua")
        let before = try snapshot(of: fake.source)

        _ = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        #expect(try snapshot(of: fake.source) == before)
    }

    // MARK: - Symbolic links

    @Test func copiesLinkContentsAndReportsUnavailableTargets() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        let links = [
            "lua/date.lua": "date_translator.lua",
            "cn_dicts/base.dict.yaml": "../rime_ice.dict.yaml",
            "linked_dicts": "/Volumes/Fixture Cloud/dicts",
            "shared.yaml": "../shared/shared.yaml",
        ]
        for (path, target) in links {
            try FileManager.default.createSymbolicLink(atPath: fake.url(path).path(percentEncoded: false), withDestinationPath: target)
        }

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        for path in ["lua/date.lua", "cn_dicts/base.dict.yaml"] {
            let copy = fake.destination.appending(path: path)
            #expect(try FileManager.default.attributesOfItem(atPath: copy.path)[.type] as? FileAttributeType == .typeRegular)
            #expect(FileManager.default.contents(atPath: copy.path) == FileManager.default.contents(atPath: fake.url(path).path))
        }
        for path in ["linked_dicts", "shared.yaml"] {
            #expect(!itemExists(fake.destination.appending(path: path)))
            #expect(report.skipped.contains(SkippedItem(path: path, reason: .unavailableLink)))
        }
        let linkNotices = report.notices.filter {
            if case .symbolicLink = $0 { true } else { false }
        }
        #expect(linkNotices == [
            .symbolicLink(path: "linked_dicts", target: "/Volumes/Fixture Cloud/dicts"),
            .symbolicLink(path: "shared.yaml", target: "../shared/shared.yaml"),
        ])
    }

    // MARK: - Destination

    @Test func movesExistingDestinationToBackup() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        let old = fake.destination
        try FileManager.default.createDirectory(at: old.appending(path: "build"), withIntermediateDirectories: true)
        try Data("installation_id: \"old\"\n".utf8).write(to: old.appending(path: "installation.yaml"))
        try Data("var: {}\n".utf8).write(to: old.appending(path: "user.yaml"))
        let before = try snapshot(of: old, dates: false)
        let now = Date(timeIntervalSince1970: 1_761_200_000)

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run(now: now)

        let backup = try #require(report.backup)
        #expect(backup.lastPathComponent == "Scribe backup \(Self.stamp(now))")
        #expect(try snapshot(of: fake.root.appending(path: backup.lastPathComponent), dates: false) == before)
        #expect(try names(in: fake.root) == ["Rime", "Scribe", backup.lastPathComponent])
        #expect(itemExists(fake.destination.appending(path: "rime_ice.schema.yaml")))
        #expect(!itemExists(fake.destination.appending(path: "build")))
    }

    @Test func replacesEmptyDestinationWithoutBackup() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        try FileManager.default.createDirectory(at: fake.destination, withIntermediateDirectories: false)

        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()

        #expect(report.backup == nil)
        #expect(try names(in: fake.root) == ["Rime", "Scribe"])
        #expect(itemExists(fake.destination.appending(path: "rime_ice.schema.yaml")))
    }

    @Test func createsMissingParent() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        let destination = fake.root.appending(path: "Library/Application Support/Scribe", directoryHint: .isDirectory)

        let report = try RimeDirectoryImporter(source: fake.source, destination: destination).run()

        #expect(report.backup == nil)
        #expect(itemExists(destination.appending(path: "installation.yaml")))
        #expect(try names(in: destination.deletingLastPathComponent()) == ["Scribe"])
    }

    @Test func numbersBackupsWithTheSameTimestamp() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        let importer = RimeDirectoryImporter(source: fake.source, destination: fake.destination)
        let now = Date(timeIntervalSince1970: 1_761_200_000)

        #expect(try importer.run(now: now).backup == nil)
        let first = try #require(try importer.run(now: now).backup)
        let second = try #require(try importer.run(now: now).backup)
        let third = try #require(try importer.run(now: now).backup)

        #expect(first.lastPathComponent == "Scribe backup \(Self.stamp(now))")
        #expect(second.lastPathComponent == "Scribe backup \(Self.stamp(now))-2")
        #expect(third.lastPathComponent == "Scribe backup \(Self.stamp(now))-3")
    }

    @Test func removesStagingDirectoryWhenCopyFails() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        try FileManager.default.createDirectory(at: fake.destination, withIntermediateDirectories: false)
        try Data("var: {}\n".utf8).write(to: fake.destination.appending(path: "user.yaml"))
        let before = try snapshot(of: fake.destination)
        let unreadable = fake.url("user.yaml").path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable) }

        #expect(throws: (any Error).self) {
            try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()
        }

        #expect(try names(in: fake.root) == ["Rime", "Scribe"])
        #expect(try snapshot(of: fake.destination) == before)
    }

    // MARK: - Errors

    @Test func rejectsMissingSource() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        let missing = fake.root.appending(path: "Missing", directoryHint: .isDirectory)

        #expect(throws: RimeImportError.sourceNotFound(missing)) {
            try RimeDirectoryImporter(source: missing, destination: fake.destination).run()
        }
        #expect(try names(in: fake.root) == ["Rime"])
    }

    @Test func rejectsFileAsSource() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        let file = fake.url("user.yaml")

        #expect(throws: RimeImportError.sourceNotFound(file)) {
            try RimeDirectoryImporter(source: file, destination: fake.destination).run()
        }
        #expect(try names(in: fake.root) == ["Rime"])
    }

    @Test func rejectsOverlappingDirectories() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        let alias = fake.root.appending(path: "Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fake.source)
        let cases: [(source: URL, destination: URL)] = [
            (fake.source, fake.source),
            (fake.source, alias),
            (fake.source, fake.source.appending(path: "Scribe", directoryHint: .isDirectory)),
            (fake.source, fake.url("lua/Scribe")),
            (fake.url("lua"), fake.source),
            (fake.source, fake.root),
        ]
        let before = try snapshot(of: fake.root)

        for (source, destination) in cases {
            #expect(throws: RimeImportError.overlappingDirectories, "\(source.path(percentEncoded: false)) -> \(destination.path(percentEncoded: false))") {
                try RimeDirectoryImporter(source: source, destination: destination).run()
            }
        }
        #expect(try snapshot(of: fake.root) == before)
    }

    /// `yyyyMMdd-HHmmss` in local time, computed independently of the importer.
    static func stamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02d-%02d%02d%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                      parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}
