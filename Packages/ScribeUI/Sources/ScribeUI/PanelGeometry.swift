import CoreGraphics

/// The shape arithmetic behind the panel's backgrounds and highlights.
///
/// These reproduce Squirrel's results, including its edge cases, so the same
/// theme draws the same shapes. Rectangles are used as stored, without
/// standardizing, wherever Squirrel does the same.
enum PanelGeometry {
    /// A closed path through `vertices` whose corners are rounded with cubic
    /// curves, except the corners listed in `straightCorners`. `beta` is how
    /// far from a corner the curve starts and `alpha` where its control
    /// points sit.
    static func smoothPath(_ vertices: [CGPoint], straightCorners: Set<Int>, alpha: CGFloat, beta rawBeta: CGFloat) -> CGPath? {
        guard vertices.count >= 3 else { return nil }
        let count = vertices.count
        let beta = max(0.00001, rawBeta)
        let path = CGMutablePath()
        var target = vertices[count - 1]
        if straightCorners.isEmpty || !straightCorners.contains(count - 1) {
            target += unit(vertices[0] - vertices[count - 1], beta: beta) * beta
        }
        path.move(to: target)
        for index in 0..<count {
            let previous = vertices[(count + index - 1) % count]
            let point = vertices[index]
            let next = vertices[(index + 1) % count]
            if straightCorners.contains(index) {
                path.addLine(to: point)
                continue
            }
            let incoming = unit(point - previous, beta: beta)
            let outgoing = unit(next - point, beta: beta)
            path.addLine(to: point - incoming * beta)
            path.addCurve(to: point + outgoing * beta, control1: point - incoming * alpha, control2: point + outgoing * alpha)
        }
        path.closeSubpath()
        return path
    }

    /// The direction of `vector`, shortened when the vector itself is short
    /// so that corners between close points get smaller radii.
    private static func unit(_ vector: CGPoint, beta: CGFloat) -> CGPoint {
        let scaled = vector / beta
        let length = (scaled.x * scaled.x + scaled.y * scaled.y).squareRoot()
        return length >= 2 ? scaled / length : scaled / 2
    }

    /// The corners of `rect`, starting at its origin and going towards
    /// larger y first: clockwise on screen in flipped coordinates.
    static func vertices(of rect: CGRect) -> [CGPoint] {
        [
            rect.origin,
            CGPoint(x: rect.origin.x, y: rect.origin.y + rect.size.height),
            CGPoint(x: rect.origin.x + rect.size.width, y: rect.origin.y + rect.size.height),
            CGPoint(x: rect.origin.x + rect.size.width, y: rect.origin.y),
        ]
    }

    static func isNearlyEmpty(_ rect: CGRect) -> Bool {
        rect.size.height * rect.size.width < 1
    }

