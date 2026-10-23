import ScribeUI
import Testing

@MainActor
@Test func panelStartsHidden() {
    let panel = CandidatePanel()
    #expect(!panel.isVisible)
    panel.hide()
    #expect(!panel.isVisible)
}
