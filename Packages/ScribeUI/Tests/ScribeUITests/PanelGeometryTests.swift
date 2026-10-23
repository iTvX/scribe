import CoreGraphics
@testable import ScribeUI
import Testing

@Suite struct PanelGeometryTests {
    private let rect = CGRect(x: 10, y: 20, width: 100, height: 40)

    @Test func rectangleVerticesGoClockwiseInFlippedCoordinates() {
        #expect(PanelGeometry.vertices(of: rect) == [
            CGPoint(x: 10, y: 20), CGPoint(x: 10, y: 60), CGPoint(x: 110, y: 60), CGPoint(x: 110, y: 20),
        ])
    }

    @Test func smoothPathNeedsThreeVertices() {
        #expect(PanelGeometry.smoothPath([.zero, CGPoint(x: 1, y: 1)], straightCorners: [], alpha: 1, beta: 1) == nil)
    }

    @Test func zeroRadiusKeepsSharpCorners() throws {
        let path = try #require(PanelGeometry.smoothPath(PanelGeometry.vertices(of: rect), straightCorners: [], alpha: 0, beta: 0))
        #expect(path.boundingBoxOfPath.insetBy(dx: -0.001, dy: -0.001).contains(rect))
        #expect(path.contains(CGPoint(x: 10.01, y: 20.01)))
        #expect(path.contains(CGPoint(x: 109.99, y: 59.99)))
    }

    @Test func radiusRoundsEveryCorner() throws {
        let path = try #require(PanelGeometry.smoothPath(PanelGeometry.vertices(of: rect), straightCorners: [], alpha: 0.3 * 10, beta: 1.4 * 10))
        #expect(path.boundingBoxOfPath == rect)
        for corner in [CGPoint(x: 11, y: 21), CGPoint(x: 11, y: 59), CGPoint(x: 109, y: 59), CGPoint(x: 109, y: 21)] {
            #expect(!path.contains(corner))
        }
        #expect(path.contains(CGPoint(x: 60, y: 20.5)))
        #expect(path.contains(CGPoint(x: 10.5, y: 40)))
    }

    @Test func straightCornersStaySquare() throws {
        let path = try #require(PanelGeometry.smoothPath(PanelGeometry.vertices(of: rect), straightCorners: [2, 3], alpha: 3, beta: 14))
        #expect(!path.contains(CGPoint(x: 11, y: 21)))
        #expect(path.contains(CGPoint(x: 109.5, y: 59.5)))
        #expect(path.contains(CGPoint(x: 109.5, y: 20.5)))
    }

    @Test func closeVerticesGetSmallerCurves() throws {
        // A 2-point-tall rectangle with a 10-point radius: the curves shrink
        // to fit instead of overshooting.
        let thin = CGRect(x: 0, y: 0, width: 50, height: 2)
        let path = try #require(PanelGeometry.smoothPath(PanelGeometry.vertices(of: thin), straightCorners: [], alpha: 3, beta: 14))
        #expect(path.boundingBoxOfPath.minY >= -0.001)
        #expect(path.boundingBoxOfPath.maxY <= 2.001)
    }

    @Test func unionOfSegments() {
        let union = PanelGeometry.union(of: [CGRect(x: 0, y: 0, width: 10, height: 5), CGRect(x: 4, y: 5, width: 20, height: 5)])
        #expect(union == CGRect(x: 0, y: 0, width: 24, height: 10))
    }

    @Test func oneLineIsTheBody() {
        let lines = PanelGeometry.multilineRects([CGRect(x: 5, y: 0, width: 30, height: 20)], edgeInset: CGSize(width: 7, height: 4), lineSpacing: 6, extraSurrounding: 0, bounds: .zero)
        #expect(lines.leading == .zero)
        #expect(lines.trailing == .zero)
        #expect(lines.body == CGRect(x: 12, y: 1, width: 30, height: 26))
    }

    @Test func twoLinesReachThePanelSides() {
        let bounds = CGRect(x: 2, y: 0, width: 200, height: 100)
        let lines = PanelGeometry.multilineRects(
            [CGRect(x: 120, y: 0, width: 60, height: 20), CGRect(x: 0, y: 30, width: 50, height: 20)],
            edgeInset: .zero,
            lineSpacing: 0,
            extraSurrounding: 0,
            bounds: bounds
        )
        #expect(lines.leading == CGRect(x: 120, y: 0, width: 82, height: 25))
        #expect(lines.trailing == CGRect(x: 2, y: 25, width: 48, height: 25))
        #expect(lines.body == .zero)
    }

    @Test func middleLinesSpanThePanel() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let lines = PanelGeometry.multilineRects(
            [CGRect(x: 120, y: 0, width: 60, height: 20), CGRect(x: 0, y: 20, width: 190, height: 20), CGRect(x: 0, y: 40, width: 30, height: 20)],
            edgeInset: .zero,
            lineSpacing: 0,
            extraSurrounding: 0,
            bounds: bounds
        )
        #expect(lines.body == CGRect(x: 0, y: 20, width: 200, height: 20))
        #expect(lines.leading.maxX == 200)
        #expect(lines.trailing.minX == 0)
    }

    @Test func separatorsWidenLinearHighlights() {
        let lines = PanelGeometry.multilineRects([CGRect(x: 40, y: 0, width: 30, height: 20)], edgeInset: .zero, lineSpacing: 0, extraSurrounding: 8, bounds: .zero)
        #expect(lines.body == CGRect(x: 36, y: 0, width: 38, height: 20))
        #expect(PanelGeometry.widened(.zero, by: 8) == .zero)
    }

    @Test func multilineOutlineIsOnePolygon() {
        let leading = CGRect(x: 100, y: 0, width: 100, height: 20)
        let body = CGRect(x: 0, y: 20, width: 200, height: 20)
        let trailing = CGRect(x: 0, y: 40, width: 50, height: 20)
        #expect(PanelGeometry.multilineVertices(leading: leading, body: body, trailing: trailing) == [
            CGPoint(x: 0, y: 60), CGPoint(x: 50, y: 60), CGPoint(x: 50, y: 40), CGPoint(x: 200, y: 40),
            CGPoint(x: 200, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 20), CGPoint(x: 0, y: 20),
        ])
        #expect(PanelGeometry.multilineVertices(leading: .zero, body: body, trailing: .zero) == PanelGeometry.vertices(of: body))
        #expect(PanelGeometry.multilineVertices(leading: .zero, body: .zero, trailing: .zero).isEmpty)
    }

    @Test func separateLinesMakeTwoPolygons() {
        let leading = CGRect(x: 150, y: 0, width: 50, height: 20)
        let trailing = CGRect(x: 0, y: 20, width: 40, height: 20)
        let polygons = PanelGeometry.linearMultilineVertices(leading: leading, body: .zero, trailing: trailing)
        #expect(polygons.first == PanelGeometry.vertices(of: leading))
        #expect(polygons.second == PanelGeometry.vertices(of: trailing))
        #expect(polygons.firstStraightCorners == [2, 3])
        #expect(polygons.secondStraightCorners == [0, 1])

        let overlapping = PanelGeometry.linearMultilineVertices(leading: leading, body: .zero, trailing: CGRect(x: 0, y: 20, width: 160, height: 20))
        #expect(overlapping.second.isEmpty)
        #expect(overlapping.first.count == 8)
    }

    @Test func pointsOutsideTheInnerBoxMoveToTheOuterBox() {
        let inner = CGRect(x: 10, y: 10, width: 80, height: 80)
        let outer = CGRect(x: 0, y: 0, width: 100, height: 100)
        let clamped = PanelGeometry.clamp([CGPoint(x: 5, y: 50), CGPoint(x: 95, y: 95), CGPoint(x: 50, y: 50)], inner: inner, outer: outer)
        #expect(clamped == [CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 100), CGPoint(x: 50, y: 50)])
    }

    @Test func enlargingMovesEveryEdgeOutwards() {
        let enlarged = PanelGeometry.enlarge(PanelGeometry.vertices(of: rect), by: 2)
        #expect(enlarged == PanelGeometry.vertices(of: rect.insetBy(dx: -2, dy: -2)))
        #expect(PanelGeometry.enlarge(PanelGeometry.vertices(of: rect), by: 0) == PanelGeometry.vertices(of: rect))
        #expect(PanelGeometry.outwardNormal(CGPoint(x: 3, y: 4)) == .zero)
    }

    @Test func cornersOnTheContainingEdgeAreRounded() {
        let vertices = PanelGeometry.vertices(of: CGRect(x: 0, y: 0, width: 10, height: 10))
        let containing = CGRect(x: 0, y: 0, width: 10, height: 20)
        #expect(PanelGeometry.removeCorners([0, 1, 2], of: vertices, on: containing) == [1, 2])
        #expect(PanelGeometry.removeCorners([], of: vertices, on: containing).isEmpty)
    }

    @Test func carveInsetShrinksBySumOfRadiusAndBorder() {
        #expect(PanelGeometry.carveInset(rect, hilitedCornerRadius: 3, borderWidth: 2) == CGRect(x: 15, y: 25, width: 90, height: 30))
    }

    @Test func trianglePointsDown() {
        let triangle = PanelGeometry.triangle(center: .zero, radius: 2)
        #expect(triangle[0] == CGPoint(x: 0, y: 2))
        #expect(triangle[1].y == -1)
        #expect(abs(triangle[1].x - 3.0.squareRoot()) < 1e-12)
    }
}

