import ScribeConfig
import Testing

@Suite("Colour literals")
struct ColorTests {
    @Test(arguments: [
        ("0x75B100", "#00B175FF"),
        ("0x000000", "#000000FF"),
        ("0xffffff", "#FFFFFFFF"),
        ("0xfFaAbB", "#BBAAFFFF"),
        ("0x80fFaAbB", "#BBAAFF80"),
        ("0xeefa3a0a", "#0A3AFAEE"),
        ("0x00000000", "#00000000"),
    ])
    func valid(literal: String, hex: String) {
        #expect(RGBAColor(squirrel: literal, colorSpace: .sRGB)?.hex == hex)
    }

    @Test func byteOrderIsAlphaBlueGreenRed() {
        let color = RGBAColor(squirrel: "0x11223344", colorSpace: .sRGB)
        #expect(color == RGBAColor(red: 0x44, green: 0x33, blue: 0x22, alpha: 0x11))
    }

    @Test(arguments: [
        "", "0x", "0x75B10", "0x75B1000", "0x75B100001", "0x75B10000FF", "0X75B100", "#75B100", "75B100",
        " 0x75B100", "0x75B100 ", "0x 75B100", "0x75B10G", "0x75B100\n", "red",
    ])
    func invalid(literal: String) {
        #expect(RGBAColor(squirrel: literal, colorSpace: .sRGB) == nil)
    }

    @Test func colorSpaceTagging() {
        #expect(RGBAColor(squirrel: "0x75B100", colorSpace: .displayP3)?.colorSpace == .displayP3)
        #expect(ColorSpace(squirrel: "display_p3") == .displayP3)
        #expect(ColorSpace(squirrel: "Display_P3") == .sRGB)
        #expect(ColorSpace(squirrel: "srgb") == .sRGB)
        #expect(ColorSpace(squirrel: nil) == .sRGB)
    }

    @Test func components() throws {
        let color = try #require(RGBAColor(squirrel: "0x80FF0000", colorSpace: .sRGB))
        #expect(color.redComponent == 0)
        #expect(color.greenComponent == 0)
        #expect(color.blueComponent == 1)
        #expect(color.alphaComponent == 128.0 / 255)
    }
}
