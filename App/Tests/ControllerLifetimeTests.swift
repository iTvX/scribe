import AppKit
import Carbon
import InputMethodKit
import RimeKit
import ScribeCore
import ScribeTestSupport
import ScribeUI
import Testing

// The real IMK controller and client wrapper are compiled into this target.
// Process-wide services are fakes so the test cannot touch a user dictionary.
@MainActor final class RimeService {
    static let shared = RimeService()
    let engine = FakeRimeEngine()
    let panel = CallLog()
    weak var lastAdapter: InputAdapter?
    enum Place { case logs, userFolder, help }
    func makeAdapter() -> InputAdapter {
        let adapter = InputAdapter(session: InputSession(engine: engine), candidates: panel)
        lastAdapter = adapter
        return adapter
    }
    func activated(_ adapter: InputAdapter) {}
    func request(_ task: MaintenanceQueue.Task) {}
    func open(_ place: Place) {}
    func openSettings() {}
}
@MainActor final class SoftwareUpdater {
    static let shared = SoftwareUpdater()
    var isAvailable: Bool { false }
    func checkForUpdates() {}
}

final class AuditTextInput: NSObject, IMKTextInput {
    func insertText(_ string: Any!, replacementRange: NSRange) {}
    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {}
    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! { nil }
    func length() -> Int { 0 }
    func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { 0 }
    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
        lineRect?.pointee = .zero
        return [:]
    }
    func validAttributesForMarkedText() -> [Any]! { [] }
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
    func selectMode(_ modeIdentifier: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { "example.scribe-investigation" }
    func windowLevel() -> CGWindowLevel { 0 }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "scribe-investigation-client" }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { "" }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer!) -> NSRect { .zero }
}

@MainActor @Suite(.serialized) struct ControllerLifetimeTests {
    @Test(arguments: [true, false])
    func releasingTheControllerShouldReleaseItsRimeSession(deactivate: Bool) async {
        let client = AuditTextInput()
        var controller: ScribeInputController? = ScribeInputController()
        weak var observed = controller
        controller?.activateServer(client)
        // A Command shortcut is passed through, but records the real IMKTextClient.
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
            characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        _ = controller?.handle(event, client: client)
        if deactivate { controller?.deactivateServer(client) }
        controller = nil
        for _ in 0..<5 { await Task.yield() }
        #expect(observed == nil)
        #expect(RimeService.shared.engine.liveSessionCount == 0)
        // Also release a failed test fixture without leaving engine sessions.
        RimeService.shared.lastAdapter?.close()
        for _ in 0..<5 { await Task.yield() }
        observed = nil
    }
}
