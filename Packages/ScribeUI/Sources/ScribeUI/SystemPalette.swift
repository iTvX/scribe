import AppKit
import ScribeConfig

/// The system colours a theme may refer to, resolved for one appearance.
///
/// Native themes depend on the user's accent and highlight colours; tests
/// pass a fixed palette so their images do not.
struct SystemPalette: Sendable {
    var windowBackground: NSColor
    var label: NSColor
    var secondaryLabel: NSColor
    var selectedTextBackground: NSColor
    var gray: NSColor

    init(windowBackground: NSColor, label: NSColor, secondaryLabel: NSColor, selectedTextBackground: NSColor, gray: NSColor) {
        self.windowBackground = windowBackground
        self.label = label
        self.secondaryLabel = secondaryLabel
        self.selectedTextBackground = selectedTextBackground
        self.gray = gray
    }

    /// The current system colours as they look in `appearance`.
    @MainActor
    init(resolvingIn appearance: NSAppearance) {
        var palette: SystemPalette?
        appearance.performAsCurrentDrawingAppearance {
            func resolved(_ color: NSColor) -> NSColor {
                color.usingColorSpace(.sRGB) ?? color
            }
            palette = SystemPalette(
                windowBackground: resolved(.windowBackgroundColor),
                label: resolved(.labelColor),
                secondaryLabel: resolved(.secondaryLabelColor),
                selectedTextBackground: resolved(.selectedTextBackgroundColor),
                gray: resolved(.gray)
            )
        }
        self = palette!
    }

    func color(_ color: SystemColor) -> NSColor {
        switch color {
        case .windowBackground: windowBackground
        case .label: label
        case .secondaryLabel: secondaryLabel
        case .selectedTextBackground: selectedTextBackground
        case .gray: gray
        }
    }
}