@Suite struct PanelShapesTests {
    private let metrics = PanelMetrics(
        edgeInset: CGSize(width: 10, height: 6),
        lineSpacing: 4,
        spacing: 8,
        cornerRadius: 5,
        hilitedCornerRadius: 0,
        borderWidth: 5,
        borderLineWidth: 1,
        surroundingExtraExpansion: 0,
        pagingOffset: 0,
        linear: false,
        mutualExclusive: false,
        showPaging: false,
        drawsPreeditBackground: true,
        drawsCandidateBackground: true,
        drawsHighlightedCandidate: true,
        drawsHighlightedPreedit: true
    )

    /// Three stacked rows of 20 points with 4 points between them.
    private func stacked() -> PanelTextGeometry {
        PanelTextGeometry(candidates: [
            .init(segments: [CGRect(x: 0, y: 2, width: 80, height: 20)], isFirst: true),
            .init(segments: [CGRect(x: 0, y: 26, width: 60, height: 20)]),
            .init(segments: [CGRect(x: 0, y: 50, width: 70, height: 20)], isLast: true),
        ])
    }

    private let size = CGSize(width: 100, height: 84)

    @Test func backgroundFillsTheViewLessThePagingStrip() {
        var metrics = metrics
        metrics.pagingOffset = 12
        let shapes = PanelShapes(size: size, metrics: metrics, text: stacked(), highlightedIndex: 0, canPageUp: false, canPageDown: false)
        #expect(shapes.backgroundRect == CGRect(x: 0, y: 0, width: 88, height: 84))
        #expect(shapes.background.boundingBoxOfPath == shapes.backgroundRect)
        #expect(shapes.preeditRect == .zero)
        #expect(shapes.preedit == nil)
    }