    /// The smallest rectangle around `rects`, as Squirrel measures a text
    /// range from its segments.
    static func union(of rects: [CGRect]) -> CGRect {
        var (x0, x1, y0, y1) = (CGFloat.infinity, -CGFloat.infinity, CGFloat.infinity, -CGFloat.infinity)
        for rect in rects {
            x0 = min(rect.minX, x0)
            x1 = max(rect.maxX, x1)
            y0 = min(rect.minY, y0)
            y1 = max(rect.maxY, y1)
        }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Splits the line segments of a text range into its first line, the
    /// full lines in between and its last line. Segments are in text
    /// container coordinates and come out in panel coordinates, each line
    /// taller by the line spacing. When the range spans several lines, the
    /// first line reaches the right of `bounds` and the last the left.
    static func multilineRects(
        _ segments: [CGRect],
        edgeInset: CGSize,
        lineSpacing: CGFloat,
        extraSurrounding: CGFloat,
        bounds: CGRect
    ) -> (leading: CGRect, body: CGRect, trailing: CGRect) {
        let lines = segments.map { segment in
            var line = segment
            line.origin.x += edgeInset.width
            line.origin.y += edgeInset.height
            line.size.height += lineSpacing
            line.origin.y -= lineSpacing / 2
            return line
        }

        var leading = CGRect.zero
        var body = CGRect.zero
        var trailing = CGRect.zero
        if lines.count == 1 {
            body = lines[0]
        } else if lines.count == 2 {
            leading = lines[0]
            trailing = lines[1]
        } else if lines.count > 2 {
            leading = lines[0]
            trailing = lines[lines.count - 1]
            var middle = union(of: Array(lines[1..<(lines.count - 1)]))
            let top = min(leading.maxY, middle.minY)
            let bottom = max(trailing.minY, middle.maxY)
            middle = CGRect(x: middle.minX, y: top, width: middle.maxX - middle.minX, height: bottom - top)
            body = middle
        }

        if extraSurrounding > 0 {
            if isNearlyEmpty(leading) && isNearlyEmpty(trailing) {
                body = widened(body, by: extraSurrounding)
            } else {
                if !isNearlyEmpty(leading) {
                    leading = widened(leading, by: extraSurrounding)
                }
                if !isNearlyEmpty(trailing) {
                    trailing = widened(trailing, by: extraSurrounding)
                }
            }
        }

        if !isNearlyEmpty(leading) && !isNearlyEmpty(trailing) {
            leading.size.width = bounds.maxX - leading.origin.x
            trailing.size.width = trailing.maxX - bounds.minX
            trailing.origin.x = bounds.minX
            if !isNearlyEmpty(body) {
                body.size.width = bounds.size.width
                body.origin.x = bounds.origin.x
            } else {
                let gap = trailing.minY - leading.maxY
                leading.size.height += gap / 2
                trailing.size.height += gap / 2
                trailing.origin.y -= gap / 2
            }
        }
        return (leading, body, trailing)
    }

    /// `rect` wider by `amount`, split evenly between both sides; empty
    /// rectangles stay as they are.
    static func widened(_ rect: CGRect, by amount: CGFloat) -> CGRect {
        guard !isNearlyEmpty(rect) else { return rect }
        var rect = rect
        rect.size.width += amount
        rect.origin.x -= amount / 2
        return rect
    }

    /// The outline of a highlight made of a first line, full lines and a
    /// last line, as one polygon.
    static func multilineVertices(leading: CGRect, body: CGRect, trailing: CGRect) -> [CGPoint] {
        let leadingEmpty = isNearlyEmpty(leading)
        let bodyEmpty = isNearlyEmpty(body)
        let trailingEmpty = isNearlyEmpty(trailing)
        if bodyEmpty && !leadingEmpty && trailingEmpty {
            return vertices(of: leading)
        } else if bodyEmpty && leadingEmpty && !trailingEmpty {
            return vertices(of: trailing)
        } else if leadingEmpty && trailingEmpty && !bodyEmpty {
            return vertices(of: body)
        } else if trailingEmpty && !bodyEmpty {
            let leading = vertices(of: leading)
            let body = vertices(of: body)
            return [body[0], body[1], body[2], leading[3], leading[0], leading[1]]
        } else if leadingEmpty && !bodyEmpty {
            let trailing = vertices(of: trailing)
            let body = vertices(of: body)
            return [trailing[1], trailing[2], trailing[3], body[2], body[3], body[0]]
        } else if !leadingEmpty && !trailingEmpty && bodyEmpty && leading.maxX > trailing.minX {
            let leading = vertices(of: leading)
            let trailing = vertices(of: trailing)
            return [trailing[0], trailing[1], trailing[2], trailing[3], leading[2], leading[3], leading[0], leading[1]]
        } else if !leadingEmpty && !trailingEmpty && !bodyEmpty {
            let leading = vertices(of: leading)
            let body = vertices(of: body)
            let trailing = vertices(of: trailing)
            return [trailing[1], trailing[2], trailing[3], body[2], leading[3], leading[0], leading[1], body[0]]
        } else {
            return []
        }
    }

    /// One polygon for a highlight, or two when its first and last lines
    /// do not overlap horizontally. The two-polygon case keeps the corners
    /// at the panel edge square (`straightCorners`).
    static func linearMultilineVertices(
        leading: CGRect,
        body: CGRect,
        trailing: CGRect
    ) -> (first: [CGPoint], second: [CGPoint], firstStraightCorners: Set<Int>, secondStraightCorners: Set<Int>) {
        if isNearlyEmpty(body) && !isNearlyEmpty(leading) && !isNearlyEmpty(trailing) && trailing.maxX < leading.minX {
            return (vertices(of: leading), vertices(of: trailing), [2, 3], [0, 1])
        }
        return (multilineVertices(leading: leading, body: body, trailing: trailing), [], [], [])
    }

    /// Moves points that fall outside `inner` onto the edges of `outer`, so
    /// highlights touching the text edge reach the panel edge.
    static func clamp(_ vertices: [CGPoint], inner: CGRect, outer: CGRect) -> [CGPoint] {
        vertices.map { vertex in
            var point = vertex
            if point.x < inner.origin.x {
                point.x = outer.origin.x
            } else if point.x > inner.origin.x + inner.size.width {
                point.x = outer.origin.x + outer.size.width
            }
            if point.y < inner.origin.y {
                point.y = outer.origin.y
            } else if point.y > inner.origin.y + inner.size.height {
                point.y = outer.origin.y + outer.size.height
            }
            return point
        }
    }

    /// The outward normal of an axis-aligned edge going along `diff`, for a
    /// polygon listed clockwise in flipped coordinates; zero otherwise.
    static func outwardNormal(_ diff: CGPoint) -> CGPoint {
        if diff.y == 0 && diff.x > 0 {
            CGPoint(x: 0, y: 1)
        } else if diff.y == 0 && diff.x < 0 {
            CGPoint(x: 0, y: -1)
        } else if diff.x == 0 && diff.y > 0 {
            CGPoint(x: -1, y: 0)
        } else if diff.x == 0 && diff.y < 0 {
            CGPoint(x: 1, y: 0)
        } else {
            .zero
        }
    }

    /// Pushes every edge of an axis-aligned polygon outwards by `amount`.
    static func enlarge(_ vertices: [CGPoint], by amount: CGFloat) -> [CGPoint] {
        guard amount != 0 else { return vertices }
        let count = vertices.count
        return vertices.indices.map { index in
            let previous = vertices[(count + index - 1) % count]
            let point = vertices[index]
            let next = vertices[(index + 1) % count]
            var moved = point
            var normal = outwardNormal(point - previous)
            moved.x += amount * normal.x
            moved.y += amount * normal.y
            normal = outwardNormal(next - point)
            moved.x += amount * normal.x
            moved.y += amount * normal.y
            return moved
        }
    }

    /// Drops square corners that lie on the top or bottom edge of
    /// `containing`, so they get rounded like the panel's own corners.
    static func removeCorners(_ straightCorners: Set<Int>, of vertices: [CGPoint], on containing: CGRect) -> Set<Int> {
        guard !vertices.isEmpty && !straightCorners.isEmpty else { return straightCorners }
        return straightCorners.filter { index in
            let corner = vertices[index]
            return min(containing.maxY - corner.y, corner.y - containing.minY) >= 1e-2
        }
    }

    /// `rect` shrunk on every side by the highlight radius and border width.
    static func carveInset(_ rect: CGRect, hilitedCornerRadius: CGFloat, borderWidth: CGFloat) -> CGRect {
        let inset = hilitedCornerRadius + borderWidth
        var rect = rect
        rect.size.height -= inset * 2
        rect.size.width -= inset * 2
        rect.origin.x += inset
        rect.origin.y += inset
        return rect
    }

    /// An equilateral triangle around `center` with its apex towards larger
    /// y: pointing down in flipped coordinates.
    static func triangle(center: CGPoint, radius: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: center.x, y: center.y + radius),
            CGPoint(x: center.x + 0.5 * 3.0.squareRoot() * radius, y: center.y - 0.5 * radius),
            CGPoint(x: center.x - 0.5 * 3.0.squareRoot() * radius, y: center.y - 0.5 * radius),
        ]
    }
}

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func += (lhs: inout CGPoint, rhs: CGPoint) {
        lhs = lhs + rhs
    }

    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    static func / (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x / rhs, y: lhs.y / rhs)
    }
}
