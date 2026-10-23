import AppKit
import Foundation
import Testing

@MainActor
@Test func menuOffersTheMaintenanceCommandsInOrder() {
    let menu = InputMenu.make(target: NSObject())
    #expect(menu.items.map(\.title) == ["Deploy", "Sync user data", "Logs…", "User folder…", "Help…"])
    #expect(menu.items.map(\.action) == [
        InputMenu.Command.deploy.action, InputMenu.Command.sync.action, InputMenu.Command.openLogs.action,
        InputMenu.Command.openUserFolder.action, InputMenu.Command.openHelp.action,
    ])
    // As in Squirrel: Control-Option-` deploys.
    #expect(menu.items[0].keyEquivalent == "`")
    #expect(menu.items[0].keyEquivalentModifierMask == [.control, .option])
}

/// Every string the app shows is translated into English, Simplified and
/// Traditional Chinese.
@Test func everyLanguageHasEveryString() throws {
    let resources = URL(filePath: #filePath)
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // App
        .appending(path: "Resources", directoryHint: .isDirectory)
    var keysByLanguage: [String: Set<String>] = [:]
    for language in ["en", "zh-Hans", "zh-Hant"] {
        let file = resources.appending(path: "\(language).lproj/Localizable.strings")
        let strings = try #require(NSDictionary(contentsOf: file) as? [String: String], "\(language)")
        keysByLanguage[language] = Set(strings.keys)
        #expect(strings.values.allSatisfy { !$0.isEmpty }, "\(language)")
    }
    #expect(keysByLanguage["en"] == keysByLanguage["zh-Hans"])
    #expect(keysByLanguage["en"] == keysByLanguage["zh-Hant"])
    for command in InputMenu.Command.allCases {
        #expect(keysByLanguage["en"]?.contains(command.title) == true, "\(command.title)")
    }
    #expect(keysByLanguage["en"]?.contains(LaunchGuard.warningKey) == true)
    for message in DeployMessage.allCases {
        #expect(keysByLanguage["en"]?.contains(message.key) == true, "\(message.key)")
    }
}

@Suite struct LaunchGuardTests {
    let file = FileManager.default.temporaryDirectory.appending(path: "scribe-launch-test-\(UUID().uuidString)")

    @Test func firstLaunchIsFine() {
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(!LaunchGuard(file: file).isRelaunchTooSoon(now: Date(timeIntervalSince1970: 1000)))
    }

    @Test func relaunchWithinTwoSecondsIsAProblem() {
        defer { try? FileManager.default.removeItem(at: file) }
        let guard_ = LaunchGuard(file: file)
        _ = guard_.isRelaunchTooSoon(now: Date(timeIntervalSince1970: 1000))
        #expect(guard_.isRelaunchTooSoon(now: Date(timeIntervalSince1970: 1001.5)))
    }

    @Test func relaunchLaterIsFine() {
        defer { try? FileManager.default.removeItem(at: file) }
        let guard_ = LaunchGuard(file: file)
        _ = guard_.isRelaunchTooSoon(now: Date(timeIntervalSince1970: 1000))
        #expect(!guard_.isRelaunchTooSoon(now: Date(timeIntervalSince1970: 1003)))
    }

    @Test func aDamagedRecordIsIgnored() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not a date".utf8).write(to: file)
        #expect(!LaunchGuard(file: file).isRelaunchTooSoon(now: Date(timeIntervalSince1970: 1000)))
    }
}
