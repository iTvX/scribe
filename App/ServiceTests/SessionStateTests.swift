import AppKit
import RimeKit
import ScribeConfig
import ScribeCore
import ScribeUI
import Testing

// These tests use the real service, adapters, session and librime. Only the
// window and text clients are recordings; dictionaries live in a temp dir.
// One serialized suite also contains RecoveryTests, since librime is global.
extension RecoveryTests {
    @Test(arguments: ["example.OtherApp", "example.Editor"])
    func returningToAClientRestoresItsSchemaStyle(secondApp: String) throws {
        let fixture = try SessionFixture()
        defer { fixture.close() }
        let a = try fixture.makeClient(schema: "scribe_inline", bundleID: "example.Editor")
        let b = try fixture.makeClient(schema: "scribe_test", bundleID: secondApp)

        fixture.activate(a)
        fixture.type("n", into: a)
        #expect(a.adapter.configuration.presentation.inlinePreedit)
        a.adapter.deactivate(client: a.text)
        fixture.activate(b)
        fixture.type("n", into: b)
        #expect(!b.adapter.configuration.presentation.inlinePreedit)
        #expect(a.adapter.configuration.presentation.inlinePreedit)
        b.adapter.deactivate(client: b.text)

        fixture.activate(a)
        fixture.type("n", into: a)
        #expect(a.text.marked.text == "n")
        #expect(fixture.panel.appearance.light.layout == .stacked)
        #expect(!fixture.engine.option("_linear", in: a.id))
        #expect(a.text.commits == ["n"])
        #expect(b.text.commits == ["n"])
    }

    @Test func lateDeactivationDoesNotHideTheNewClientsCandidates() throws {
        let fixture = try SessionFixture()
        defer { fixture.close() }
        let a = try fixture.makeClient(schema: "scribe_inline")
        let b = try fixture.makeClient(schema: "scribe_test")
        fixture.activate(a)
        fixture.type("n", into: a)
        fixture.activate(b)
        fixture.type("n", into: b)
        let snapshot = fixture.panel.snapshot
        a.adapter.deactivate(client: a.text)
        #expect(fixture.panel.visible)
        #expect(fixture.panel.delegate === b.adapter)
        #expect(fixture.panel.snapshot == snapshot)
        #expect(a.text.commits == ["n"])
        #expect(b.text.commits.isEmpty)
    }

    @Test func inactiveOptionNotificationDoesNotReplaceTheActiveMode() throws {
        let fixture = try SessionFixture()
        defer { fixture.close() }
        let a = try fixture.makeClient(schema: "scribe_inline")
        let b = try fixture.makeClient(schema: "scribe_test")
        fixture.activate(a)
        fixture.type("n", into: a)
        a.adapter.deactivate(client: a.text)
        fixture.activate(b)
        fixture.type("n", into: b)
        fixture.engine.setOption("ascii_mode", true, in: a.id)
        fixture.service.announce(RimeNotification(sessionID: a.id, type: "option", value: "ascii_mode"))
        #expect(fixture.status.title == "中")
        #expect(fixture.panel.delegate === b.adapter)
        #expect(fixture.panel.visible)
    }

    @Test func activationUsesTheCurrentSystemAppearance() throws {
        let fixture = try SessionFixture()
        defer { fixture.close() }
        let a = try fixture.makeClient(schema: "scribe_dark")
        fixture.activate(a)
        fixture.type("n", into: a)
        #expect(a.text.marked.text == "n")
        a.adapter.deactivate(client: a.text)
        fixture.dark = true
        fixture.activate(a)
        fixture.type("n", into: a)
        #expect(!a.adapter.configuration.presentation.inlinePreedit)
        #expect(a.text.marked.text == "　")
        #expect(fixture.panel.snapshot?.preedit?.text.hasPrefix("n") == true)
    }

