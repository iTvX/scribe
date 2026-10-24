import Foundation
import ScribeCore
import Testing

/// Text Input Sources as a test sees them; nothing reaches the real system.
@MainActor
final class FakeInputSources: InputSourceSystem {
    var sources: [String: InputSourceState] = [:]
    var log: [String] = []
    var status: OSStatus = 0
    var currentInputSourceID: String?

    /// `bundlePath` is where the registered sources come from.
    init(registered: Bool = true, enabled: Set<String> = [], selected: String? = nil,
         bundlePath: String? = "/Library/Input Methods/Scribe.app") {
        if registered {
            for id in [InputSourceInstaller.bundleIdentifier, hansID, hantID] {
                sources[id] = InputSourceState(
                    isEnabled: enabled.contains(id),
                    isSelectable: id != InputSourceInstaller.bundleIdentifier,
                    isSelected: id == selected,
                    bundlePath: bundlePath
                )
            }
        }
    }

    func state(of id: String) -> InputSourceState? {
        sources[id]
    }

    func register(_ bundleURL: URL) -> OSStatus {
        log.append("register \(bundleURL.lastPathComponent)")
        return status
    }

    func enable(_ id: String) -> OSStatus {
        log.append("enable \(id)")
        sources[id]?.isEnabled = true
        return status
    }

    func disable(_ id: String) -> OSStatus {
        log.append("disable \(id)")
        sources[id]?.isEnabled = false
        return status
    }

    func select(_ id: String) -> OSStatus {
        log.append("select \(id)")
        return status
    }
}

private let hansID = "io.github.itvx.inputmethod.Scribe.Hans"
private let hantID = "io.github.itvx.inputmethod.Scribe.Hant"
private let app = URL(filePath: "/Library/Input Methods/Scribe.app")

@MainActor
@Suite struct InputSourceInstallerTests {
    @Test func scribeIsCurrentInEitherMode() {
        let system = FakeInputSources()
        for (id, isScribe) in [
            (hansID, true), (hantID, true), ("com.apple.keylayout.ABC", false),
            ("io.github.itvx.inputmethod.ScribeX.Hans", false), (nil, false),
        ] {
            system.currentInputSourceID = id
            #expect(InputSourceInstaller(system: system).isScribeCurrent == isScribe, "\(id ?? "none")")
        }
    }

    @Test func registersWhenNothingIsEnabled() {
        let system = FakeInputSources(registered: false)
        #expect(InputSourceInstaller(system: system).register(bundleURL: app))
        #expect(system.log == ["register Scribe.app"])
    }

    @Test func registrationIsSkippedWhenScribeIsRegisteredFromThisApp() {
        let system = FakeInputSources(enabled: [hansID])
        #expect(InputSourceInstaller(system: system).register(bundleURL: app))
        #expect(system.log.isEmpty)
    }

    /// A development copy in ~/Library replaced by the release in /Library:
    /// the enabled mode still names the old copy, so the new one registers,
    /// and nothing is enabled or selected.
    @Test func aReplacedCopyRegistersTheNewOne() {
        let system = FakeInputSources(enabled: [hansID], bundlePath: "/Users/max/.Trash/Scribe.app")
        #expect(InputSourceInstaller(system: system).register(bundleURL: app))
        #expect(system.log == ["register Scribe.app"])
    }

    @Test func registersWhenTheSystemDoesNotSayWhereFrom() {
        let system = FakeInputSources(enabled: [hansID], bundlePath: nil)
        #expect(InputSourceInstaller(system: system).register(bundleURL: app))
        #expect(system.log == ["register Scribe.app"])
    }

    @Test func theBundleOfAnIconIsTheAppAroundIt() {
        let icon = URL(filePath: "/Library/Input Methods/Scribe.app/Contents/Resources/scribe.pdf")
        #expect(InputSourceState.bundlePath(containing: icon) == "/Library/Input Methods/Scribe.app")
        #expect(InputSourceState.bundlePath(containing: URL(filePath: "/tmp/scribe.pdf")) == nil)
    }

    @Test func registrationFailureIsReported() {
        let system = FakeInputSources(registered: false)
        system.status = -50
        #expect(!InputSourceInstaller(system: system).register(bundleURL: app))
    }

    @Test func enablingWithoutModesEnablesThePrimaryMode() {
        let system = FakeInputSources()
        InputSourceInstaller(system: system).enable([])
        #expect(system.log == ["enable \(hansID)"])
    }

    @Test func enablingWithoutModesKeepsWhatTheUserEnabled() {
        let system = FakeInputSources(enabled: [hantID])
        InputSourceInstaller(system: system).enable([])
        #expect(system.log.isEmpty)
    }

    @Test func enablingNamedModesSkipsEnabledOnes() {
        let system = FakeInputSources(enabled: [hansID])
        InputSourceInstaller(system: system).enable([.hans, .hant])
        #expect(system.log == ["enable \(hantID)"])
    }

    @Test func disablingWithoutModesDisablesAllEnabledModes() {
        let system = FakeInputSources(enabled: [hansID, hantID])
        InputSourceInstaller(system: system).disable([])
        #expect(system.log == ["disable \(hansID)", "disable \(hantID)"])
    }

    @Test func selectingWithoutAModeNeedsThePrimaryEnabled() {
        let system = FakeInputSources()
        InputSourceInstaller(system: system).select(nil)
        #expect(system.log.isEmpty)
    }

    @Test func selectingTheEnabledPrimaryMode() {
        let system = FakeInputSources(enabled: [hansID])
        InputSourceInstaller(system: system).select(nil)
        #expect(system.log == ["select \(hansID)"])
    }

    @Test func selectingANamedModeEnablesItFirst() {
        let system = FakeInputSources()
        InputSourceInstaller(system: system).select(.hant)
        #expect(system.log == ["enable \(hantID)", "select \(hantID)"])
    }

    @Test func selectingTheSelectedModeDoesNothing() {
        let system = FakeInputSources(enabled: [hansID], selected: hansID)
        InputSourceInstaller(system: system).select(.hans)
        #expect(system.log.isEmpty)
    }
}
