import CoreGraphics

/// Where the text sits, as the shapes need it: the line segments of each
/// part, in text container coordinates.
struct PanelTextGeometry: Equatable, Sendable {
    struct Candidate: Equatable, Sendable {
        var segments: [CGRect]
        var isEmpty = false
        /// The row starts the text, right after the preedit if there is one.
        var isFirst = false
        /// The row ends the text.
        var isLast = false
    }

    var candidates: [Candidate]
    /// Empty when there is no preedit.
    var preeditSegments: [CGRect] = []
    var highlightedPreeditSegments: [CGRect] = []
    var separatorWidth: CGFloat = 0

    var hasPreedit: Bool {
        !preeditSegments.isEmpty
    }
}

/// The panel's background and highlight shapes for one layout.
///
/// Panel shapes are relative to the panel's top left, which sits right of
/// the paging strip; the paging arrows are relative to the view.
struct PanelShapes {
    /// The panel without the paging strip.
    var backgroundRect: CGRect
    /// The preedit's band across the top of the panel; zero without one.
    var preeditRect: CGRect
    var background: CGPath
    var preedit: CGPath?
    var candidates: CGPath?
    var highlightedCandidate: CGPath?
    var highlightedPreedit: CGPath?
    var pageUp: CGPath?
    var pageDown: CGPath?

    /// The shapes for a view of `size`, mirroring Squirrel's
    /// `SquirrelView.draw(_:)`.
    init(
        size: CGSize,
        metrics: PanelMetrics,
        text: PanelTextGeometry,
        highlightedIndex: Int,
        canPageUp: Bool,
        canPageDown: Bool
    ) {
        let inset = metrics.edgeInset
        var containingRect = CGRect(origin: .zero, size: size)
        containingRect.size.width -= metrics.pagingOffset
        backgroundRect = containingRect

        preeditRect = .zero
        if text.hasPreedit {
            preeditRect = PanelGeometry.union(of: text.preeditSegments)
            preeditRect.size.width = backgroundRect.size.width
            preeditRect.size.height += inset.height + metrics.spacing / 2 + metrics.hilitedCornerRadius / 2
            preeditRect.origin = backgroundRect.origin
            if text.candidates.isEmpty {
                preeditRect.size.height += inset.height - metrics.spacing / 2 - metrics.hilitedCornerRadius / 2
            }
            containingRect.size.height -= preeditRect.size.height
            containingRect.origin.y += preeditRect.size.height
            if metrics.drawsPreeditBackground {
                preedit = PanelGeometry.smoothPath(PanelGeometry.vertices(of: preeditRect), straightCorners: [], alpha: 0, beta: 0)
            }
        }

        containingRect = PanelGeometry.carveInset(containingRect, hilitedCornerRadius: metrics.hilitedCornerRadius, borderWidth: metrics.borderWidth)
        let boxes = HighlightBoxes(metrics: metrics, backgroundRect: backgroundRect, preeditRect: preeditRect, hasPreedit: text.hasPreedit)
        var candidatePaths: CGMutablePath?
        for (index, candidate) in text.candidates.enumerated() where !candidate.isEmpty {
            if index == highlightedIndex {
                if metrics.drawsHighlightedCandidate {
                    highlightedCandidate = boxes.path(for: candidate, containingRect: containingRect, extraExpansion: 0, separatorWidth: text.separatorWidth)
                }
            } else if metrics.drawsCandidateBackground {
                let paths = candidatePaths ?? CGMutablePath()
                if let path = boxes.path(
                    for: candidate,
                    containingRect: containingRect,
                    extraExpansion: metrics.surroundingExtraExpansion,
                    separatorWidth: text.separatorWidth
                ) {
                    paths.addPath(path)
                }
                candidatePaths = paths
            }
        }
        candidates = candidatePaths

        if !text.highlightedPreeditSegments.isEmpty && metrics.drawsHighlightedPreedit {
            highlightedPreedit = Self.highlightedPreeditPath(text.highlightedPreeditSegments, metrics: metrics, preeditRect: preeditRect, hasCandidates: !text.candidates.isEmpty)
        }

        background = PanelGeometry.smoothPath(
            PanelGeometry.vertices(of: backgroundRect),
            straightCorners: [],
            alpha: 0.3 * metrics.cornerRadius,
            beta: 1.4 * metrics.cornerRadius
        ) ?? CGPath(rect: backgroundRect, transform: nil)

        if metrics.showPaging && (canPageUp || canPageDown), let first = text.candidates.first {
            let arrows = Self.pagingPaths(firstCandidate: first, metrics: metrics, preeditRect: preeditRect, canPageUp: canPageUp, canPageDown: canPageDown)
            pageUp = arrows.up
            pageDown = arrows.down
        }
    }

