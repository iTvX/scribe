import AppKit

/// Draws the panel into a bitmap without a window, for snapshot tests and
/// tools.
///
/// Images are 8-bit sRGB with premultiplied alpha, so theme colours keep
/// their hex values; Display P3 colours outside sRGB are clipped. What is
/// transparent in the panel stays transparent: the translucent backdrop and
/// the window shadow are not drawn.
@MainActor
enum PanelRenderer {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The reference screen: a 1440×900 display.
    nonisolated static let referenceScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    /// The panel for `content`, or nil when it has nothing to show. `scale`
    /// is pixels per point.
    static func render(
        _ content: PanelContent,
        theme: PanelTheme,
        appearance: NSAppearance,
        screen: CGRect = referenceScreen,
        scale: CGFloat = 2
    ) -> CGImage? {
        guard let text = PanelText(content, theme: theme) else { return nil }
        let view = PanelView()
        view.appearance = appearance
        let sizing = view.update(text, theme: theme, screen: screen)
        let viewSize = PanelView.viewSize(for: sizing.size, vertical: theme.vertical)
        view.frame = CGRect(origin: .zero, size: viewSize)

        // An oversized panel is drawn at its natural size and scaled down
        // to fit the screen, like Squirrel's window bounds.
        let fit = sizing.isOversized ? PanelPlacement.oversizedScale(sizing.size, screen: screen) : 1
        let pixelScale = scale * fit
        let width = Int((viewSize.width * pixelScale).rounded(.up))
        let height = Int((viewSize.height * pixelScale).rounded(.up))
        guard width > 0, height > 0, let context = bitmap(width: width, height: height) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: pixelScale, y: -pixelScale)
        // PanelView smooths its text, as Squirrel's TextKit layers do.
        context.setAllowsFontSmoothing(true)
        context.clip(to: windowClip(viewSize: viewSize, screenSize: sizing.size, vertical: theme.vertical, scale: scale))

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        appearance.performAsCurrentDrawingAppearance {
            view.drawPanel(in: context)
        }
        NSGraphicsContext.current = previous

        return theme.vertical ? rotatedClockwise(context) : context.makeImage()
    }

    /// The part of the view the window shows, in view coordinates. AppKit
    /// rounds the window's content view to the nearest pixel at `scale`;
    /// the panel stays at its natural size, so a panel that rounds down
    /// loses a sliver of its right edge and of its top edge (bottom edge
    /// when turned for vertical text) on screen.
    static func windowClip(viewSize: CGSize, screenSize: CGSize, vertical: Bool, scale: CGFloat) -> CGRect {
        // A side that rounds up is not cut; it keeps a whole extra point so
        // the clip leaves its anti-aliased edge alone.
        func shownLength(_ length: CGFloat) -> CGFloat {
            let rounded = (length * scale).rounded() / scale
            return rounded < length ? rounded : length.rounded(.up) + 1
        }
        let shown = CGSize(width: shownLength(screenSize.width), height: shownLength(screenSize.height))
        if vertical {
            // The view's x runs down the screen and its y leftwards; the
            // turned content keeps its top edge and loses its bottom one.
            return CGRect(x: 0, y: viewSize.height - shown.width, width: shown.height, height: shown.width)
        }
        return CGRect(x: 0, y: max(0, screenSize.height - shown.height), width: shown.width, height: shown.height)
    }

    private static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// The bitmap in `source` turned a quarter turn clockwise, pixel for
    /// pixel, as the window turns a vertical panel.
    static func rotatedClockwise(_ source: CGContext) -> CGImage? {
        let (width, height) = (source.width, source.height)
        guard let target = bitmap(width: height, height: width),
              let sourceData = source.data, let targetData = target.data else { return nil }
        let pixels = sourceData.assumingMemoryBound(to: UInt32.self)
        let rotated = targetData.assumingMemoryBound(to: UInt32.self)
        // Rows are stored top first: the source's top row becomes the
        // target's right column.
        for row in 0..<height {
            for column in 0..<width {
                rotated[column * height + (height - 1 - row)] = pixels[row * width + column]
            }
        }
        return target.makeImage()
    }
}
