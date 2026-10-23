import AppKit
import ScribeConfig
import ScribeCore

/// What the user does with the mouse in the candidate window.
@MainActor
public protocol CandidatePanelDelegate: AnyObject {
    /// A click on a candidate of the current page: pressed and released on
    /// the same one.
    func candidatePanel(_ panel: CandidatePanel, didSelectCandidateAt index: Int)
    /// A click on a paging arrow, a scroll, or a horizontal swipe.
    func candidatePanel(_ panel: CandidatePanel, didRequestPage direction: PageDirection)
    /// A click on the preedit before or after the caret: one step that way.
    func candidatePanel(_ panel: CandidatePanel, didRequestCaretMove direction: CaretMove)
}

/// The candidate window, drawn and placed like Squirrel's. Holds no input
/// state: it shows what it is given next to the caret, without taking focus
/// from the client, and reports clicks and scrolls to its delegate.
@MainActor
public final class CandidatePanel {
    public weak var delegate: (any CandidatePanelDelegate)?
    /// The themes to draw with; dark mode uses the dark one when there is
    /// one.
    public var appearance = Appearance(light: Theme(), dark: nil)
    public private(set) var isVisible = false

    /// How long a status message stays up.
    var statusDuration: Duration = .seconds(1.2)
    /// The system colours for an appearance; tests pass fixed ones.
    var palette: (NSAppearance) -> SystemPalette = { SystemPalette(resolvingIn: $0) }

    private lazy var window = makeWindow()
    private let panelView = PanelView()
    private let backdrop = PanelBackground.makeView()
    private let backdropMask = CAShapeLayer()

    private var content = PanelContent(nil)
    private var caretRect = NSRect.zero
    /// The row Rime highlights, or the one last pressed.
    private var highlightedIndex = 0
    /// The row drawn highlighted, which follows the mouse.
    private(set) var displayedIndex = 0
    private var pressedPage: PageDirection?
    private var memorizedLength: CGFloat = 0
    private var scrollPager = ScrollPager()
    private var statusTask: Task<Void, Never>?

    public init() {}

    /// Shows `snapshot` next to the caret. `caretRect` is in screen
    /// coordinates, as InputMethodKit reports it. With nothing to show the
    /// window hides, unless a status message is still up.
    public func show(_ snapshot: CandidateSnapshot, near caretRect: NSRect) {
        let content = PanelContent(snapshot)
        guard PanelText(content, theme: currentTheme().theme) != nil else {
            if statusTask == nil {
                hide()
            }
            return
        }
        cancelStatus()
        self.content = content
        self.caretRect = caretRect
        highlightedIndex = snapshot.highlightedIndex
        display(highlighting: highlightedIndex)
    }

    /// Shows `message` alone, such as a new input mode, for a moment.
    public func showStatus(_ message: String, near caretRect: NSRect) {
        guard !message.isEmpty else { return }
        cancelStatus()
        content = PanelContent(nil, statusMessage: message)
        self.caretRect = caretRect
        display(highlighting: -1)
        statusTask = Task { [weak self, statusDuration] in
            try? await Task.sleep(for: statusDuration)
            guard !Task.isCancelled else { return }
            self?.statusTask = nil
            self?.hide()
        }
    }

    public func hide() {
        cancelStatus()
        if isVisible {
            window.orderOut(nil)
        }
        isVisible = false
        memorizedLength = 0
        pressedPage = nil
    }

    private func cancelStatus() {
        statusTask?.cancel()
        statusTask = nil
    }

    // MARK: Showing

    /// The theme for the current system appearance, and the appearance the
    /// window draws in.
    private func currentTheme() -> (theme: PanelTheme, appearance: NSAppearance) {
        let systemAppearance = NSApplication.shared.effectiveAppearance
        let isDark = systemAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let windowAppearance = appearance.forcesLightAppearance ? NSAppearance(named: .aqua)! : systemAppearance
        return (PanelTheme(appearance.theme(isDark: isDark), palette: palette(windowAppearance)), windowAppearance)
    }