    /// The panel shapes that `fill` paints in the background colour: the
    /// background minus the preedit band and, with `mutual_exclusive`, minus
    /// the candidate backgrounds, using the even-odd rule.
    func backgroundFill(mutualExclusive: Bool) -> CGPath {
        let path = CGMutablePath()
        path.addPath(background)
        if let preedit {
            path.addPath(preedit)
        }
        if mutualExclusive {
            if let highlightedCandidate {
                path.addPath(highlightedCandidate)
            }
            if let candidates {
                path.addPath(candidates)
            }
        }
        return path
    }

    private static func highlightedPreeditPath(_ segments: [CGRect], metrics: PanelMetrics, preeditRect: CGRect, hasCandidates: Bool) -> CGPath? {
        let inset = metrics.edgeInset
        var innerBox = preeditRect
        innerBox.size.width -= (inset.width + 1) * 2
        innerBox.origin.x += inset.width + 1
        innerBox.origin.y += inset.height + 1
        if hasCandidates {
            innerBox.size.height -= inset.height + metrics.spacing / 2 + metrics.hilitedCornerRadius / 2 + 2
        } else {
            innerBox.size.height -= (inset.height + 1) * 2
        }
        let outerInset = max(0, metrics.hilitedCornerRadius + metrics.borderLineWidth)
        var outerBox = preeditRect
        outerBox.size.height -= outerInset
        outerBox.size.width -= outerInset
        outerBox.origin.x += outerInset / 2
        outerBox.origin.y += outerInset / 2

        let lines = PanelGeometry.multilineRects(segments, edgeInset: inset, lineSpacing: metrics.lineSpacing, extraSurrounding: 0, bounds: outerBox)
        let polygons = PanelGeometry.linearMultilineVertices(leading: lines.leading, body: lines.body, trailing: lines.trailing)
        let containingRect = PanelGeometry.carveInset(preeditRect, hilitedCornerRadius: metrics.hilitedCornerRadius, borderWidth: metrics.borderWidth)
        let radius = metrics.hilitedCornerRadius
        return Self.path(
            polygons,
            inner: innerBox,
            outer: outerBox,
            containingRect: containingRect,
            enlargedBy: 0,
            radius: radius
        )
    }

    /// Clamps one or two highlight polygons to the panel and rounds them.
    fileprivate static func path(
        _ polygons: (first: [CGPoint], second: [CGPoint], firstStraightCorners: Set<Int>, secondStraightCorners: Set<Int>),
        inner: CGRect,
        outer: CGRect,
        containingRect: CGRect,
        enlargedBy expansion: CGFloat,
        radius: CGFloat
    ) -> CGPath? {
        func rounded(_ vertices: [CGPoint], straightCorners: Set<Int>) -> CGPath? {
            let vertices = PanelGeometry.clamp(PanelGeometry.enlarge(vertices, by: expansion), inner: inner, outer: outer)
            let straightCorners = PanelGeometry.removeCorners(straightCorners, of: vertices, on: containingRect)
            return PanelGeometry.smoothPath(vertices, straightCorners: straightCorners, alpha: 0.3 * radius, beta: 1.4 * radius)
        }
        let path = rounded(polygons.first, straightCorners: polygons.firstStraightCorners)?.mutableCopy()
        if !polygons.second.isEmpty, let second = rounded(polygons.second, straightCorners: polygons.secondStraightCorners) {
            path?.addPath(second)
        }
        return path
    }

    private static func pagingPaths(
        firstCandidate: PanelTextGeometry.Candidate,
        metrics: PanelMetrics,
        preeditRect: CGRect,
        canPageUp: Bool,
        canPageDown: Bool
    ) -> (up: CGPath?, down: CGPath?) {
        let inset = metrics.edgeInset
        var height = PanelGeometry.union(of: firstCandidate.segments).height
        let preeditHeight = max(0, preeditRect.height + metrics.spacing / 2 + metrics.hilitedCornerRadius / 2 - inset.height)
            + inset.height - metrics.lineSpacing / 2
        height += metrics.lineSpacing
        let radius = min(0.5 * metrics.pagingOffset, 2 * height / 9)
        let cornerRadius = min(metrics.cornerRadius, 0.6 * radius)
        guard let triangle = PanelGeometry.smoothPath(
            PanelGeometry.triangle(center: .zero, radius: radius),
            straightCorners: [],
            alpha: 0.3 * cornerRadius,
            beta: 1.4 * cornerRadius
        ) else { return (nil, nil) }
        var up: CGPath?
        var down: CGPath?
        if canPageDown {
            var transform = CGAffineTransform(translationX: 0.5 * metrics.pagingOffset, y: 2 * height / 3 + preeditHeight)
            down = triangle.copy(using: &transform)
        }
        if canPageUp {
            var transform = CGAffineTransform(rotationAngle: .pi).translatedBy(x: -0.5 * metrics.pagingOffset, y: -height / 3 - preeditHeight)
            up = triangle.copy(using: &transform)
        }
        return (up, down)
    }
}

