import AppKit

/// Lays out the panel text with TextKit 2 in an `NSTextView` set up like
/// Squirrel's, so lines break and measure the same. The view is never shown:
/// `PanelView` draws the laid-out text itself.
@MainActor
final class PanelTextLayout {
    private let textView = NSTextView(usingTextLayoutManager: true)
    private let lineBreaker = NoBreakDelegate()

    init() {
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textLayoutManager.delegate = lineBreaker
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
    }

    private var textLayoutManager: NSTextLayoutManager {
        textView.textLayoutManager!
    }

    private var textContainer: NSTextContainer {
        textView.textContainer!
    }

    /// Vertical text is laid out in lines along x, like horizontal text;
    /// the panel turns it a quarter turn when drawing.
    func setText(_ text: NSAttributedString, vertical: Bool) {
        textView.textContentStorage!.attributedString = text
        textView.setLayoutOrientation(vertical ? .vertical : .horizontal)
    }

    /// Lays the text out in lines at most `width` long.
    func layOut(width: CGFloat) {
        textContainer.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
    }

    /// The selection rectangles of `range`, one per line, in text container
    /// coordinates.
    func segments(of range: NSRange) -> [CGRect] {
        let documentStart = textLayoutManager.documentRange.location
        guard range.location != NSNotFound,
              let start = textLayoutManager.location(documentStart, offsetBy: range.location),
              let end = textLayoutManager.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return [] }
        var rects: [CGRect] = []
        textLayoutManager.enumerateTextSegments(in: textRange, type: .selection, options: [.rangeNotRequired]) { _, rect, _, _ in
            rects.append(rect)
            return true
        }
        return rects
    }

    /// The area covered by `ranges`, reaching back to the container origin,
    /// as Squirrel sizes the panel.
    func contentRect(of ranges: [NSRange]) -> CGRect {
        var (x0, x1, y0, y1) = (CGFloat.infinity, -CGFloat.infinity, CGFloat.infinity, -CGFloat.infinity)
        for range in ranges where range.location != NSNotFound {
            let rect = PanelGeometry.union(of: segments(of: range))
            x0 = min(rect.minX, x0)
            x1 = max(rect.maxX, x1)
            y0 = min(rect.minY, y0)
            y1 = max(rect.maxY, y1)
        }
        if x1 == -CGFloat.infinity { return .zero }
        return CGRect(x: min(0, x0), y: min(0, y0), width: x1 - min(0, x0), height: y1 - min(0, y0))
    }

    /// Draws the text with the container origin at `origin`, in flipped
    /// coordinates.
    func draw(at origin: CGPoint, in context: CGContext) {
        textLayoutManager.enumerateTextLayoutFragments(from: textLayoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            fragment.draw(at: CGPoint(x: origin.x + frame.minX, y: origin.y + frame.minY), in: context)
            return true
        }
    }
}

/// Keeps lines from breaking before characters marked `.noBreak`.
private final class NoBreakDelegate: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, shouldBreakLineBefore location: any NSTextLocation, hyphenating: Bool) -> Bool {
        let index = textLayoutManager.offset(from: textLayoutManager.documentRange.location, to: location)
        guard let storage = textLayoutManager.textContentManager as? NSTextContentStorage,
              let text = storage.attributedString,
              index >= 0, index < text.length else { return true }
        return text.attribute(.noBreak, at: index, effectiveRange: nil) as? Bool != true
    }
}
