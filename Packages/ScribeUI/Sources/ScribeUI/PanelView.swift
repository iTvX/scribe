import AppKit
import ScribeCore

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

/// What a point in the panel falls on.
struct PanelHit: Equatable {
    var candidate: Int?
    /// A UTF-16 offset into the preedit.
    var preeditIndex: Int?
    var page: PageDirection?
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

    private func shapes(_ text: PanelText, theme: PanelTheme) -> PanelShapes {
        PanelShapes(
            size: bounds.size,
            metrics: theme.metrics,
            text: textGeometry(text),
            highlightedIndex: text.highlightedIndex,
            canPageUp: text.canPageUp,
            canPageDown: text.canPageDown
        )
    }

    /// What is under `point`, in this view's coordinates, found the way
    /// Squirrel's `click(at:)` finds it.
    func hit(at point: CGPoint) -> PanelHit {
        guard let theme, let text else { return PanelHit() }
        let shapes = shapes(text, theme: theme)
        if shapes.pageDown?.contains(point) == true {
            return PanelHit(page: .down)
        }
        if shapes.pageUp?.contains(point) == true {
            return PanelHit(page: .up)
        }
        var panel = CGAffineTransform(translationX: theme.pagingOffset, y: 0)
        guard shapes.background.copy(using: &panel)?.contains(point) == true else { return PanelHit() }
        let inContainer = CGPoint(x: point.x - theme.edgeInset.width - theme.pagingOffset, y: point.y - theme.edgeInset.height)
        guard let index = textLayout.characterIndex(at: inContainer) else { return PanelHit() }
        if let preeditRange = text.preeditRange, NSLocationInRange(index, preeditRange) {
            return PanelHit(preeditIndex: index)
        }
        return PanelHit(candidate: text.candidateRanges.firstIndex { NSLocationInRange(index, $0) })
    }

    /// Where candidate row `index`'s text is, in this view's coordinates.
    func textRect(ofCandidate index: Int) -> CGRect? {
        guard let theme, let text, text.candidateRanges.indices.contains(index) else { return nil }
        let rect = PanelGeometry.union(of: textLayout.segments(of: text.candidateRanges[index]))
        return rect.offsetBy(dx: theme.pagingOffset + theme.edgeInset.width, dy: theme.edgeInset.height)
    }

    /// The panel's outline and paging arrows for masking a sibling view of
    /// the same frame, in unflipped coordinates.
    func outline() -> CGPath? {
        guard let theme, let text else { return nil }
        let shapes = shapes(text, theme: theme)
        let flip = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -bounds.height)
        let path = CGMutablePath()
        path.addPath(shapes.background, transform: CGAffineTransform(translationX: theme.pagingOffset, y: 0).concatenating(flip))
        for arrow in [shapes.pageDown, shapes.pageUp].compactMap({ $0 }) {
            path.addPath(arrow, transform: flip)
        }
        return path
    }

    /// Draws the whole panel into `context`, whose user space must be this
    /// view's flipped coordinates.
    func drawPanel(in context: CGContext) {
        guard let theme, let text else { return }
        let shapes = shapes(text, theme: theme)

        context.saveGState()
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

        // TextKit smooths fonts in the layers it draws Squirrel's text into;
        // matching that keeps Scribe's text as heavy as Squirrel's.
        context.setShouldSmoothFonts(true)
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
    ///
    /// Core Graphics applies shadow offsets in the context's base space,
    /// which differs between a bitmap and AppKit's layer contexts, so the
    /// shadow is made in a bitmap of its own and drawn from there.
    private func drawShadow(of path: CGPath, offset: CGSize, radius: CGFloat, in context: CGContext) {
        let transform = context.ctm
        let scale = abs(transform.a * transform.d - transform.b * transform.c).squareRoot()
        // Core Animation's shadowRadius blurs about as much as twice that
        // value does in Core Graphics.
        let blur = 2 * radius
        let margin = 2 * blur + abs(offset.width) + abs(offset.height)
        let box = path.boundingBoxOfPath.insetBy(dx: -margin, dy: -margin).integral
        let width = Int((box.width * scale).rounded(.up))
        let height = Int((box.height * scale).rounded(.up))
        guard width > 0, height > 0, let shadow = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: PanelRenderer.colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        shadow.translateBy(x: 0, y: CGFloat(height))
        shadow.scaleBy(x: scale, y: -scale)
        shadow.translateBy(x: -box.minX, y: -box.minY)
        // The shape goes beside the bitmap; only its shadow falls inside.
        let away = box.width
        shadow.setShadow(
            offset: CGSize(width: (offset.width - away) * scale, height: -offset.height * scale),
            blur: blur * scale,
            color: NSColor.black.withAlphaComponent(0.2).cgColor
        )
        shadow.translateBy(x: away, y: 0)
        shadow.addPath(path)
        shadow.setFillColor(NSColor.black.cgColor)
        shadow.fillPath()
        guard let image = shadow.makeImage() else { return }
        context.saveGState()
        context.translateBy(x: box.minX, y: box.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: box.size))
        context.restoreGState()
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
