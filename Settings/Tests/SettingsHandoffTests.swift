import Foundation
import ScribeConfig
import Testing

@MainActor @Suite("settings update handoff", .serialized)
struct SettingsHandoffTests {
    @Test(arguments: ["-", "12x", "12.3.4", "NaN", "", "999"])
    func incompleteNumbersStayAsDrafts(_ text: String) {
        #expect(!SettingsFieldDraft(text: text, minimum: 1, maximum: 200).isValid)
    }

    @Test func roundTripRetainsEveryDraftWithoutSaving() throws {
        let f = try Fixture()
        let old = f.models()
        old.defaults.pageSize = 9
        old.defaults.schemaItems[0].node = ["schema": "scribe_test", "case": .null]
        old.defaults.hotkeys = ["Control+Shift+j"]
        old.defaults.setSwitchKey("Shift_L", to: "commit_code")
        old.looks.personalize()
        old.looks.setField("appearance/font/face", text: "Helvetica, ")
        old.looks.setField("appearance/font/size", text: "-", range: 1...200)
        old.looks.reset("appearance/status_message")
        old.session.selection = .looks
        old.session.recipe = "iDvel/rime-ice:others/recipes/full"
        old.importer.source = f.root.appending(path: "另一个目录")
        old.importer.restoreFailure("保留这条导入结果")
        let draft = old.draft
        let decoded = try JSONDecoder().decode(SettingsDraft.self, from: JSONEncoder().encode(draft))
        #expect(decoded == draft)
        let new = f.models()
        try new.restore(decoded)
        #expect(new.draft == draft)
        #expect(new.looks.hasInvalidFields)
        #expect(new.looks.fieldDrafts["appearance/font/face"]?.text == "Helvetica, ")
        #expect(new.looks.preview == old.looks.preview)
        #expect(try Data(contentsOf: f.user.appending(path: "scribe.custom.yaml")) == f.originalLooks)
        #expect(!FileManager.default.fileExists(atPath: f.user.appending(path: "default.custom.yaml").path))
        new.looks.save()
        #expect(new.looks.status?.isError == true)
        #expect(new.looks.hasEdits)
    }

    @Test func diskChangesStillConflictAndCleanPagesStayFresh() throws {
        let f = try Fixture()
        let old = f.models()
        old.defaults.pageSize = 9
        old.looks.set("appearance/status_message", "short")
        let draft = old.draft
        let externalDefaults = "patch:\n  switcher/hotkeys: [Control+F8]\n"
        let externalLooks = String(decoding: f.originalLooks, as: UTF8.self) + "  appearance/alpha: 0.8\n"
        try externalDefaults.write(to: f.user.appending(path: "default.custom.yaml"), atomically: true, encoding: .utf8)
        try externalLooks.write(to: f.user.appending(path: "scribe.custom.yaml"), atomically: true, encoding: .utf8)
        let new = f.models()
        try new.restore(draft)
        #expect(new.defaults.hotkeys == ["Control+F8"])
        #expect(new.defaults.pageSize == 9)
        new.defaults.save(.schemas)
        new.looks.save()
        #expect(new.defaults.statuses[.schemas]?.isError == true)
        #expect(new.looks.status?.isError == true)
        #expect(new.defaults.pageSize == 9)
        #expect(try String(contentsOf: f.user.appending(path: "default.custom.yaml"), encoding: .utf8) == externalDefaults)
        #expect(try String(contentsOf: f.user.appending(path: "scribe.custom.yaml"), encoding: .utf8) == externalLooks)
    }

