import ScribeCore
import Testing

@Suite struct ReservedPropertyTests {
    @Test func parsesTheNotificationValue() {
        #expect(ReservedProperty("_comment_highlight=1,3") == .commentHighlight([1, 3]))
        #expect(ReservedProperty("_comment_warning=value=2&by=plugin") == .commentWarning([2]))
        #expect(ReservedProperty("_refresh_ui=1") == .refreshUI)
        #expect(ReservedProperty("_comment_highlight= 0 , 4 ") == .commentHighlight([0, 4]))
    }

    @Test func ignoresWhatItDoesNotKnow() {
        #expect(ReservedProperty("client_app=com.apple.TextEdit") == nil)
        #expect(ReservedProperty("_comment_highlight=one") == nil)
        #expect(ReservedProperty("_comment_highlight=-1") == nil)
        #expect(ReservedProperty("_comment_highlight=") == nil)
        #expect(ReservedProperty("_comment_highlight=label=1") == nil)
        #expect(ReservedProperty("_something_else=1") == nil)
    }
}