    @Test func appearanceChangesRedrawAnExistingCompositionWithoutAnotherKey() throws {
        let fixture = try SessionFixture()
        defer { fixture.close() }
        let a = try fixture.makeClient(schema: "scribe_dark")
        fixture.activate(a)
        fixture.type("ni", into: a)
        let entries = fixture.panel.snapshot?.entries
        fixture.dark = true
        fixture.service.systemAppearanceChanged()
        #expect(a.text.marked.text == "　")
        #expect(fixture.panel.snapshot?.preedit?.text.hasPrefix("ni") == true)
        #expect(fixture.panel.snapshot?.entries == entries)
        #expect(a.text.commits.isEmpty)
        fixture.dark = false
        fixture.service.systemAppearanceChanged()
        #expect(a.text.marked.text == "ni")
        #expect(fixture.panel.snapshot?.preedit == nil)
        #expect(fixture.engine.input(in: a.id) == "ni")
    }

    @Test func appKitAppearanceObservationRefreshesTheActiveSession() async throws {
        let app = NSApplication.shared
        let previous = app.appearance
        defer { app.appearance = previous }
        app.appearance = NSAppearance(named: .aqua)
        let fixture = try SessionFixture()
        defer { fixture.close() }
        fixture.usesSystemAppearance = true
        let a = try fixture.makeClient(schema: "scribe_dark")
        fixture.activate(a)
        fixture.type("n", into: a)
        #expect(a.text.marked.text == "n")
        app.appearance = NSAppearance(named: .darkAqua)
        for _ in 0..<20 where a.text.marked.text != "　" { await Task.yield() }
        #expect(a.text.marked.text == "　")
        #expect(a.text.commits.isEmpty)
    }

    @Test func firstKeyCatchesAnAppearanceChangeBeforeItsQueuedCallback() throws {
        let fixture = try SessionFixture()
        defer { fixture.close() }
        let a = try fixture.makeClient(schema: "scribe_dark")
        fixture.activate(a)
        fixture.dark = true
        fixture.type("n", into: a)
        #expect(!a.adapter.configuration.presentation.inlinePreedit)
        #expect(a.text.marked.text == "　")
    }

    @Test func staleNotificationsCannotRevertTheCurrentSchemaOrMode() throws {
        let fixture = try SessionFixture()
        defer { fixture.close() }
        let a = try fixture.makeClient(schema: "scribe_inline")
        fixture.activate(a)
        fixture.type("n", into: a)
        #expect(fixture.engine.selectSchema("scribe_test", in: a.id))
        fixture.service.announce(RimeNotification(sessionID: a.id, type: "schema", value: "scribe_test/Scribe Test"))
        #expect(!a.adapter.configuration.presentation.inlinePreedit)
        fixture.type("n", into: a)
        #expect(fixture.engine.option("_linear", in: a.id))
        let messages = fixture.panel.messages
        fixture.service.announce(RimeNotification(sessionID: a.id, type: "schema", value: "scribe_inline/Old Schema"))
        fixture.service.announce(RimeNotification(sessionID: a.id, type: "option", value: "ascii_mode"))
        #expect(!a.adapter.configuration.presentation.inlinePreedit)
        #expect(fixture.status.title == "中")
        #expect(fixture.panel.messages == messages)
        #expect(fixture.panel.appearance.light.layout == .linear)
    }

    @Test func inactivePropertyAndSchemaNotificationsCannotTakeTheWindow() throws {
        let fixture = try SessionFixture()
        defer { fixture.close() }
        let a = try fixture.makeClient(schema: "scribe_inline")
        let b = try fixture.makeClient(schema: "scribe_test")
        fixture.activate(a)
        fixture.type("n", into: a)
        // B becomes active before A receives its deactivation callback.
        fixture.activate(b)
        fixture.type("ni", into: b)
        let snapshot = fixture.panel.snapshot
        for (type, value) in [("property", "_refresh_ui=1"), ("schema", "scribe_inline/Old Schema")] {
            fixture.service.announce(RimeNotification(sessionID: a.id, type: type, value: value))
        }
        #expect(fixture.panel.delegate === b.adapter)
        #expect(fixture.panel.snapshot == snapshot)
        #expect(fixture.panel.messages.isEmpty)
        #expect(fixture.panel.appearance.light.layout == .linear)
        #expect(b.text.marked.text == "　")
    }