    @Test func readyReceiverMustAcknowledgeBeforeOldQuits() async throws {
        let f = try Fixture()
        let old = f.models()
        old.defaults.pageSize = 8
        old.session.selection = .shortcuts
        let oldRuntime = FakeRuntime(pid: 100)
        let source = f.coordinator(old, oldRuntime)
        source.start(scheduled: false)
        source.tick(); source.tick()
        await Task.yield()
        let token = try #require(oldRuntime.launched.first)
        #expect(old.session.isFrozen)
        #expect(oldRuntime.quitCount == 0)
        #expect(source.prepareToQuit() == false)
        let new = f.models()
        let newRuntime = FakeRuntime(pid: 200, build: "2")
        oldRuntime.living.append(newRuntime.process)
        newRuntime.living.append(oldRuntime.process)
        let receiver = f.coordinator(new, newRuntime)
        #expect(receiver.start(token: token, scheduled: false))
        #expect(new.session.isFrozen)
        #expect(new.defaults.pageSize == 8)
        source.tick()
        #expect(oldRuntime.quitCount == 1)
        #expect(try f.store.read(token).phase == .committed)
        receiver.tick()
        #expect(!new.session.isFrozen)
        #expect(new.session.selection == .shortcuts)
        receiver.tick(); receiver.tick()
        #expect(newRuntime.launched.isEmpty)
        #expect(oldRuntime.launched.count == 1)
    }

    @Test func timeoutCancelsLateReceiverAndKeepsSourceEditable() async throws {
        let f = try Fixture()
        let old = f.models()
        old.defaults.pageSize = 7
        let runtime = FakeRuntime(pid: 100)
        let source = f.coordinator(old, runtime)
        source.start(scheduled: false)
        source.tick(); source.tick()
        await Task.yield()
        let token = try #require(runtime.launched.first)
        source.tick(now: .now.addingTimeInterval(31))
        #expect(try f.store.read(token).phase == .cancelled)
        #expect(!old.session.isFrozen)
        #expect(old.defaults.pageSize == 7)
        #expect(runtime.quitCount == 0)
        let late = f.models()
        let lateRuntime = FakeRuntime(pid: 200, build: "2")
        let receiver = f.coordinator(late, lateRuntime)
        receiver.start(token: token, scheduled: false)
        #expect(lateRuntime.quitCount == 1)
        old.defaults.pageSize = 10
        #expect(source.prepareToQuit())
        #expect(try f.store.read(token).draft.defaults?.schemas?.pageSize == 10)
    }

    @Test func launchFailureKeepsDraftAndRetryCanSucceed() async throws {
        let f = try Fixture()
        let old = f.models()
        old.looks.setField("appearance/candidate_format", text: "[candidate] ")
        let runtime = FakeRuntime(pid: 100)
        runtime.launchError = true
        let source = f.coordinator(old, runtime)
        source.start(scheduled: false)
        source.tick(); source.tick()
        for _ in 0..<4 { await Task.yield() }
        #expect(!old.session.isFrozen)
        #expect(old.session.canRetryUpdate)
        #expect(old.looks.fieldDrafts["appearance/candidate_format"]?.text == "[candidate] ")
        source.tick(); source.tick()
        #expect(runtime.launched.count == 1)
        runtime.launchError = false
        source.retry(); source.tick()
        await Task.yield()
        #expect(runtime.launched.count == 2)
        #expect(runtime.quitCount == 0)
    }

    @Test func acknowledgementWinsOverTimeout() async throws {
        let f = try Fixture()
        let old = f.models()
        let runtime = FakeRuntime(pid: 100)
        let source = f.coordinator(old, runtime)
        source.start(scheduled: false)
        source.tick(); source.tick()
        await Task.yield()
        let token = try #require(runtime.launched.first)
        let process = SettingsProcess(pid: 200, launchedAt: 1)
        runtime.living.append(process)
        try f.store.transition(token, from: .waiting, to: .ready, receiver: process)
        source.tick(now: .now.addingTimeInterval(60))
        #expect(runtime.quitCount == 1)
        #expect(try f.store.read(token).phase == .committed)
    }