    @Test func stackedHighlightSpansThePanelWidth() throws {
        let shapes = PanelShapes(size: size, metrics: metrics, text: stacked(), highlightedIndex: 1, canPageUp: false, canPageDown: false)
        let highlighted = try #require(shapes.highlightedCandidate)
        // The row's line box, moved by the inset and grown by the line
        // spacing, clamped to the panel inside the border.
        #expect(highlighted.boundingBoxOfPath == CGRect(x: 0.5, y: 30, width: 99, height: 24))
        let candidates = try #require(shapes.candidates)
        #expect(candidates.boundingBoxOfPath == CGRect(x: 0.5, y: 0.5, width: 99, height: 83))
    }

    @Test func firstAndLastRowsReachThePanelEdge() throws {
        let first = try #require(PanelShapes(size: size, metrics: metrics, text: stacked(), highlightedIndex: 0, canPageUp: false, canPageDown: false).highlightedCandidate)
        #expect(first.boundingBoxOfPath.minY == 0.5)
        let last = try #require(PanelShapes(size: size, metrics: metrics, text: stacked(), highlightedIndex: 2, canPageUp: false, canPageDown: false).highlightedCandidate)
        #expect(last.boundingBoxOfPath.maxY == 83.5)
    }

    @Test func missingColoursDrawNothing() {
        var metrics = metrics
        metrics.drawsCandidateBackground = false
        metrics.drawsHighlightedCandidate = false
        let shapes = PanelShapes(size: size, metrics: metrics, text: stacked(), highlightedIndex: 0, canPageUp: false, canPageDown: false)
        #expect(shapes.candidates == nil)
        #expect(shapes.highlightedCandidate == nil)
    }

