import Foundation
import RimeKit
import ScribeConfig
import ScribeCore
import ScribeTestSupport
import Testing

/// Every app in the app_options table of SharedSupport/squirrel.yaml behaves
/// as its options promise, one test per app.
@MainActor
@Suite struct AppOptionsTableTests {
    nonisolated static let bundleIDs = [
        "com.apple.Spotlight", "com.alfredapp.Alfred", "com.runningwithcrayons.Alfred-2", "com.blacktree.Quicksilver",
        "com.apple.Terminal", "org.alacritty", "com.googlecode.iterm2", "org.vim.MacVim", "com.apple.dt.Xcode",
        "com.barebones.textwrangler", "com.macromates.TextMate.preview", "com.github.atom", "com.microsoft.VSCode",
        "com.sublimetext.2", "org.gnu.Aquamacs", "org.gnu.Emacs", "co.zeit.hyper", "com.google.Chrome",
        "com.microsoft.edgemac", "ru.keepcoder.Telegram",
    ]

    static func table() throws -> AppOptions {
        let file = URL(filePath: #filePath)
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // repository root
            .appending(path: "SharedSupport/squirrel.yaml")
        let yaml = try String(contentsOf: file, encoding: .utf8)
        return try #require(TestRime.engine.withConfig(.yaml(yaml)) { ScribeSettings(squirrel: $0).appOptions })
    }

    /// A new app in the table needs a test here.
    @Test func theTableListsTheseApps() throws {
        #expect(Set(try Self.table().byBundleID.keys) == Set(Self.bundleIDs))
    }

    @Test(arguments: bundleIDs)
    func appBehavesAsItsOptionsSay(bundleID: String) throws {
        let options = try Self.table().options(for: bundleID)
        #expect(!options.isEmpty)
        for (option, value) in options.sorted(by: { $0.key < $1.key }) {
            #expect(value, "\(option) is off; only options that are on have behavior to check")
            switch option {
            case "ascii_mode": startsInASCII(bundleID, options)
            case "no_inline": showsTheInputInTheWindow(bundleID, options)
            case "inline": showsTheInputInlineAnyway(bundleID, options)
            case "vim_mode": leavesInsertModeInASCII(bundleID, options)
            case "force_marked_text_for_direct_commit": marksTextBeforeADirectCommit(bundleID, options)
            default: Issue.record("no behavior test for \(option)")
            }
        }
    }

    // One client of an app, typing through the adapter.
    @MainActor
    struct Client {
        let log = CallLog()
        let chordTimer = ManualChordTimer()
        let session: InputSession
        let adapter: InputAdapter

        init(_ bundleID: String, _ options: [String: Bool], inlinePreedit: Bool = true) {
            session = InputSession(engine: FakeRimeEngine(), chordTimer: chordTimer)
            adapter = InputAdapter(session: session, candidates: log)
            var configuration = SessionConfiguration()
            configuration.appOptions = AppOptions(byBundleID: [bundleID: options])
            configuration.presentation.inlinePreedit = inlinePreedit
            adapter.configuration = configuration
            log.bundleIdentifier = bundleID
            session.setClientApp(configuration.clientApp(bundleID))
        }

        /// Typing in Chinese, whatever the app starts in.
        func leaveASCIIMode() {
            session.setOption("ascii_mode", false)
            log.calls.removeAll()
        }

        func type(_ key: String, code: UInt16) -> Bool {
            adapter.handle(KeyInput(kind: .keyDown, keyCode: code, characters: key, charactersIgnoringModifiers: key, flags: []), client: log)
        }
    }

    func startsInASCII(_ bundleID: String, _ options: [String: Bool]) {
        let client = Client(bundleID, options)
        #expect(!client.type("n", code: 45), "\(bundleID): n goes to the app")
        #expect(client.adapter.isASCIIMode == true, "\(bundleID)")
    }

    func showsTheInputInTheWindow(_ bundleID: String, _ options: [String: Bool]) {
        let client = Client(bundleID, options)
        client.leaveASCIIMode()
        _ = client.type("n", code: 45)
        #expect(client.log.calls.first == "mark 　|0", "\(bundleID): \(client.log.calls)")
    }

    func showsTheInputInlineAnyway(_ bundleID: String, _ options: [String: Bool]) {
        let client = Client(bundleID, options, inlinePreedit: false)
        client.leaveASCIIMode()
        _ = client.type("n", code: 45)
        #expect(client.log.calls.first == "mark n|1", "\(bundleID): \(client.log.calls)")
    }

    func leavesInsertModeInASCII(_ bundleID: String, _ options: [String: Bool]) {
        let client = Client(bundleID, options)
        client.leaveASCIIMode()
        #expect(!client.type("\u{1b}", code: 53), "\(bundleID): Escape goes to the app")
        #expect(client.adapter.isASCIIMode == true, "\(bundleID)")
    }

    func marksTextBeforeADirectCommit(_ bundleID: String, _ options: [String: Bool]) {
        let client = Client(bundleID, options)
        client.leaveASCIIMode()
        // The fake engine commits chords directly, without marked text.
        client.session.setOption("_chord_typing", true)
        _ = client.type("a", code: 0)
        _ = client.type("s", code: 1)
        client.log.calls.removeAll()
        client.chordTimer.fire()
        #expect(client.log.calls.prefix(2) == ["mark as|2", "insert as"], "\(bundleID): \(client.log.calls)")
    }
}