    @Test func deadReceiverDoesNotTakeSourceDown() async throws {
        let f = try Fixture()
        let old = f.models()
        let runtime = FakeRuntime(pid: 100)
        let source = f.coordinator(old, runtime)
        source.start(scheduled: false)
        source.tick(); source.tick()
        await Task.yield()
        let token = try #require(runtime.launched.first)
        try f.store.transition(token, from: .waiting, to: .ready, receiver: .init(pid: 200, launchedAt: 1))
        source.tick()
        #expect(runtime.quitCount == 0)
        #expect(!old.session.isFrozen)
        #expect(try f.store.read(token).phase == .cancelled)
    }

    @Test func receiverCanFinishAfterSourceCrashesFollowingAcknowledgement() throws {
        let f = try Fixture()
        let old = f.models()
        old.defaults.pageSize = 8
        let record = SettingsHandoff(source: .init(pid: 100, launchedAt: 1), targetBuild: "2", draft: old.draft)
        try f.store.create(record)
        let new = f.models()
        let runtime = FakeRuntime(pid: 200, build: "2")
        let receiver = f.coordinator(new, runtime)
        receiver.start(token: record.token, scheduled: false)
        #expect(new.session.isFrozen)
        receiver.tick()
        #expect(!new.session.isFrozen)
        #expect(new.defaults.pageSize == 8)
        #expect(try f.store.read(record.token).phase == .committed)
    }

    @Test func recoverySurvivesReceiverCrashAndRetiresAfterSave() throws {
        let f = try Fixture()
        let old = f.models()
        old.defaults.pageSize = 9
        var record = SettingsHandoff(source: .init(pid: 100, launchedAt: 1), targetBuild: "2", draft: old.draft)
        record.phase = .committed
        record.receiver = .init(pid: 200, launchedAt: 1)
        try f.store.create(record)
        let new = f.models()
        let runtime = FakeRuntime(pid: 300, build: "2")
        let receiver = f.coordinator(new, runtime)
        #expect(receiver.start(scheduled: false))
        #expect(new.defaults.pageSize == 9)
        new.defaults.save(.schemas)
        #expect(new.defaults.statuses[.schemas]?.isError == false)
        receiver.tick()
        #expect(try f.store.records().isEmpty)
    }

    @Test func defersDuringCompositionRecordingAndImportConfirmation() async throws {
        let f = try Fixture()
        let old = f.models()
        let runtime = FakeRuntime(pid: 100)
        let source = f.coordinator(old, runtime)
        source.start(scheduled: false)
        runtime.interactionBlocked = true
        source.tick(); source.tick()
        runtime.interactionBlocked = false
        old.session.isRecordingShortcut = true
        source.tick()
        old.session.isRecordingShortcut = false
        old.importer.isConfirmingBackup = true
        source.tick()
        old.importer.isConfirmingBackup = false
        runtime.canFlush = false
        source.tick()
        #expect(runtime.launched.isEmpty)
        #expect(!old.session.isFrozen)
        runtime.canFlush = true
        source.tick()
        await Task.yield()
        #expect(runtime.launched.count == 1)
    }

    @Test func importAndItsReportFinishBeforeSwitching() async throws {
        let f = try Fixture()
        let old = f.models()
        old.importer.source = try #require(f.directories.shared)
        let runtime = FakeRuntime(pid: 100)
        let source = f.coordinator(old, runtime)
        source.start(scheduled: false)
        old.importer.startImport()
        #expect(old.importer.isWorking)
        source.tick(); source.tick()
        #expect(runtime.launched.isEmpty)
        for _ in 0..<500 {
            if !old.importer.isWorking { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!old.importer.isWorking)
        #expect(old.importer.handoffBlocked) // The finished report is still visible.
        source.tick()
        #expect(runtime.launched.isEmpty)
        old.importer.reset()
        source.tick()
        await Task.yield()
        #expect(runtime.launched.count == 1)
    }

    @Test func incompatibleBuildWrongDirectoryAndBrokenStoreNeverQuitSource() async throws {
        let f = try Fixture()
        let old = f.models()
        let runtime = FakeRuntime(pid: 100)
        let source = f.coordinator(old, runtime)
        source.start(scheduled: false)
        runtime.installed?.protocolVersion = 2
        source.tick(); source.tick()
        #expect(runtime.launched.isEmpty)
        runtime.installed?.protocolVersion = 1
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.store.root.path)
        source.tick(); source.tick()
        await Task.yield()
        #expect(runtime.launched.isEmpty)
        #expect(runtime.quitCount == 0)
        #expect(!old.session.isFrozen)
        var wrong = old.draft
        wrong.userDirectory = f.root
        #expect(throws: SettingsHandoffError.self) { try old.restore(wrong) }
    }

