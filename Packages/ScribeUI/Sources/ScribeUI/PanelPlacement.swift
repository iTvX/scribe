import CoreGraphics

/// How big the panel is and where it goes, following Squirrel's
/// `SquirrelPanel.show()`. Screen coordinates are AppKit's: y grows upwards.
enum PanelPlacement {
    /// Space between the caret and the panel.
    static let caretGap: CGFloat = 5

    /// The longest line the text may have on `screen`: a third of the screen
    /// width (a quarter of its height in vertical mode), more for larger
    /// fonts.
    static func maxTextWidth(fontSize: CGFloat, vertical: Bool, edgeInset: CGSize, screen: CGRect) -> CGFloat {
        let ratio = min(1, 1 / (vertical ? 4 : 3) + fontSize / 12 / 12)
        if vertical {
            return screen.height * ratio - edgeInset.height * 2
        } else {
            return screen.width * ratio - edgeInset.width * 2
        }
    }

    /// The panel size around `contentRect` in screen orientation: in
    /// vertical mode lines run down the screen.
    static func naturalSize(contentRect: CGRect, edgeInset: CGSize, pagingOffset: CGFloat, vertical: Bool) -> CGSize {
        if vertical {
            CGSize(
                width: contentRect.height + edgeInset.height * 2,
                height: contentRect.width + edgeInset.width * 2 + pagingOffset
            )
        } else {
            CGSize(
                width: contentRect.width + edgeInset.width * 2 + pagingOffset,
                height: contentRect.height + edgeInset.height * 2
            )
        }
    }

    /// Whether a panel of `size` needs scaling down to fit `screen`.
    static func isOversized(_ size: CGSize, screen: CGRect) -> Bool {
        size.width > screen.width * 0.95 || size.height > screen.height * 0.95
    }

    /// For an oversized panel, the line length that gives the text the
    /// screen's proportions, so it scales down as little as possible.
    static func oversizedTextWidth(contentRect: CGRect, vertical: Bool, screen: CGRect) -> CGFloat {
        let area = contentRect.width * contentRect.height
        let screenRatio = (screen.width * 0.95) / (screen.height * 0.95)
        return vertical ? (area / screenRatio).squareRoot() : (area * screenRatio).squareRoot()
    }

    /// The factor that fits an oversized panel into 95% of `screen`.
    static func oversizedScale(_ size: CGSize, screen: CGRect) -> CGFloat {
        min(screen.width * 0.95 / size.width, screen.height * 0.95 / size.height)
    }

    struct Input {
        /// The caret, in screen coordinates.
        var caret: CGRect
        var screen: CGRect
        /// From `naturalSize`.
        var size: CGSize
        var contentRect: CGRect
        var isOversized: Bool
        /// The height of the preedit text, which a vertical panel keeps
        /// clear of the caret; nil without a preedit.
        var preeditHeight: CGFloat?
        var vertical: Bool
        var memorizeSize: Bool
        var edgeInset: CGSize
        var pagingOffset: CGFloat
        /// The longest line seen while this panel stays up (Squirrel's
        /// `maxHeight`); 0 at first.
        var memorizedLength: CGFloat = 0
    }

    struct Placement: Equatable {
        /// The window frame.
        var frame: CGRect
        /// The panel size before any scaling, in screen orientation; longer
        /// than `Input.size` when a vertical panel keeps its longest length.
        var size: CGSize
        var memorizedLength: CGFloat
    }

    /// Where the panel goes: below the caret, or for vertical text left of
    /// it, flipped and pushed back inside the screen as needed.
    static func place(_ input: Input) -> Placement {
        let screen = input.screen
        let caret = input.caret
        var size = input.size
        if input.isOversized {
            let scale = oversizedScale(size, screen: screen)
            let scaled = CGSize(width: size.width * scale, height: size.height * scale)
            let origin = CGPoint(x: screen.minX + (screen.width - scaled.width) / 2, y: screen.minY + (screen.height - scaled.height) / 2)
            return Placement(frame: CGRect(origin: origin, size: scaled), size: size, memorizedLength: 0)
        }

        var memorizedLength = input.memorizedLength
        var contentRect = input.contentRect
        // Squirrel's condition, operator precedence included: the second
        // half applies even without memorize_size.
        if input.memorizeSize && (input.vertical && caret.midY / screen.height < 0.5)
            || (input.vertical && caret.minX + max(contentRect.width, memorizedLength) + input.edgeInset.width * 2 > screen.maxX) {
            if contentRect.width >= memorizedLength {
                memorizedLength = contentRect.width
            } else {
                contentRect.size.width = memorizedLength
                if input.vertical {
                    size.height = contentRect.width + input.edgeInset.width * 2 + input.pagingOffset
                } else {
                    size.width = contentRect.width + input.edgeInset.width * 2 + input.pagingOffset
                }
            }
        }

        var frame = CGRect(origin: .zero, size: size)
        if input.vertical {
            // Stay on one side of the caret so the panel does not jump.
            if caret.midY / screen.height >= 0.5 {
                frame.origin.y = caret.minY - caretGap - frame.height + input.pagingOffset
            } else {
                frame.origin.y = caret.maxY + caretGap
            }
            frame.origin.x = caret.minX - frame.width - caretGap
            if let preeditHeight = input.preeditHeight {
                frame.origin.x += preeditHeight + input.edgeInset.width
            }
        } else {
            frame.origin = CGPoint(x: caret.minX - input.pagingOffset, y: caret.minY - caretGap - frame.height)
        }

        if frame.maxX > screen.maxX { frame.origin.x = screen.maxX - frame.width }
        if frame.minX < screen.minX { frame.origin.x = screen.minX }
        if frame.minY < screen.minY {
            frame.origin.y = input.vertical ? screen.minY : caret.maxY + caretGap
        }
        if frame.maxY > screen.maxY { frame.origin.y = screen.maxY - frame.height }
        if frame.minY < screen.minY { frame.origin.y = screen.minY }
        return Placement(frame: frame, size: size, memorizedLength: memorizedLength)
    }
}
