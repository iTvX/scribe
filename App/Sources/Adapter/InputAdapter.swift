import AppKit
import ScribeCore

/// The text field Scribe types into.
@MainActor
protocol TextClient {
    /// Inserts committed text, replacing any marked text.
    func insertText(_ text: String)
    /// Replaces the marked text; empty text removes it. `caret` counts
    /// UTF-16 code units.
    func setMarkedText(_ text: String, caret: Int)
    /// The caret line, in screen coordinates.
    func caretRect() -> NSRect
}

@MainActor
protocol CandidatePresenting {
    func show(_ snapshot: CandidateSnapshot, near caretRect: NSRect)
    func hide()
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
    var charactersIgnoringModifiers: String?
    var flags: MacModifierFlags

    init(kind: Kind, keyCode: UInt16, charactersIgnoringModifiers: String?, flags: MacModifierFlags) {
        self.kind = kind
        self.keyCode = keyCode
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.flags = flags
    }

    init(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            self.init(
                kind: .keyDown,
                keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                flags: Self.flags(event.modifierFlags)
            )
        case .flagsChanged:
            self.init(kind: .flagsChanged, keyCode: event.keyCode, charactersIgnoringModifiers: nil, flags: Self.flags(event.modifierFlags))
        default:
            self.init(kind: .other, keyCode: 0, charactersIgnoringModifiers: nil, flags: [])
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

    init(session: InputSession, candidates: CandidatePresenting) {
        self.session = session
        self.candidates = candidates
    }

    /// Returns whether the key was consumed. Modifier changes always reach
    /// the client too, so its idea of the held modifiers stays right.
    func handle(_ input: KeyInput, client: TextClient) -> Bool {
        switch input.kind {
        case .keyDown:
            modifiers = input.flags
            guard let key = MacKeyTranslator.keyDown(
                keyCode: input.keyCode,
                charactersIgnoringModifiers: input.charactersIgnoringModifiers,
                flags: input.flags
            ) else { return false }
            let result = session.handle(key)
            apply(result.actions, to: client)
            return result.handled
        case .flagsChanged:
            for key in MacKeyTranslator.flagsChanged(keyCode: input.keyCode, from: modifiers, to: input.flags) {
                apply(session.handle(key).actions, to: client)
            }
            modifiers = input.flags
            return false
        case .other:
            return false
        }
    }

    /// Commits whatever is being composed, as when the client loses focus.
    func commitComposition(client: TextClient) {
        apply(session.commitComposition(), to: client)
    }

    /// The input method is no longer active for this client.
    func deactivate(client: TextClient) {
        commitComposition(client: client)
        candidates.hide()
    }

    func close() {
        session.close()
        candidates.hide()
    }

    func apply(_ actions: [SessionAction], to client: TextClient) {
        for action in actions {
            switch action {
            case .commit(let text):
                client.insertText(text)
            case .setMarkedText(let marked):
                client.setMarkedText(marked.text, caret: marked.caret)
            case .showCandidates(let snapshot):
                candidates.show(snapshot, near: client.caretRect())
            case .hideCandidates:
                candidates.hide()
            }
        }
    }
}