    @Test func receiptTransitionsPermissionsAndCorruption() throws {
        let f = try Fixture()
        let record = SettingsHandoff(source: .init(pid: 100, launchedAt: 1), targetBuild: "2", draft: f.models().draft)
        try f.store.create(record)
        let path = f.store.root.appending(path: record.token.uuidString + ".json")
        #expect(try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? Int == 0o600)
        #expect(try FileManager.default.attributesOfItem(atPath: f.store.root.path)[.posixPermissions] as? Int == 0o700)
        #expect(try f.store.transition(record.token, from: .waiting, to: .cancelled))
        #expect(try !f.store.transition(record.token, from: .waiting, to: .ready))
        #expect(try !f.store.claim(record, by: .init(pid: 200, launchedAt: 1)))
        try Data("broken".utf8).write(to: path)
        #expect(throws: (any Error).self) { try f.store.read(record.token) }
        var unsupported = record
        unsupported.format = 2
        try f.store.create(unsupported)
        #expect(throws: SettingsHandoffError.self) { try f.store.read(record.token) }
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: f.user.appending(path: "scribe.custom.yaml"))
        #expect(throws: (any Error).self) { try f.store.read(record.token) }
    }

    @Test func legacyBridgePreservesOldProcessesAndDoesNotOpenWhenClosed() {
        let old = SettingsInstallationBridge.Running(process: .init(pid: 10, launchedAt: 1), build: nil)
        let current = SettingsInstallationBridge.Running(process: .init(pid: 20, launchedAt: 1), build: "2")
        let cooperative = SettingsInstallationBridge.Running(process: .init(pid: 30, launchedAt: 1), build: "1")
        #expect(SettingsInstallationBridge.legacyToOpen([], currentBuild: "2").isEmpty)
        #expect(SettingsInstallationBridge.legacyToOpen([old], currentBuild: "2") == [10])
        #expect(SettingsInstallationBridge.legacyToOpen([old, current], currentBuild: "2").isEmpty)
        #expect(SettingsInstallationBridge.legacyToOpen([cooperative], currentBuild: "2").isEmpty)
        #expect(SettingsInstallationBridge.legacyToOpen([old, cooperative], currentBuild: "2").isEmpty)
    }

    @Test func repeatedInstallerJobsCoalesce() throws {
        let f = try Fixture()
        let now = Date.now
        #expect(try f.store.claimLegacyLaunch(build: "2", now: now))
        #expect(try !f.store.claimLegacyLaunch(build: "2", now: now.addingTimeInterval(1)))
        #expect(try f.store.claimLegacyLaunch(build: "2", now: now.addingTimeInterval(31)))
        #expect(try f.store.claimLegacyLaunch(build: "3", now: now.addingTimeInterval(32)))
    }

    @Test func leasesRejectReusedPIDsAndManifestReadsNewBytes() throws {
        let f = try Fixture()
        let process = SettingsProcess(pid: 100, launchedAt: 1)
        try f.store.register(.init(process: process, build: "1"))
        #expect(try f.store.lease(for: process)?.build == "1")
        #expect(try f.store.lease(for: .init(pid: 100, launchedAt: 2)) == nil)
        f.store.unregister(process)
        #expect(try f.store.lease(for: process) == nil)
        let app = f.root.appending(path: "test.app")
        let macOS = app.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let executable = macOS.appending(path: "Settings")
        try Data("test".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        var info: [String: Any] = ["CFBundleVersion": "1", "CFBundleIdentifier": "test", "CFBundleExecutable": "Settings", "ScribeSettingsHandoffVersion": 1]
        let plist = app.appending(path: "Contents/Info.plist")
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
        #expect(SettingsManifest.read(at: app)?.build == "1")
        info["CFBundleVersion"] = "2"
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
        #expect(SettingsManifest.read(at: app)?.build == "2")
    }
}

