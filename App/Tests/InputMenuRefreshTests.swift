import Foundation
import Testing

private let hans = "io.github.itvx.inputmethod.Scribe.Hans"
private let hant = "io.github.itvx.inputmethod.Scribe.Hant"
private let layout = "com.apple.keylayout.ABC"

@MainActor
@Suite struct InputMenuRefreshTests {
    private func system(enabled: Set<String> = [hans]) -> FakeInputSources {
        let system = FakeInputSources(enabled: enabled)
        system.currentInputSourceID = enabled.contains(hans) ? hans : hant
        system.disabledKeyboardLayoutForRefresh = layout
        system.sources[layout] = InputSourceState(isEnabled: false, isSelectable: true, isSelected: false)
        return system
    }

    @Test(arguments: [Set([hans]), Set([hant]), Set([hans, hant])])
    func restoresLayoutWithoutChangingAnyScribeModes(enabled: Set<String>) {
        let system = system(enabled: enabled)
        let before = system.sources
        let selected = system.currentInputSourceID
        #expect(InputSourceInstaller(system: system).refreshMenu { system.log.append("settle") })
        #expect(system.log == ["enable \(layout)", "settle", "disable \(layout)"])
        #expect(system.sources == before)
        #expect(system.currentInputSourceID == selected)
    }

    @Test func aDisabledInputMethodIsNeverEnabledByInstallation() {
        let system = system(enabled: [])
        #expect(InputSourceInstaller(system: system).refreshMenu { Issue.record("unexpected wait") })
        #expect(system.log.isEmpty)
    }

    @Test func missingControlLayoutLeavesEverythingAlone() {
        let system = system()
        system.disabledKeyboardLayoutForRefresh = nil
        #expect(!InputSourceInstaller(system: system).refreshMenu())
        #expect(system.log.isEmpty)
    }

    @Test func noActiveUserContextLeavesEverythingAlone() {
        let system = system()
        system.currentInputSourceID = nil
        #expect(!InputSourceInstaller(system: system).refreshMenu())
        #expect(system.log.isEmpty)
    }

    @Test func aLayoutEnabledBySomeoneElseIsNotDisabled() {
        let system = system()
        system.sources[layout]?.isEnabled = true
        #expect(!InputSourceInstaller(system: system).refreshMenu())
        #expect(system.log.isEmpty)
    }

    @Test func aSilentEnableFailureIsNotReportedAsSuccess() {
        let system = system()
        system.enableHasEffect = false
        #expect(!InputSourceInstaller(system: system).refreshMenu { Issue.record("unexpected wait") })
        #expect(system.log == ["enable \(layout)"])
        #expect(system.sources[layout]?.isEnabled == false)
    }

    @Test func partialEnableFailureStillRestoresTheLayout() {
        let system = system()
        system.status = -50
        #expect(!InputSourceInstaller(system: system).refreshMenu { Issue.record("unexpected wait") })
        #expect(system.log == ["enable \(layout)", "disable \(layout)"])
        #expect(system.sources[layout]?.isEnabled == false)
    }

    @Test func aSilentDisableFailureIsReported() {
        let system = system()
        system.disableHasEffect = false
        #expect(!InputSourceInstaller(system: system).refreshMenu {})
        #expect(system.sources[layout]?.isEnabled == true)
    }

    @Test func respectsAUserSelectingTheTemporaryLayout() {
        let system = system()
        #expect(!InputSourceInstaller(system: system).refreshMenu {
            system.currentInputSourceID = layout
            system.sources[layout]?.isSelected = true
        })
        #expect(system.log == ["enable \(layout)"])
        #expect(system.sources[layout]?.isEnabled == true)
    }

    @Test func respectsAUserSwitchingToAnotherSource() {
        let system = system()
        #expect(InputSourceInstaller(system: system).refreshMenu {
            system.currentInputSourceID = "im.rime.inputmethod.Squirrel.Hans"
        })
        #expect(system.currentInputSourceID == "im.rime.inputmethod.Squirrel.Hans")
        #expect(system.log == ["enable \(layout)", "disable \(layout)"])
    }
}
