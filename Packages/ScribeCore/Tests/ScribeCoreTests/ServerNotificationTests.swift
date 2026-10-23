import ScribeCore
import Testing

@Test func notificationNamesAreStable() {
    // Other programs, such as the settings app, post these by name.
    #expect(ServerNotification.reload == "io.github.itvx.inputmethod.Scribe.ReloadNotification")
    #expect(ServerNotification.sync == "io.github.itvx.inputmethod.Scribe.SyncNotification")
    #expect(ServerNotification.setASCIIMode == "io.github.itvx.inputmethod.Scribe.SetASCIIModeNotification")
    #expect(ServerNotification.getASCIIMode == "io.github.itvx.inputmethod.Scribe.GetASCIIModeNotification")
    #expect(ServerNotification.asciiModeResponse == "io.github.itvx.inputmethod.Scribe.ASCIIModeResponse")
}
