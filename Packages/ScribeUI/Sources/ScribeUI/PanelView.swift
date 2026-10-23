import AppKit

/// What laying out the panel text decided about the panel's size.
struct PanelSizing: Equatable {
    /// The area the text covers, in text container coordinates.
    var contentRect: CGRect
    /// The panel size in screen orientation, before any scaling.
    var size: CGSize
    var isOversized: Bool
    /// The height of the preedit text; nil without a preedit.
    var preeditHeight: CGFloat?
}

/// Draws the candidate panel: backgrounds, border and highlights with Core
/// Graphics, then the text.
///
/// The view is flipped and its x axis runs along the text lines, with the
/// paging strip on the left. A vertical panel is drawn the same way and
/// turned a quarter turn clockwise on screen. Everything is drawn in
/// `draw(_:)`, rather than with Squirrel's shape layers and masks, so an
/// offscreen render is exactly what the window shows.
@MainActor
final class PanelView: NSView {
    private(set) var theme: PanelTheme?
    private(set) var text: PanelText?
    private let textLayout = PanelTextLayout()

    override var isFlipped: Bool {
        true
    }

    /// Sets what to draw and lays the text out for `screen`, as Squirrel
    /// does before showing the panel. The caller sizes the view.
    func update(_ text: PanelText, theme: PanelTheme, screen: CGRect) -> PanelSizing {
        self.text = text
        self.theme = theme
        needsDisplay = true
        textLayout.setText(text.string, vertical: theme.vertical)

        var textWidth = PanelPlacement.maxTextWidth(fontSize: theme.font.pointSize, vertical: theme.vertical, edgeInset: theme.edgeInset, screen: screen)
        textLayout.layOut(width: textWidth)
        var ranges = text.candidateRanges
        if let preeditRange = text.preeditRange, preeditRange.length > 0 {
            ranges.append(preeditRange)
        }
        func naturalSize(_ contentRect: CGRect) -> CGSize {
            PanelPlacement.naturalSize(contentRect: contentRect, edgeInset: theme.edgeInset, pagingOffset: theme.pagingOffset, vertical: theme.vertical)
        }
        var contentRect = textLayout.contentRect(of: ranges)
        var size = naturalSize(contentRect)
        let isOversized = PanelPlacement.isOversized(size, screen: screen)
        if isOversized {
            let wider = PanelPlacement.oversizedTextWidth(contentRect: contentRect, vertical: theme.vertical, screen: screen)
            if wider > textWidth {
                textWidth = wider
                textLayout.layOut(width: textWidth)
                contentRect = textLayout.contentRect(of: ranges)
                size = naturalSize(contentRect)
            }
        }
        let preeditHeight = text.preeditRange.map { PanelGeometry.union(of: textLayout.segments(of: $0)).height }
        return PanelSizing(contentRect: contentRect, size: size, isOversized: isOversized, preeditHeight: preeditHeight)
    }

    /// The view size for a panel of `size` in screen orientation.
    static func viewSize(for size: CGSize, vertical: Bool) -> CGSize {
        vertical ? CGSize(width: size.height, height: size.width) : size
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawPanel(in: context)
    }

