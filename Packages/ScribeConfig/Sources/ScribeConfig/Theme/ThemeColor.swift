/// The colour space a colour scheme's values are given in.
public enum ColorSpace: String, Sendable {
    case sRGB, displayP3

    /// A scheme's `color_space`: only "display_p3" selects Display P3.
    public init(squirrel name: String?) {
        self = name == "display_p3" ? .displayP3 : .sRGB
    }
}

/// An 8-bit RGBA colour from a colour scheme.
public struct RGBAColor: Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8
    public var colorSpace: ColorSpace

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255, colorSpace: ColorSpace = .sRGB) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.colorSpace = colorSpace
    }

    /// Squirrel's colour literal: "0xAABBGGRR", or "0xBBGGRR" with an opaque
    /// alpha. The whole string must match, with a lowercase "0x".
    public init?(squirrel value: String, colorSpace: ColorSpace) {
        let digits: Substring
        if let match = value.wholeMatch(of: /0x([A-Fa-f0-9]{8})/) {
            digits = match.output.1
        } else if let match = value.wholeMatch(of: /0x([A-Fa-f0-9]{6})/) {
            digits = "FF" + match.output.1
        } else {
            return nil
        }
        guard let packed = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: UInt8(truncatingIfNeeded: packed),
            green: UInt8(truncatingIfNeeded: packed >> 8),
            blue: UInt8(truncatingIfNeeded: packed >> 16),
            alpha: UInt8(truncatingIfNeeded: packed >> 24),
            colorSpace: colorSpace
        )
    }

    public var redComponent: Double { Double(red) / 255 }
    public var greenComponent: Double { Double(green) / 255 }
    public var blueComponent: Double { Double(blue) / 255 }
    public var alphaComponent: Double { Double(alpha) / 255 }

    /// "#RRGGBBAA", for snapshots and the settings UI.
    public var hex: String {
        "#" + [red, green, blue, alpha].map { byte in
            let digits = String(byte, radix: 16, uppercase: true)
            return digits.count == 1 ? "0" + digits : digits
        }.joined()
    }
}

/// The AppKit system colours Squirrel's native palette uses.
public enum SystemColor: String, Sendable {
    case windowBackground, label, secondaryLabel, selectedTextBackground, gray
}

/// A theme colour, resolved to an NSColor by the renderer.
public indirect enum ThemeColor: Equatable, Sendable {
    case rgba(RGBAColor)
    case system(SystemColor)
    /// Squirrel's label colour: (2 × foreground + background) / 3 per component, alpha included, in deviceRGB.
    case blend(foreground: ThemeColor, background: ThemeColor)
}