    @Test func aDeactivatedSessionCannotReopenTheWindow() throws {
        let fixture = try SessionFixture()
        defer { fixture.close() }
        let a = try fixture.makeClient(schema: "scribe_inline")
        fixture.activate(a)
        fixture.type("n", into: a)
        a.adapter.deactivate(client: a.text)
        fixture.engine.setOption("ascii_mode", true, in: a.id)
        fixture.service.announce(RimeNotification(sessionID: a.id, type: "option", value: "ascii_mode"))
        #expect(!fixture.panel.visible)
        #expect(fixture.panel.delegate == nil)
        #expect(fixture.panel.messages.isEmpty)
        #expect(fixture.status.title == "中")
    }

    @Test func appOptionsAndModeIndicatorAreReadyBeforeTheFirstKey() throws {
        let fixture = try SessionFixture()
        defer { fixture.close() }
        let ascii = try fixture.makeClient(schema: "scribe_inline", bundleID: "example.ASCII")
        let chinese = try fixture.makeClient(schema: "scribe_test")
        fixture.activate(ascii)
        #expect(ascii.adapter.isASCIIMode == true)
        #expect(fixture.status.title == "A")
        fixture.activate(chinese)
        #expect(chinese.adapter.isASCIIMode == false)
        #expect(fixture.status.title == "中")
        fixture.activate(ascii)
        #expect(fixture.status.title == "A")
        // The user's own mode toggle survives returning to this app.
        ascii.adapter.setASCIIMode(false)
        #expect(fixture.status.title == "中")
        fixture.activate(chinese)
        fixture.activate(ascii)
        #expect(ascii.adapter.isASCIIMode == false)
        #expect(fixture.status.title == "中")
    }

    @Test func schemaSynchronizationDoesNotConsumeOrDuplicateAPendingCommit() throws {
        let fixture = try SessionFixture()
        defer { fixture.close() }
        let a = try fixture.makeClient(schema: "scribe_inline")
        fixture.activate(a)
        #expect(fixture.engine.selectSchema("scribe_test", in: a.id))
        #expect(fixture.engine.processKey(0x6e, modifiers: 0, in: a.id))
        let candidate = try #require(fixture.engine.context(in: a.id).menu?.candidates.first?.text)
        #expect(fixture.engine.processKey(0x20, modifiers: 0, in: a.id))
        fixture.type("n", into: a)
        #expect(a.text.commits == [candidate])
        #expect(a.text.marked.text == "　")
        fixture.type("i", into: a)
        #expect(a.text.commits == [candidate])
        #expect(fixture.engine.input(in: a.id) == "ni")
    }

    @Test func configurationReloadKeepsEachClientsOwnSchema() throws {
        let fixture = try SessionFixture()
        defer { fixture.close() }
        let a = try fixture.makeClient(schema: "scribe_inline")
        let b = try fixture.makeClient(schema: "scribe_test")
        fixture.activate(a)
        fixture.type("n", into: a)
        a.adapter.deactivate(client: a.text)
        fixture.activate(b)
        fixture.type("n", into: b)
        fixture.service.loadAppearance()
        #expect(a.adapter.configuration.presentation.inlinePreedit)
        #expect(!b.adapter.configuration.presentation.inlinePreedit)
        #expect(fixture.panel.appearance.light.layout == .linear)
        #expect(fixture.engine.input(in: b.id) == "n")
    }
}

@MainActor private final class SessionFixture {
    let engine = LibrimeEngine.shared
    let panel = RecordingPanel()
    let status = ModeStatusItem()
    var dark = false
    var usesSystemAppearance = false
    lazy var service = RimeService(candidatePanel: panel, modeStatusItem: status, isDark: { [unowned self] in
        self.usesSystemAppearance
            ? NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            : self.dark
    })
    let directory = FileManager.default.temporaryDirectory.appending(path: "scribe-session-\(UUID().uuidString)")
    private var clients: [Client] = []

    struct Client {
        let adapter: InputAdapter
        let text: RecordingClient
        let id: RimeSessionID
    }

