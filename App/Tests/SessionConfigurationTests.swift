import RimeKit
import ScribeConfig
import ScribeCore
import ScribeTestSupport
import Testing

@MainActor
@Suite struct SessionConfigurationTests {
    func settings(_ yaml: String) throws -> ScribeSettings {
        try #require(TestRime.engine.withConfig(.yaml(yaml)) { ScribeSettings(squirrel: $0) })
    }

    @Test func takesTheSettingsAndTheTheme() throws {
        let settings = try settings("""
            chord_duration: 0.3
            show_notifications_when: never
            keyboard_layout: default
            unsafe:
              report_bundleid: true
            app_options:
              com.apple.Terminal:
                ascii_mode: true
                no_inline: true
            """)
        var theme = Theme()
        theme.inlinePreedit = false
        theme.inlineCandidate = true
        theme.layout = .linear
        theme.orientation = .vertical
        theme.statusMessageType = .long

        let configuration = SessionConfiguration(settings: settings, theme: theme)
        #expect(configuration.chordDuration == 0.3)
        #expect(configuration.notifications == .never)
        #expect(configuration.statusMessageType == .long)
        #expect(configuration.keyboardLayout == .named("com.apple.keylayout.ABC"))
        #expect(configuration.presentation == InputSession.Presentation(inlinePreedit: false, inlineCandidate: true, linear: true, vertical: true))
        #expect(configuration.clientApp("com.apple.Terminal") == InputSession.ClientApp(
            bundleID: "com.apple.Terminal",
            options: ["ascii_mode": true, "no_inline": true],
            reportsBundleID: true
        ))
        #expect(configuration.clientApp("com.apple.TextEdit").options.isEmpty)
    }

    /// Before squirrel.yaml is read, sessions behave like Squirrel's default
    /// style: the input inline, announcements as they fit.
    @Test func defaultsMatchSquirrel() {
        let configuration = SessionConfiguration()
        #expect(configuration.presentation == InputSession.Presentation())
        #expect(configuration.notifications == .appropriate)
        #expect(configuration.statusMessageType == .mix)
        #expect(configuration.keyboardLayout == .last)
    }
}
