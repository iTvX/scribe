import ScribeConfig
import Testing

@Suite("Candidate format")
struct CandidateFormatTests {
    @Test func defaultFormat() {
        let format = CandidateFormat.default
        #expect(format.template == "[label]. [candidate] [comment]")
        #expect(format.segments == [.label, .text(". "), .candidate, .text(" "), .comment])
        #expect(format.showsLabel)
    }

    @Test(arguments: [
        ("%c %@", "[label] [candidate] [comment]"),
        ("%c\u{2005}%@\u{2005}", "[label]\u{2005}[candidate] [comment]\u{2005}"),
        ("%@%@", "[candidate] [comment][candidate] [comment]"),
        ("%c%c", "[label][label]"),
        ("%c. [candidate]", "[label]. [candidate]"),
        ("[label] %@", "[label] [candidate] [comment]"),
        ("%%c", "%[label]"),
        ("%C %", "%C %"),
        ("", ""),
    ])
    func legacyTokens(squirrel: String, template: String) {
        #expect(CandidateFormat(squirrel).template == template)
    }

    @Test func maxsFormat() {
        let format = CandidateFormat("%c\u{2005}%@\u{2005}")
        #expect(format.segments == [.label, .text("\u{2005}"), .candidate, .text(" "), .comment, .text("\u{2005}")])
        #expect(format.showsLabel)
    }

    @Test func repeatedTokens() {
        let format = CandidateFormat("[candidate][candidate] ([comment])[label]")
        #expect(format.segments == [.candidate, .candidate, .text(" ("), .comment, .text(")"), .label])
    }

    @Test func unknownBracketsAreText() {
        let format = CandidateFormat("[index] [candidate] [Label]")
        #expect(format.segments == [.text("[index] "), .candidate, .text(" [Label]")])
        #expect(!format.showsLabel)
    }

    @Test func withoutLabel() {
        #expect(!CandidateFormat("%@").showsLabel)
        #expect(CandidateFormat("%@").segments == [.candidate, .text(" "), .comment])
        #expect(CandidateFormat("").segments == [])
    }
}