    /// Draws the whole panel into `context`, whose user space must be this
    /// view's flipped coordinates.
    func drawPanel(in context: CGContext) {
        guard let theme, let text else { return }
        let shapes = PanelShapes(
            size: bounds.size,
            metrics: theme.metrics,
            text: textGeometry(text),
            highlightedIndex: text.highlightedIndex,
            canPageUp: text.canPageUp,
            canPageDown: text.canPageDown
        )

        context.saveGState()
        context.clip(to: bounds)
        // The window's alphaValue fades everything together.
        let fades = theme.alpha < 1
        if fades {
            context.setAlpha(theme.alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }

        context.saveGState()
        context.translateBy(x: theme.pagingOffset, y: 0)
        drawShapes(shapes, theme: theme, in: context)
        context.restoreGState()

        for arrow in [shapes.pageDown, shapes.pageUp].compactMap({ $0 }) {
            fill(arrow, with: theme.backgroundColor, in: context)
        }

        textLayout.draw(at: CGPoint(x: theme.pagingOffset + theme.edgeInset.width, y: theme.edgeInset.height), in: context)

        if fades {
            context.endTransparencyLayer()
        }
        context.restoreGState()
    }

    /// The panel itself, clipped to its rounded background like Squirrel's
    /// masked panel layer, in the order of its sublayers.
    private func drawShapes(_ shapes: PanelShapes, theme: PanelTheme, in context: CGContext) {
        context.addPath(shapes.background)
        context.clip(using: .evenOdd)

        fill(shapes.backgroundFill(mutualExclusive: theme.mutualExclusive), with: theme.backgroundColor, in: context)

        if let color = theme.preeditBackgroundColor, let preedit = shapes.preedit {
            context.saveGState()
            let mask = CGMutablePath()
            mask.addPath(shapes.background)
            if theme.mutualExclusive, let highlightedPreedit = shapes.highlightedPreedit {
                mask.addPath(highlightedPreedit)
            }
            context.addPath(mask)
            context.clip(using: .evenOdd)
            fill(preedit, with: color, in: context)
            context.restoreGState()
        }

        if theme.borderLineWidth > 0, let color = theme.borderColor {
            // Stroked twice as wide; the clip leaves the inner half.
            context.addPath(shapes.background)
            context.setLineWidth(theme.borderLineWidth * 2)
            context.setStrokeColor(color.cgColor)
            context.strokePath()
        }

        if let color = theme.highlightedPreeditColor, let highlightedPreedit = shapes.highlightedPreedit {
            fill(highlightedPreedit, with: color, in: context)
        }

        if let color = theme.candidateBackColor, let candidates = shapes.candidates {
            fill(candidates, with: color, in: context)
        }

        if let color = theme.highlightedBackColor, let highlighted = shapes.highlightedCandidate {
            fill(highlighted, with: color, in: context)
            if theme.shadowSize > 0 {
                context.addPath(highlighted)
                context.setLineWidth(0.5)
                context.setStrokeColor(NSColor.black.withAlphaComponent(0.15).cgColor)
                context.strokePath()

                // The shadow falls only outside the highlight.
                context.saveGState()
                let mask = CGMutablePath()
                mask.addPath(shapes.background)
                mask.addPath(highlighted)
                context.addPath(mask)
                context.clip(using: .evenOdd)
                let size = theme.shadowSize
                drawShadow(
                    of: highlighted,
                    offset: CGSize(width: size / 2, height: (theme.vertical ? -1 : 1) * size / 2),
                    radius: size,
                    in: context
                )
                context.restoreGState()
            }
        }
    }

    private func fill(_ path: CGPath, with color: NSColor, in context: CGContext) {
        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath(using: .evenOdd)
    }

    /// Draws only the shadow `path` would cast, matching a Core Animation
    /// shadow: black at 20% opacity, `radius` as `shadowRadius`, and an
    /// offset in this view's flipped coordinates.
    private func drawShadow(of path: CGPath, offset: CGSize, radius: CGFloat, in context: CGContext) {
        // Core Graphics takes shadow offsets and blur in device space; the
        // shape itself is drawn far away so only its shadow lands here.
        let away: CGFloat = 100_000
        let transform = context.ctm
        let deviceOffset = CGSize(width: offset.width - away, height: offset.height).applying(transform)
        let scale = (abs(transform.a * transform.d - transform.b * transform.c)).squareRoot()
        context.setShadow(offset: deviceOffset, blur: 2 * radius * scale, color: NSColor.black.withAlphaComponent(0.2).cgColor)
        context.translateBy(x: away, y: 0)
        context.addPath(path)
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()
    }

    private func textGeometry(_ text: PanelText) -> PanelTextGeometry {
        let length = text.string.length
        let preeditEnd = text.preeditRange.map(NSMaxRange) ?? 0
        func segments(_ range: NSRange?) -> [CGRect] {
            guard let range, range.length > 0 else { return [] }
            return textLayout.segments(of: range)
        }
        return PanelTextGeometry(
            candidates: text.candidateRanges.map { range in
                PanelTextGeometry.Candidate(
                    segments: textLayout.segments(of: range),
                    isEmpty: range.length == 0,
                    isFirst: range.location - preeditEnd <= 1,
                    isLast: NSMaxRange(range) == length
                )
            },
            preeditSegments: segments(text.preeditRange),
            highlightedPreeditSegments: segments(text.highlightedPreeditRange),
            separatorWidth: text.separatorWidth
        )
    }
}
