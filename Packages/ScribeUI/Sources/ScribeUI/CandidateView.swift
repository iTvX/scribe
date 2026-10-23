import AppKit
import CoreText
import ScribeCore

/// Draws one page of candidates in a row with Core Text, highlighting one.
final class CandidateView: NSView {
    var snapshot = CandidateSnapshot(entries: []) {
        didSet {
            layoutEntries()
            needsDisplay = true
        }
    }

    private static let textFont = NSFont.systemFont(ofSize: 16)
    private static let labelFont = NSFont.systemFont(ofSize: 12)
    private static let padding = NSSize(width: 8, height: 6)
    private static let entrySpacing: CGFloat = 14
    private static let partSpacing: CGFloat = 4
    private static let highlightInset = NSSize(width: 5, height: 3)
    private static let cornerRadius: CGFloat = 7

    /// One candidate's label, text and comment, laid out left to right.
    private struct Entry {
        var parts: [(text: String, font: NSFont, x: CGFloat)]
        var frame: NSRect
    }

    private var entries: [Entry] = []
    private var contentSize = NSSize.zero

    override var isFlipped: Bool {
        true
    }

    override var fittingSize: NSSize {
        contentSize
    }

    /// The frame of each candidate, in view coordinates.
    var entryFrames: [NSRect] {
        entries.map(\.frame)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        NSColor.windowBackgroundColor.setFill()
        background.fill()
        NSColor.separatorColor.setStroke()
        background.stroke()

        for (index, entry) in entries.enumerated() {
            let highlighted = index == snapshot.highlightedIndex
            if highlighted {
                NSColor.selectedContentBackgroundColor.setFill()
                NSBezierPath(
                    roundedRect: entry.frame.insetBy(dx: -Self.highlightInset.width, dy: -Self.highlightInset.height),
                    xRadius: 5,
                    yRadius: 5
                ).fill()
            }
            for (partIndex, part) in entry.parts.enumerated() {
                let isText = partIndex == 1
                let color: NSColor = highlighted ? .alternateSelectedControlTextColor : isText ? .labelColor : .secondaryLabelColor
                let line = Self.line(part.text, font: part.font, color: color)
                context.saveGState()
                // Core Text draws upward; the view is flipped.
                context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
                context.textPosition = CGPoint(x: part.x, y: entry.frame.minY + Self.textFont.ascender)
                CTLineDraw(line, context)
                context.restoreGState()
            }
        }
    }

    private func layoutEntries() {
        var x = Self.padding.width
        entries = snapshot.entries.map { entry in
            var parts: [(text: String, font: NSFont, x: CGFloat)] = []
            var partX = x
            for (text, font) in [(entry.label, Self.labelFont), (entry.text, Self.textFont), (entry.comment ?? "", Self.labelFont)] where !text.isEmpty {
                if !parts.isEmpty {
                    partX += Self.partSpacing
                }
                parts.append((text, font, partX))
                partX += Self.width(of: Self.line(text, font: font, color: .labelColor))
            }
            let frame = NSRect(x: x, y: Self.padding.height, width: partX - x, height: Self.lineHeight)
            x = partX + Self.entrySpacing
            return Entry(parts: parts, frame: frame)
        }
        let width = entries.isEmpty ? 0 : x - Self.entrySpacing + Self.padding.width
        contentSize = NSSize(width: ceil(width), height: ceil(Self.lineHeight + 2 * Self.padding.height))
        setFrameSize(contentSize)
    }

    private static var lineHeight: CGFloat {
        ceil(textFont.ascender - textFont.descender + textFont.leading)
    }

    private static func line(_ string: String, font: NSFont, color: NSColor) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]))
    }

    private static func width(of line: CTLine) -> CGFloat {
        ceil(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
