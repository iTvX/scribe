import AppKit
import InputMethodKit

/// The InputMethodKit controller, one per client text input session. A thin
/// shell: the work happens in `InputAdapter`.
///
/// InputMethodKit calls these methods on the main thread. They hand the main
/// actor only Sendable values: the copied key, the client, and `state`.
@objc(ScribeInputController)
final class ScribeInputController: IMKInputController {
    private let state = ControllerState()

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = IMKTextClient(sender) else { return false }
        let input = KeyInput(event)
        let state = state
        return MainActor.assumeIsolated {
            state.adapter.handle(input, client: client)
        }
    }

    override func activateServer(_ sender: Any!) {
        Log.input.info("Activated for \(IMKTextClient(sender)?.bundleIdentifier ?? "unknown client", privacy: .public)")
        // This process only sees its own modifier events; ask the session
        // for the Caps Lock state.
        let capsLockOn = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        let state = state
        let layout = MainActor.assumeIsolated {
            state.adapter.activate(capsLockOn: capsLockOn)
            RimeService.shared.activated(state.adapter)
            return state.adapter.configuration.keyboardLayout
        }
        // keyboard_layout, as Squirrel applies it.
        if case .named(let id) = layout {
            IMKTextClient(sender)?.overrideKeyboard(named: id)
        }
    }

    override func deactivateServer(_ sender: Any!) {
        guard let client = IMKTextClient(sender) else { return }
        Log.input.info("Deactivated for \(client.bundleIdentifier, privacy: .public)")
        let state = state
        MainActor.assumeIsolated {
            state.deactivate(client: client)
        }
    }

    override func menu() -> NSMenu! {
        // InputMethodKit asks on the main thread; the controller is the
        // target it sends the menu's actions to.
        nonisolated(unsafe) let target = self
        nonisolated(unsafe) var menu: NSMenu?
        MainActor.assumeIsolated {
            menu = InputMenu.make(target: target)
        }
        return menu
    }

    @objc func deploy(_ sender: Any?) {
        MainActor.assumeIsolated {
            RimeService.shared.request(.reload)
        }
    }

    @objc func syncUserData(_ sender: Any?) {
        MainActor.assumeIsolated {
            RimeService.shared.request(.sync)
        }
    }

    @objc func openLogs(_ sender: Any?) {
        MainActor.assumeIsolated {
            RimeService.shared.open(.logs)
        }
    }

    @objc func openUserFolder(_ sender: Any?) {
        MainActor.assumeIsolated {
            RimeService.shared.open(.userFolder)
        }
    }

    @objc func openHelp(_ sender: Any?) {
        MainActor.assumeIsolated {
            RimeService.shared.open(.help)
        }
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = IMKTextClient(sender) else { return }
        let state = state
        MainActor.assumeIsolated {
            state.existingAdapter?.commitComposition(client: client)
        }
    }
}

/// A controller's adapter, created on first use.
@MainActor
private final class ControllerState: Sendable {
    private(set) var existingAdapter: InputAdapter?

    nonisolated init() {}

    var adapter: InputAdapter {
        if let existingAdapter {
            return existingAdapter
        }
        let adapter = RimeService.shared.makeAdapter()
        existingAdapter = adapter
        return adapter
    }

    /// The Rime session ends with the activation; the next key starts a new
    /// one.
    func deactivate(client: TextClient) {
        existingAdapter?.deactivate(client: client)
        existingAdapter?.close()
        existingAdapter = nil
    }
}
