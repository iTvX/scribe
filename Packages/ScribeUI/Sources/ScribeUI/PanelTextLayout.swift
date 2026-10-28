import AppKit
import CoreText

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
        let content: NSAttributedString
        if #available(macOS 27.2, *), vertical {
            content = Self.resolvingFallbackFonts(in: text)
        } else {
            content = text
        }
        textView.textContentStorage!.attributedString = content
        textView.setLayoutOrientation(vertical ? .vertical : .horizontal)
    }

    /// Avoid the incorrect glyphs observed with implicit font cascades in
    /// vertical TextKit layout on macOS 27.2. Concrete font descriptors give
    /// layout and drawing the same font, including its metrics. Keep whole
    /// grapheme clusters together (including emoji and combining accents).
    static func resolvingFallbackFonts(in text: NSAttributedString) -> NSAttributedString {
        let resolved = NSMutableAttributedString(attributedString: text)
        let string = text.string as NSString
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            var offset = range.location
            while offset < NSMaxRange(range) {
                let cluster = NSIntersectionRange(string.rangeOfComposedCharacterSequence(at: offset), range)
                let fallback = CTFontCreateForString(font as CTFont, string as CFString,
                                                     CFRange(location: cluster.location, length: cluster.length))
                let face = CTFontCopyPostScriptName(fallback) as String
                let concrete = NSFont(name: face, size: font.pointSize) ?? (fallback as NSFont)
                if face != font.fontName { resolved.addAttribute(.font, value: concrete, range: cluster) }
                offset = NSMaxRange(cluster)
            }
        }
        return resolved
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

    /// The index of the character under `point`, in text container
    /// coordinates; nil between or beside lines.
    func characterIndex(at point: CGPoint) -> Int? {
        guard let fragment = textLayoutManager.textLayoutFragment(for: point) else { return nil }
        let frame = fragment.layoutFragmentFrame
        let inFragment = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        let start = textLayoutManager.offset(from: textLayoutManager.documentRange.location, to: fragment.rangeInElement.location)
        guard let line = fragment.textLineFragments.first(where: { $0.typographicBounds.contains(inFragment) }) else { return nil }
        let bounds = line.typographicBounds
        return start + line.characterIndex(for: CGPoint(x: inFragment.x - bounds.minX, y: inFragment.y - bounds.minY))
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
