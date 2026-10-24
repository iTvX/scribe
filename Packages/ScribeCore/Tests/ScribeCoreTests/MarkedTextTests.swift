import RimeKit
@testable import ScribeCore
import Testing

/// The marked text handed to the client, with where the input being converted
/// starts, as Squirrel's `show(preedit:selRange:caretPos:)` gets them.
@Suite struct MarkedTextTests {
    static let inlinePreedit = (preedit: true, candidate: false)

    @Test func nothingConvertedYet() {
        let composition = Composition(preedit: "wo", cursor: 2, selectionStart: 0, selectionEnd: 2)
        #expect(InputSession.markedText(for: composition, preview: "我", inline: Self.inlinePreedit)
            == MarkedText(text: "wo", caret: 2, selectionStart: 0))
    }

    @Test func theConvertedWordsComeBeforeTheSelection() {
        // 你 already chosen, "hao" still being converted.
        let composition = Composition(preedit: "你hao", cursor: 4, selectionStart: 1, selectionEnd: 4)
        #expect(InputSession.markedText(for: composition, preview: "你好", inline: Self.inlinePreedit)
            == MarkedText(text: "你hao", caret: 4, selectionStart: 1))
    }

    @Test func theCaretCanBeInsideTheInput() {
        let composition = Composition(preedit: "xiang zuo guangbiao", cursor: 9, selectionStart: 0, selectionEnd: 9)
        #expect(InputSession.markedText(for: composition, preview: nil, inline: Self.inlinePreedit)
            == MarkedText(text: "xiang zuo guangbiao", caret: 9, selectionStart: 0))
    }

    @Test func thePlaceholderIsMarkedFromTheStart() {
        let composition = Composition(preedit: "ni‸", cursor: 2, selectionStart: 0, selectionEnd: 2)
        #expect(InputSession.markedText(for: composition, preview: "你", inline: (false, false))
            == MarkedText(text: "　", caret: 0, selectionStart: 0))
    }

    @Test func anInlineCandidateIsMarkedFromTheSelection() {
        // preedit:             已选[xiang zuo]yidong|guangbiao
        // commit_text_preview: 已选向左yidong
        // marked text:         已选[向左]yidong|guangbiao, caret after the preview
        let composition = Composition(preedit: "已选xiang zuoyidongguangbiao", cursor: 17, selectionStart: 2, selectionEnd: 11)
        #expect(InputSession.markedText(for: composition, preview: "已选向左yidong", inline: (true, true))
            == MarkedText(text: "已选向左yidongguangbiao", caret: 10, selectionStart: 2))
    }

    @Test func aSelectionPastThePreviewIsClamped() {
        // A prompt before the selection makes it start past the preview.
        let composition = Composition(preedit: "〔筆畫〕hspn", cursor: 8, selectionStart: 4, selectionEnd: 8)
        #expect(InputSession.markedText(for: composition, preview: "木", inline: (false, true))
            == MarkedText(text: "木", caret: 1, selectionStart: 1))
    }
}