    @Test func preeditBandTopsThePanel() throws {
        var text = stacked()
        text.preeditSegments = [CGRect(x: 0, y: 0, width: 60, height: 18)]
        text.highlightedPreeditSegments = [CGRect(x: 30, y: 0, width: 30, height: 18)]
        let shapes = PanelShapes(size: size, metrics: metrics, text: text, highlightedIndex: 0, canPageUp: false, canPageDown: false)
        // Text height, top inset and half the spacing.
        #expect(shapes.preeditRect == CGRect(x: 0, y: 0, width: 100, height: 28))
        #expect(shapes.preedit?.boundingBoxOfPath == shapes.preeditRect)
        // The selected text's box, stretched to the band's top and bottom
        // inside the border.
        let highlighted = try #require(shapes.highlightedPreedit)
        #expect(highlighted.boundingBoxOfPath == CGRect(x: 40, y: 0.5, width: 30, height: 27))
    }

    @Test func mutualExclusionCutsCandidatesOutOfTheBackground() throws {
        let shapes = PanelShapes(size: size, metrics: metrics, text: stacked(), highlightedIndex: 0, canPageUp: false, canPageDown: false)
        func filled(_ path: CGPath, _ point: CGPoint) -> Bool {
            path.contains(point, using: .evenOdd)
        }
        let inRow = CGPoint(x: 50, y: 12)
        #expect(filled(shapes.backgroundFill(mutualExclusive: false), inRow))
        #expect(!filled(shapes.backgroundFill(mutualExclusive: true), inRow))
    }

    @Test func linearHighlightCoversItsLine() throws {
        var metrics = metrics
        metrics.linear = true
        let text = PanelTextGeometry(
            candidates: [
                .init(segments: [CGRect(x: 0, y: 0, width: 30, height: 20)], isFirst: true),
                .init(segments: [CGRect(x: 40, y: 0, width: 30, height: 20)], isLast: true),
            ],
            separatorWidth: 10
        )
        let shapes = PanelShapes(size: CGSize(width: 100, height: 32), metrics: metrics, text: text, highlightedIndex: 1, canPageUp: false, canPageDown: false)
        let highlighted = try #require(shapes.highlightedCandidate)
        // Half a separator wider on each side, stretched to the panel's top
        // and bottom inside the border.
        #expect(highlighted.boundingBoxOfPath == CGRect(x: 45, y: 0.5, width: 40, height: 31))
    }

    @Test func pagingArrowsSitInTheStrip() throws {
        var metrics = metrics
        metrics.showPaging = true
        metrics.pagingOffset = 18
        let both = PanelShapes(size: size, metrics: metrics, text: stacked(), highlightedIndex: 0, canPageUp: true, canPageDown: true)
        let down = try #require(both.pageDown)
        let up = try #require(both.pageUp)
        #expect(abs(down.boundingBoxOfPath.midX - 9) < 0.01)
        #expect(abs(up.boundingBoxOfPath.midX - 9) < 0.01)
        #expect(up.boundingBoxOfPath.midY < down.boundingBoxOfPath.midY)

        let downOnly = PanelShapes(size: size, metrics: metrics, text: stacked(), highlightedIndex: 0, canPageUp: false, canPageDown: true)
        #expect(downOnly.pageUp == nil)
        #expect(downOnly.pageDown != nil)
        metrics.showPaging = false
        #expect(PanelShapes(size: size, metrics: metrics, text: stacked(), highlightedIndex: 0, canPageUp: true, canPageDown: true).pageDown == nil)
    }
}
