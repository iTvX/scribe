import AppKit
import ScribeCore
@testable import ScribeUI
import Testing

/// Observe actual drawing, without taking a snapshot (which itself forces
/// AppKit to draw). No run-loop turn is allowed between show and the check.
@MainActor
@Suite(.serialized) struct CandidatePresentationTests {
    private final class DrawingView: PanelView {
        var drawnText: [String] = []

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            drawnText.append(text?.string.string ?? "")
        }
    }

    private let caret = NSRect(x: 200, y: 500, width: 1, height: 18)

    @Test func preparingTheWindowKeepsItHiddenAndNonactivating() {
        let view = DrawingView()
        let panel = CandidatePanel(panelView: view)
        panel.prepare()
        #expect(!panel.isVisible)
        #expect(view.window?.isVisible == false)
        #expect(view.window?.canBecomeKey == false)
        #expect(view.window?.animationBehavior == NSWindow.AnimationBehavior.none)
        #expect(view.drawnText.isEmpty)
    }

    @Test(arguments: [false, true]) func firstCandidatesAreDrawnBeforeShowReturns(vertical: Bool) {
        let view = DrawingView()
        let panel = CandidatePanel(panelView: view)
        var theme = Fixtures.wechatLight
        theme.orientation = vertical ? .vertical : .horizontal
        panel.appearance = .init(light: theme, dark: nil)
        defer { panel.hide() }

        panel.show(.init(entries: [.init(label: "1", text: "发")]), near: caret)

        #expect(view.drawnText.last?.contains("发") == true)
    }

    @Test func eachNewCompositionPaintsItsOwnFirstFrame() {
        let view = DrawingView()
        let panel = CandidatePanel(panelView: view)
        panel.appearance = .init(light: Fixtures.wechatLight, dark: nil)
        panel.prepare()
        defer { panel.hide() }

        for text in ["发", "你好", "中书", "非"] {
            panel.hide()
            view.drawnText = []
            panel.show(.init(entries: [.init(label: "1", text: text)]), near: caret)
            #expect(view.drawnText.last?.contains(text) == true)
        }
    }
}
