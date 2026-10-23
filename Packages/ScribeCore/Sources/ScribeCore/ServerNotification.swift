/// Distributed notifications the running input method responds to. Posted by
/// `Scribe --reload` and `Scribe --sync`, and by other programs such as the
/// settings app.
public enum ServerNotification {
    /// Restart librime and deploy everything again.
    public static let reload = "io.github.itvx.inputmethod.Scribe.ReloadNotification"
    /// Synchronize user data with the sync directory.
    public static let sync = "io.github.itvx.inputmethod.Scribe.SyncNotification"
    /// Turn ASCII mode on or off; the object is "ascii" or "nascii".
    public static let setASCIIMode = "io.github.itvx.inputmethod.Scribe.SetASCIIModeNotification"
    /// Ask for the ASCII mode of the active client's session.
    public static let getASCIIMode = "io.github.itvx.inputmethod.Scribe.GetASCIIModeNotification"
    /// The answer to getASCIIMode; the object is "ascii" or "nascii".
    public static let asciiModeResponse = "io.github.itvx.inputmethod.Scribe.ASCIIModeResponse"
}