    init() throws {
        let fm = FileManager.default
        let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Tests/Fixtures/rime")
        let shared = directory.appending(path: "shared")
        let user = directory.appending(path: "user")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try fm.copyItem(at: fixtures, to: shared)
        try fm.createDirectory(at: user, withIntermediateDirectories: true)
        let squirrelFile = shared.appending(path: "squirrel.yaml")
        let squirrel = try String(contentsOf: squirrelFile, encoding: .utf8)
        try (squirrel + "\napp_options:\n  example.ASCII:\n    ascii_mode: true\n")
            .write(to: squirrelFile, atomically: true, encoding: .utf8)
        let schema = try String(contentsOf: shared.appending(path: "scribe_test.schema.yaml"), encoding: .utf8)
        let inline = schema.replacingOccurrences(of: "schema_id: scribe_test", with: "schema_id: scribe_inline")
            .replacingOccurrences(of: "inline_preedit: false", with: "inline_preedit: true")
            .replacingOccurrences(of: "candidate_list_layout: linear", with: "candidate_list_layout: stacked")
        try inline.write(to: shared.appending(path: "scribe_inline.schema.yaml"), atomically: true, encoding: .utf8)
        let dark = schema.components(separatedBy: "\nstyle:")[0]
            .replacingOccurrences(of: "schema_id: scribe_test", with: "schema_id: scribe_dark") + """

        style:
          color_scheme: test_light
          color_scheme_dark: test_dark
        preset_color_schemes:
          test_light:
            inline_preedit: true
          test_dark:
            inline_preedit: false

        """
        try dark.write(to: shared.appending(path: "scribe_dark.schema.yaml"), atomically: true, encoding: .utf8)
        try """
        config_version: "1"
        schema_list:
          - schema: scribe_test
          - schema: scribe_inline
          - schema: scribe_dark

        """.write(to: shared.appending(path: "default.yaml"), atomically: true, encoding: .utf8)
        engine.notificationHandler = nil
        engine.start(RimeConfiguration(sharedDataDirectory: shared, userDataDirectory: user,
                                       minimumLogLevel: 2, appName: "rime.scribe-state-tests"))
        #expect(engine.deploy())
        service.startMaintenance(fullCheck: true)
        engine.joinMaintenance()
        service.loadAppearance()
    }

    func makeClient(schema: String, bundleID: String = "example.Editor") throws -> Client {
        let adapter = service.makeAdapter()
        adapter.activate(capsLockOn: false)
        let id = try #require(adapter.sessionID)
        #expect(engine.selectSchema(schema, in: id))
        let client = Client(adapter: adapter, text: RecordingClient(bundleIdentifier: bundleID), id: id)
        clients.append(client)
        return client
    }

    func activate(_ client: Client) {
        client.adapter.activate(capsLockOn: false, client: client.text)
    }

    func type(_ text: String, into client: Client) {
        for character in text {
            let text = String(character)
            _ = client.adapter.handle(KeyInput(kind: .keyDown, keyCode: 45, characters: text,
                                               charactersIgnoringModifiers: text, flags: []), client: client.text)
        }
    }

    func close() {
        for client in clients { client.adapter.close() }
        engine.notificationHandler = nil
        engine.stop()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor private final class RecordingPanel: FrontendPanel {
    var appearance = Appearance(light: Theme(), dark: nil)
    weak var delegate: (any CandidatePanelDelegate)?
    var visible = false
    var snapshot: CandidateSnapshot?
    var messages: [String] = []
    func prepare() {}
    func show(_ snapshot: CandidateSnapshot, near caretRect: NSRect) { self.snapshot = snapshot; visible = true }
    func hide() { visible = false }
    func showStatus(_ message: String, near caretRect: NSRect) { messages.append(message); visible = true }
}

@MainActor private final class RecordingClient: TextClient {
    let bundleIdentifier: String
    var marked = MarkedText.empty
    var commits: [String] = []
    init(bundleIdentifier: String) { self.bundleIdentifier = bundleIdentifier }
    func insertText(_ text: String) { commits.append(text); marked = .empty }
    func setMarkedText(_ text: MarkedText) { marked = text }
    func caretRect() -> NSRect { NSRect(x: 200, y: 300, width: 1, height: 20) }
}
