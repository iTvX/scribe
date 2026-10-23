import AppKit
import ScribeCore
@testable import ScribeUI
import Testing

private let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
private let size = NSSize(width: 200, height: 30)

@Test func placedBelowTheCaretLine() {
    let caret = NSRect(x: 100, y: 400, width: 1, height: 18)
    let frame = CandidatePanelLayout.frame(size: size, caretRect: caret, visibleFrame: screen)
    #expect(frame == NSRect(x: 100, y: 400 - CandidatePanelLayout.gap - 30, width: 200, height: 30))
}

@Test func placedAboveWhenThereIsNoRoomBelow() {
    let caret = NSRect(x: 100, y: 10, width: 1, height: 18)
    let frame = CandidatePanelLayout.frame(size: size, caretRect: caret, visibleFrame: screen)
    #expect(frame.minY == caret.maxY + CandidatePanelLayout.gap)
}

@Test func keptInsideTheScreenHorizontally() {
    let nearRight = NSRect(x: 950, y: 400, width: 1, height: 18)
    #expect(CandidatePanelLayout.frame(size: size, caretRect: nearRight, visibleFrame: screen).maxX == screen.maxX)
    let offLeft = NSRect(x: -20, y: 400, width: 1, height: 18)
    #expect(CandidatePanelLayout.frame(size: size, caretRect: offLeft, visibleFrame: screen).minX == screen.minX)
}

@MainActor
@Test func viewSizesToItsCandidates() {
    let view = CandidateView()
    view.snapshot = CandidateSnapshot(entries: [
        .init(label: "1", text: "你"),
        .init(label: "2", text: "你好", comment: "ni hao"),
    ])
    let frames = view.entryFrames
    #expect(frames.count == 2)
    #expect(frames[0].maxX < frames[1].minX)
    #expect(frames[1].width > frames[0].width)
    #expect(view.fittingSize.width > frames[1].maxX)
    #expect(view.fittingSize.height > frames[0].height)

    view.snapshot = CandidateSnapshot(entries: [])
    #expect(view.entryFrames.isEmpty)
}

@MainActor
@Test func showAndHide() {
    let panel = CandidatePanel()
    #expect(!panel.isVisible)
    panel.show(CandidateSnapshot(entries: [.init(label: "1", text: "你")]), near: NSRect(x: 100, y: 400, width: 1, height: 18))
    #expect(panel.isVisible)
    panel.hide()
    #expect(!panel.isVisible)
}