    /// Lays out, places and shows the window, with row `index` highlighted.
    private func display(highlighting index: Int) {
        let (theme, windowAppearance) = currentTheme()
        var content = content
        content.snapshot?.highlightedIndex = index
        guard let text = PanelText(content, theme: theme) else {
            hide()
            return
        }
        displayedIndex = index

        let screen = Self.screenFrame(containing: caretRect.origin)
        let sizing = panelView.update(text, theme: theme, screen: screen)
        let placement = PanelPlacement.place(PanelPlacement.Input(
            caret: caretRect,
            screen: screen,
            size: sizing.size,
            contentRect: sizing.contentRect,
            isOversized: sizing.isOversized,
            preeditHeight: sizing.preeditHeight,
            vertical: theme.vertical,
            memorizeSize: theme.memorizeSize,
            edgeInset: theme.edgeInset,
            pagingOffset: theme.pagingOffset,
            memorizedLength: memorizedLength
        ))
        memorizedLength = placement.memorizedLength

        window.appearance = windowAppearance
        window.setFrame(placement.frame, display: false)
        // The content view draws at the natural size and scales to the
        // window, which is smaller only for oversized panels.
        let contentView = window.contentView!
        contentView.frame = NSRect(origin: .zero, size: placement.frame.size)
        contentView.bounds = NSRect(origin: .zero, size: placement.size)
        if theme.vertical {
            contentView.boundsRotation = -90
            contentView.setBoundsOrigin(NSPoint(x: 0, y: placement.size.width))
        } else {
            contentView.boundsRotation = 0
            contentView.setBoundsOrigin(.zero)
        }
        // Read back after rotating: AppKit swaps the bounds in vertical mode.
        let viewFrame = contentView.bounds
        panelView.frame = viewFrame

        if theme.translucency {
            var backdropFrame = viewFrame
            backdropFrame.size.width += theme.pagingOffset
            backdrop.frame = backdropFrame
            backdrop.appearance = NSApplication.shared.effectiveAppearance
            backdropMask.path = panelView.outline()
            backdrop.isHidden = false
        } else {
            backdrop.isHidden = true
        }

        window.alphaValue = theme.alpha
        window.displayIfNeeded()
        window.invalidateShadow()
        window.orderFront(nil)
        isVisible = true
    }

    /// The screen under `point`, else the main screen, as Squirrel picks it.
    private static func screenFrame(containing point: NSPoint) -> NSRect {
        NSScreen.screens.first { $0.frame.contains(point) }?.frame
            ?? NSScreen.main?.frame
            ?? PanelRenderer.referenceScreen
    }

    private func makeWindow() -> PanelWindow {
        let window = PanelWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.eventHandler = { [weak self] event in self?.handle(event) }

        let contentView = NSView()
        contentView.wantsLayer = true
        backdrop.wantsLayer = true
        backdrop.layer?.mask = backdropMask
        backdrop.isHidden = true
        contentView.addSubview(backdrop)
        contentView.addSubview(panelView)
        panelView.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: panelView
        ))
        window.contentView = contentView
        return window
    }

    // MARK: Mouse

    private func handle(_ event: NSEvent) {
        let point = { [panelView] in panelView.convert(event.locationInWindow, from: nil) }
        switch event.type {
        case .leftMouseDown:
            mouseDown(at: point())
        case .leftMouseUp:
            mouseUp(at: point())
        case .mouseEntered:
            window.acceptsMouseMovedEvents = true
        case .mouseExited:
            window.acceptsMouseMovedEvents = false
            mouseExited()
        case .mouseMoved:
            mouseMoved(to: point())
        case .scrollWheel:
            if let direction = scrollPager.page(for: ScrollPager.Event(event), vertical: currentTheme().theme.vertical) {
                delegate?.candidatePanel(self, didRequestPage: direction)
            }
        default:
            break
        }
    }

    private var candidateCount: Int {
        content.snapshot?.entries.count ?? 0
    }

    func mouseDown(at point: CGPoint) {
        let hit = panelView.hit(at: point)
        pressedPage = hit.page
        if let index = hit.candidate, index >= 0, index < candidateCount {
            highlightedIndex = index
        }
    }

    func mouseUp(at point: CGPoint) {
        let hit = panelView.hit(at: point)
        if let page = hit.page, page == pressedPage {
            delegate?.candidatePanel(self, didRequestPage: page)
        } else {
            pressedPage = nil
        }
        if let index = hit.preeditIndex, let preedit = content.snapshot?.preedit, index >= 0, index < (preedit.text as NSString).length {
            if index < preedit.caret {
                delegate?.candidatePanel(self, didRequestCaretMove: .towardStart)
            } else if index > preedit.caret {
                delegate?.candidatePanel(self, didRequestCaretMove: .towardEnd)
            }
        }
        if let index = hit.candidate, index == highlightedIndex, index >= 0, index < candidateCount {
            delegate?.candidatePanel(self, didSelectCandidateAt: index)
        }
    }

    /// Highlights the row under the mouse, only in the window.
    func mouseMoved(to point: CGPoint) {
        if let index = panelView.hit(at: point).candidate, index != displayedIndex, index >= 0, index < candidateCount {
            display(highlighting: index)
        }
    }

    func mouseExited() {
        if displayedIndex != highlightedIndex {
            display(highlighting: highlightedIndex)
        }
        pressedPage = nil
    }

    /// The panel view, for tests.
    var view: PanelView {
        panelView
    }

    /// The window frame, for tests.
    var frame: NSRect {
        window.frame
    }

    /// The window's content view, for tests.
    var contentView: NSView? {
        window.contentView
    }

    /// The scale of the window's screen, for tests.
    var backingScale: CGFloat {
        window.backingScaleFactor
    }
}

/// A panel that never becomes key and hands mouse events to the candidate
/// panel before the usual handling.
private final class PanelWindow: NSPanel {
    var eventHandler: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool {
        false
    }

    override func sendEvent(_ event: NSEvent) {
        eventHandler?(event)
        super.sendEvent(event)
    }
}