@MainActor private final class FakeRuntime: SettingsUpdateRuntime {
    var process: SettingsProcess
    var loadedBuild: String
    let identifier = "test.settings"
    var installed: SettingsManifest? = .init(build: "2", identifier: "test.settings", protocolVersion: 1)
    var interactionBlocked = false
    var canFlush = true
    var living: [SettingsProcess]
    var launched: [UUID] = []
    var launchError = false
    var quitCount = 0
    init(pid: Int32, build: String = "1") {
        process = .init(pid: pid, launchedAt: 1)
        loadedBuild = build
        living = [process]
    }
    func isAlive(_ process: SettingsProcess) -> Bool { living.contains(process) }
    func flushEditing() -> Bool { canFlush }
    func launch(token: UUID) async throws {
        launched.append(token)
        if launchError { throw SettingsHandoffError.launchFailed }
    }
    func quit() { quitCount += 1 }
    func showLegacy(_ pids: [Int32]) {}
}

@MainActor private final class Fixture {
    let root = FileManager.default.temporaryDirectory.appending(path: "scribe-handoff-\(UUID().uuidString).noindex")
    let user: URL
    let store: SettingsHandoffStore
    let directories: SettingsDirectories
    let preferences: UserDefaults
    let originalLooks: Data

    init() throws {
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shared = root.appending(path: "shared")
        user = root.appending(path: "user")
        store = SettingsHandoffStore(root: root.appending(path: "handoff"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: repo.appending(path: "Tests/Fixtures/rime"), to: shared)
        try Data(contentsOf: repo.appending(path: "SharedSupport/scribe.yaml")).write(to: shared.appending(path: "scribe.yaml"))
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        originalLooks = Data("patch:\n  appearance/theme: native\n  appearance/status_message: long\n".utf8)
        try originalLooks.write(to: user.appending(path: "scribe.custom.yaml"))
        let suite = "scribe.handoff.tests.\(UUID().uuidString)"
        preferences = try #require(UserDefaults(suiteName: suite))
        preferences.set(user.path, forKey: "ScribeUserDirectory")
        preferences.set(shared.path, forKey: "ScribeSharedDirectory")
        directories = SettingsDirectories(defaults: preferences)
        preferences.removePersistentDomain(forName: suite)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    @MainActor struct Models {
        let defaults: DefaultsModel
        let looks: LooksModel
        let importer: ImportModel
        let session: SettingsSession
        var draft: SettingsDraft { .init(defaults: defaults, looks: looks, importer: importer, session: session) }
        func restore(_ draft: SettingsDraft) throws { try draft.restore(defaults: defaults, looks: looks, importer: importer, session: session) }
    }
    func models() -> Models {
        let defaults = DefaultsModel(directories: directories)
        let looks = LooksModel(directories: directories)
        defaults.load()
        looks.load(activeSchema: nil, schemaName: nil)
        return Models(defaults: defaults, looks: looks, importer: ImportModel(directories: directories, defaults: preferences), session: SettingsSession())
    }
    func coordinator(_ models: Models, _ runtime: FakeRuntime) -> SettingsUpdateCoordinator {
        .init(runtime: runtime, store: store, session: models.session, defaults: models.defaults, looks: models.looks, importer: models.importer)
    }
}