/// The boxes a candidate highlight is clamped between: points inside the
/// inner box stay, points outside it move to the outer box.
private struct HighlightBoxes {
    var metrics: PanelMetrics
    var backgroundRect: CGRect
    var preeditRect: CGRect
    var hasPreedit: Bool

    /// The highlight or background shape of one candidate row, grown by
    /// `extraExpansion` (`surrounding_extra_expansion` for unhighlighted
    /// rows).
    func path(for candidate: PanelTextGeometry.Candidate, containingRect: CGRect, extraExpansion: CGFloat, separatorWidth: CGFloat) -> CGPath? {
        let inset = metrics.edgeInset
        let hilitedRadius = metrics.hilitedCornerRadius
        var containing = containingRect
        containing.size.width += extraExpansion * 2
        containing.size.height += extraExpansion * 2
        containing.origin.x -= extraExpansion
        containing.origin.y -= extraExpansion

        let halfLineSpacing = metrics.lineSpacing / 2
        var innerBox = backgroundRect
        innerBox.size.width -= (inset.width + 1) * 2 - 2 * extraExpansion
        innerBox.origin.x += inset.width + 1 - extraExpansion
        innerBox.size.height += 2 * extraExpansion
        innerBox.origin.y -= extraExpansion
        if hasPreedit {
            innerBox.origin.y += preeditRect.size.height + metrics.spacing / 2 + hilitedRadius / 2 + 1
            innerBox.size.height -= inset.height + preeditRect.size.height + metrics.spacing / 2 + hilitedRadius / 2 + 2
        } else {
            innerBox.origin.y += inset.height + 1
            innerBox.size.height -= (inset.height + 1) * 2
        }
        innerBox.size.height -= metrics.lineSpacing
        innerBox.origin.y += halfLineSpacing

        let outerInset = max(0, hilitedRadius + metrics.borderLineWidth)
        var outerBox = backgroundRect
        outerBox.size.height -= preeditRect.size.height + outerInset - 2 * extraExpansion
        outerBox.size.width -= outerInset - 2 * extraExpansion
        outerBox.origin.x += outerInset / 2 - extraExpansion
        outerBox.origin.y += preeditRect.size.height + outerInset / 2 - extraExpansion

        // Grows the corner radius with the expansion; this divides by zero
        // when hilited_corner_radius is 0, exactly as Squirrel does.
        let radius = max(0, hilitedRadius + 2 * extraExpansion / hilitedRadius * max(0, metrics.cornerRadius - hilitedRadius))

        if metrics.linear {
            let lines = PanelGeometry.multilineRects(
                candidate.segments,
                edgeInset: inset,
                lineSpacing: metrics.lineSpacing,
                extraSurrounding: separatorWidth,
                bounds: outerBox
            )
            let polygons = PanelGeometry.linearMultilineVertices(leading: lines.leading, body: lines.body, trailing: lines.trailing)
            return PanelShapes.path(polygons, inner: innerBox, outer: outerBox, containingRect: containing, enlargedBy: extraExpansion, radius: radius)
        }

        var rect = PanelGeometry.union(of: candidate.segments)
        guard !PanelGeometry.isNearlyEmpty(rect) else { return nil }
        rect.size.width = backgroundRect.size.width
        rect.size.height += metrics.lineSpacing
        rect.origin = CGPoint(x: backgroundRect.origin.x, y: rect.origin.y + inset.height - halfLineSpacing)
        if candidate.isLast {
            rect.size.height += inset.height - halfLineSpacing
        }
        if candidate.isFirst {
            if hasPreedit {
                rect.size.height += hilitedRadius / 2
                rect.origin.y -= hilitedRadius / 2
            } else {
                rect.size.height += inset.height - halfLineSpacing
                rect.origin.y -= inset.height - halfLineSpacing
            }
        }
        let vertices = PanelGeometry.clamp(PanelGeometry.enlarge(PanelGeometry.vertices(of: rect), by: extraExpansion), inner: innerBox, outer: outerBox)
        return PanelGeometry.smoothPath(vertices, straightCorners: [], alpha: radius * 0.3, beta: radius * 1.4)
    }
}
