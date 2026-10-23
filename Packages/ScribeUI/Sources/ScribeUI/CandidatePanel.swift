import AppKit
import ScribeCore

/// The candidate window. Holds no input state: it shows the snapshot it is
/// given, next to the caret, without taking focus from the client.
@MainActor
public final class CandidatePanel {
    public private(set) var isVisible = false

    private lazy var panel = makePanel()
    private let candidateView = CandidateView()

    public init() {}

    /// Shows `snapshot` below the caret, or above it when there is no room.
    /// `caretRect` is in screen coordinates, as InputMethodKit reports it.
    public func show(_ snapshot: CandidateSnapshot, near caretRect: NSRect) {
        candidateView.snapshot = snapshot
        let size = candidateView.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(caretRect.origin) } ?? NSScreen.main
        let frame = CandidatePanelLayout.frame(
            size: size,
            caretRect: caretRect,
            visibleFrame: screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        )
        panel.setFrame(frame, display: true)
        panel.orderFront(nil)
        isVisible = true
    }

    public func hide() {
        if isVisible {
            panel.orderOut(nil)
        }
        isVisible = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = candidateView
        return panel
    }
}

/// Where the candidate window goes relative to the caret.
public enum CandidatePanelLayout {
    /// Space between the caret line and the window.
    public static let gap: CGFloat = 4

    /// Below the caret line, aligned with its left edge; above it when there
    /// is no room below; always inside `visibleFrame`.
    public static func frame(size: NSSize, caretRect: NSRect, visibleFrame: NSRect) -> NSRect {
        var origin = NSPoint(x: caretRect.minX, y: caretRect.minY - gap - size.height)
        if origin.y < visibleFrame.minY {
            origin.y = caretRect.maxY + gap
        }
        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        return NSRect(origin: origin, size: size)
    }
}
