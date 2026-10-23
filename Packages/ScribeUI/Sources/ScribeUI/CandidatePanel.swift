import AppKit

/// The candidate window. Holds no input state: it only shows what it is given.
///
/// A placeholder for now; nothing is drawn yet.
@MainActor
public final class CandidatePanel {
    public private(set) var isVisible = false

    public init() {}

    public func hide() {
        isVisible = false
    }
}
