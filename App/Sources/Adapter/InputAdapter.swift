import AppKit
import RimeKit
import ScribeConfig
import ScribeCore
import ScribeUI

/// The text field Scribe types into.
@MainActor
protocol TextClient {
    /// The application's bundle identifier.
    var bundleIdentifier: String { get }
    /// Inserts committed text, replacing any marked text.
    func insertText(_ text: String)
    /// Replaces the marked text; empty text removes it. `caret` counts
    /// UTF-16 code units.
    func setMarkedText(_ text: String, caret: Int)
    /// The caret line, in screen coordinates.
    func caretRect() -> NSRect
}

/// The candidate window, which every client shares.
@MainActor
protocol CandidatePresenting: AnyObject {
    /// Gets the clicks and scrolls in the window; held weakly.
    var delegate: (any CandidatePanelDelegate)? { get set }
    func show(_ snapshot: CandidateSnapshot, near caretRect: NSRect)
    func hide()
    /// Shows a short message, such as a mode change, that hides by itself.
    func showStatus(_ message: String, near caretRect: NSRect)
}

/// The parts of a key event the adapter uses, copied out of the `NSEvent`
/// so they can be handed to the main actor.
struct KeyInput: Equatable, Sendable {
    enum Kind: Sendable {
        case keyDown
        case flagsChanged
        case other
    }

    var kind: Kind
    var keyCode: UInt16
    var characters: String?
    var charactersIgnoringModifiers: String?
    var flags: MacModifierFlags

    init(kind: Kind, keyCode: UInt16, characters: String?, charactersIgnoringModifiers: String?, flags: MacModifierFlags) {
        self.kind = kind
        self.keyCode = keyCode
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.flags = flags
    }

    init(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            self.init(
                kind: .keyDown,
                keyCode: event.keyCode,
                characters: event.characters,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                flags: Self.flags(event.modifierFlags)
            )
        case .flagsChanged:
            self.init(kind: .flagsChanged, keyCode: event.keyCode, characters: nil, charactersIgnoringModifiers: nil, flags: Self.flags(event.modifierFlags))
        default:
            self.init(kind: .other, keyCode: 0, characters: nil, charactersIgnoringModifiers: nil, flags: [])
        }
    }

    static func flags(_ flags: NSEvent.ModifierFlags) -> MacModifierFlags {
        var result: MacModifierFlags = []
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.capsLock) { result.insert(.capsLock) }
        return result
    }
}

/// Connects one client to one input session: translates key events into
/// Rime keys and applies the session's actions to the client and the
/// candidate window.
@MainActor
final class InputAdapter {
    private let session: InputSession
    private let candidates: CandidatePresenting
    private var modifiers: MacModifierFlags = []
    /// The client of the last event, for actions that come without one,
    /// such as a chord released after a delay.
    private var client: TextClient?
    /// The app's options for its session, from the app's bundle identifier.
    var clientApp: (String) -> InputSession.ClientApp = { InputSession.ClientApp(bundleID: $0) }

    init(session: InputSession, candidates: CandidatePresenting) {
        self.session = session
        self.candidates = candidates
        session.onAsyncActions = { [weak self] actions in
            guard let self, let client = self.client else { return }
            self.apply(actions, to: client)
        }
    }

    var sessionID: RimeSessionID? {
        session.currentSessionID
    }

    /// The input method became active for the client. It gets no modifier
    /// event for keys already locked, so the Caps Lock state comes from the
    /// hardware.
    func activate(capsLockOn: Bool) {
        if capsLockOn {
            modifiers.insert(.capsLock)
        } else {
            modifiers.remove(.capsLock)
        }
    }

    /// Returns whether the key was consumed. Command shortcuts and modifier
    /// changes always reach the client, so its idea of the held modifiers
    /// stays right; an event that changes no modifier is consumed.
    func handle(_ input: KeyInput, client: TextClient) -> Bool {
        self.client = client
        session.setClientApp(clientApp(client.bundleIdentifier))
        switch input.kind {
        case .keyDown:
            guard let key = MacKeyTranslator.keyDown(
                keyCode: input.keyCode,
                characters: input.characters,
                charactersIgnoringModifiers: input.charactersIgnoringModifiers,
                flags: input.flags
            ) else { return false }
            let result = session.handle(key)
            apply(result.actions, to: client)
            return result.handled
        case .flagsChanged:
            guard input.flags != modifiers else { return true }
            for key in MacKeyTranslator.flagsChanged(keyCode: input.keyCode, from: modifiers, to: input.flags) {
                apply(session.handle(key).actions, to: client)
            }
            modifiers = input.flags
            return false
        case .other:
            return false
        }
    }

    /// Commits what was typed, unconverted, as when the client loses focus.
    func commitComposition(client: TextClient) {
        apply(session.commitComposition(), to: client)
    }

    /// Announces an option or schema change of this adapter's session.
    func handle(_ notification: RimeNotification, notifications: NotificationPolicy, messageType: StatusMessageType) {
        guard session.owns(notification.sessionID), let client else { return }
        apply(session.status(for: notification, notifications: notifications, messageType: messageType), to: client)
    }

    /// Turns ASCII mode on or off, as `Scribe --ascii` and `--nascii` ask.
    func setASCIIMode(_ on: Bool) {
        let actions = session.setOption("ascii_mode", on)
        if let client {
            apply(actions, to: client)
        }
    }

    var isASCIIMode: Bool? {
        session.option("ascii_mode")
    }

    /// The input method is no longer active for this client.
    func deactivate(client: TextClient) {
        commitComposition(client: client)
        candidates.hide()
    }

    func close() {
        session.close()
        candidates.hide()
        client = nil
    }

    func apply(_ actions: [SessionAction], to client: TextClient) {
        for action in actions {
            switch action {
            case .commit(let text):
                client.insertText(text)
            case .setMarkedText(let marked):
                client.setMarkedText(marked.text, caret: marked.caret)
            case .showCandidates(let snapshot) where snapshot.entries.isEmpty && snapshot.preedit == nil:
                // The input is shown inline, so there is nothing to show.
                candidates.hide()
            case .showCandidates(let snapshot):
                // The window shows this client's candidates, so clicks in it
                // are for this client.
                candidates.delegate = self
                candidates.show(snapshot, near: client.caretRect())
            case .hideCandidates:
                candidates.hide()
            case .showStatus(let message):
                candidates.showStatus(message, near: client.caretRect())
            }
        }
    }
}

/// Requests from the candidate window, while it shows this adapter's
/// candidates.
extension InputAdapter: CandidatePanelDelegate {
    func candidatePanel(_ panel: CandidatePanel, didSelectCandidateAt index: Int) {
        if let client {
            apply(session.selectCandidate(at: index), to: client)
        }
    }

    func candidatePanel(_ panel: CandidatePanel, didRequestPage direction: PageDirection) {
        if let client {
            apply(session.changePage(direction), to: client)
        }
    }

    func candidatePanel(_ panel: CandidatePanel, didRequestCaretMove direction: CaretMove) {
        if let client {
            apply(session.moveCaret(direction), to: client)
        }
    }
}
