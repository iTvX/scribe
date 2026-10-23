import ScribeConfig
import Testing

@Suite("Fonts")
struct FontTests {
    @Test func familyAndStyle() {
        #expect(FontFace.list(squirrel: "PingFangSC-Regular,HanaMinB") == [
            FontFace(name: "PingFangSC-Regular", family: "PingFangSC", style: "Regular"),
            FontFace(name: "HanaMinB"),
        ])
    }

    @Test func stylesWithSpaces() {
        #expect(FontFace.list(squirrel: "HYQiHei-55S Book,HanaMinA Regular") == [
            FontFace(name: "HYQiHei-55S Book", family: "HYQiHei", style: "55S Book"),
            FontFace(name: "HanaMinA Regular"),
        ])
    }

    @Test func surroundingSpaces() {
        #expect(FontFace.list(squirrel: " Avenir ") == [FontFace(name: "Avenir")])
        // The regex keeps trailing spaces in the style; the name is trimmed.
        #expect(FontFace.list(squirrel: " Foo-Bar ") == [FontFace(name: "Foo-Bar", family: "Foo", style: "Bar ")])
    }

    @Test func lastHyphenSplits() {
        #expect(FontFace.list(squirrel: "Source-Han-Sans-Bold") == [
            FontFace(name: "Source-Han-Sans-Bold", family: "Source-Han-Sans", style: "Bold"),
        ])
        #expect(FontFace.list(squirrel: "Trailing-") == [FontFace(name: "Trailing-")])
    }

    @Test func emptyPieces() {
        #expect(FontFace.list(squirrel: "Avenir,,Menlo,") == [FontFace(name: "Avenir"), FontFace(name: "Menlo")])
        #expect(FontFace.list(squirrel: ",") == [])
        #expect(FontFace.list(squirrel: "") == [])
        #expect(FontFace.list(squirrel: nil) == [])
        // A blank piece is not empty, so it stays, with an empty name.
        #expect(FontFace.list(squirrel: "Avenir, ") == [FontFace(name: "Avenir"), FontFace(name: "")])
    }

    @Test func labelCommentAndPreeditInheritTheCandidateFont() {
        let config: ConfigNode = [
            "style": [
                "font_face": "Avenir",
                "font_point": 16,
                "label_font_point": 12,
                "comment_font_face": "Menlo",
                "preedit_font_face": "Courier",
                "preedit_font_point": 14,
            ],
        ]
        let theme = Theme(source: config, colorSchemeKey: "style/color_scheme")
        #expect(theme.candidateFont == ThemeFont(faces: [FontFace(name: "Avenir")], pointSize: 16))
        #expect(theme.labelFont == ThemeFont(faces: [FontFace(name: "Avenir")], pointSize: 12))
        #expect(theme.commentFont == ThemeFont(faces: [FontFace(name: "Menlo")], pointSize: 16))
        #expect(theme.preeditFont == ThemeFont(faces: [FontFace(name: "Courier")], pointSize: 14))
    }

    @Test func schemeFontKeysOverrideStyleBeforeInheriting() {
        let config: ConfigNode = [
            "style": [
                "color_scheme": "custom",
                "font_face": "Avenir",
                "font_point": 16,
                "label_font_face": "Menlo",
            ],
            "preset_color_schemes": [
                "custom": ["font_face": "PingFangSC-Regular", "comment_font_point": 10],
            ],
        ]
        let theme = Theme(source: config, colorSchemeKey: "style/color_scheme")
        let pingFang = FontFace(name: "PingFangSC-Regular", family: "PingFangSC", style: "Regular")
        #expect(theme.candidateFont == ThemeFont(faces: [pingFang], pointSize: 16))
        #expect(theme.labelFont == ThemeFont(faces: [FontFace(name: "Menlo")], pointSize: 16))
        #expect(theme.commentFont == ThemeFont(faces: [pingFang], pointSize: 10))
        #expect(theme.preeditFont == ThemeFont(faces: [pingFang], pointSize: 16))
    }

    @Test func noFontKeys() {
        let theme = Theme(source: ConfigNode.map([:]), colorSchemeKey: "style/color_scheme")
        for font in [theme.candidateFont, theme.labelFont, theme.commentFont, theme.preeditFont] {
            #expect(font == ThemeFont(faces: [], pointSize: nil))
        }
    }

    @Test func sizeWithoutFace() {
        let config: ConfigNode = ["style": ["label_font_point": 12]]
        let theme = Theme(source: config, colorSchemeKey: "style/color_scheme")
        #expect(theme.candidateFont == ThemeFont())
        #expect(theme.labelFont == ThemeFont(faces: [], pointSize: 12))
    }
}
