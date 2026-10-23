import AppKit
import ScribeConfig
import ScribeCore
@testable import ScribeUI
import Testing

/// Records what the panel reports.
@MainActor
private final class Recorder: CandidatePanelDelegate {
    enum Call: Equatable {
        case select(Int), page(PageDirection), caret(CaretMove)
    }

    var calls: [Call] = []

    func candidatePanel(_ panel: CandidatePanel, didSelectCandidateAt index: Int) {
        calls.append(.select(index))
    }

    func candidatePanel(_ panel: CandidatePanel, didRequestPage direction: PageDirection) {
        calls.append(.page(direction))
    }

    func candidatePanel(_ panel: CandidatePanel, didRequestCaretMove direction: CaretMove) {
        calls.append(.caret(direction))
    }
}

@MainActor
@Suite(.serialized) struct CandidatePanelTests {
    private let caret = NSRect(x: 200, y: 500, width: 1, height: 18)

    private func panel(_ theme: Theme = Fixtures.squirrelDefaults) -> (CandidatePanel, Recorder) {
        let panel = CandidatePanel()
        panel.appearance = Appearance(light: theme, dark: nil)
        panel.palette = { _ in Fixtures.lightPalette }
        let recorder = Recorder()
        panel.delegate = recorder
        return (panel, recorder)
    }

    private func center(of candidate: Int, in panel: CandidatePanel) throws -> CGPoint {
        let rect = try #require(panel.view.textRect(ofCandidate: candidate))
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    @Test func showAndHide() {
        let (panel, _) = panel()
        #expect(!panel.isVisible)
        panel.show(Fixtures.pinyinPage, near: caret)
        #expect(panel.isVisible)
        panel.hide()
        #expect(!panel.isVisible)
    }

    @Test func placedBelowTheCaret() {
        let (panel, _) = panel()
        panel.show(Fixtures.pinyinPage, near: caret)
        defer { panel.hide() }
        #expect(panel.frame.minX == caret.minX)
        #expect(panel.frame.maxY == caret.minY - PanelPlacement.caretGap)
        // AppKit rounds the window to whole points; the panel keeps its size.
        #expect(abs(panel.view.frame.width - panel.frame.width) < 1)
        #expect(abs(panel.view.frame.height - panel.frame.height) < 1)
    }

    @Test func nothingToShowHides() {
        let (panel, _) = panel()
        panel.show(Fixtures.pinyinPage, near: caret)
        // The session sends no preedit when it is inline.
        panel.show(CandidateSnapshot(entries: [], preedit: nil), near: caret)
        #expect(!panel.isVisible)
    }

    @Test func aPreeditAloneShows() {
        let (panel, _) = panel()
        panel.show(CandidateSnapshot(entries: [], preedit: Preedit(text: "zh", selectedRange: 0..<2, caret: 2)), near: caret)
        #expect(panel.isVisible)
        panel.hide()
    }

    @Test func statusMessagesHideByThemselves() async throws {
        let (panel, _) = panel()
        panel.statusDuration = .milliseconds(50)
        panel.showStatus("中文", near: caret)
        #expect(panel.isVisible)
        // An empty update does not cut the message short.
        panel.show(CandidateSnapshot(entries: []), near: caret)
        #expect(panel.isVisible)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!panel.isVisible)
    }

    @Test func candidatesReplaceTheStatusMessage() async throws {
        let (panel, _) = panel()
        panel.statusDuration = .milliseconds(50)
        panel.showStatus("中文", near: caret)
        panel.show(Fixtures.pinyinPage, near: caret)
        try await Task.sleep(for: .milliseconds(300))
        #expect(panel.isVisible)
        panel.hide()
    }

    @Test func clickingACandidateSelectsIt() throws {
        let (panel, recorder) = panel()
        panel.show(Fixtures.pinyinPage, near: caret)
        defer { panel.hide() }
        let second = try center(of: 1, in: panel)
        panel.mouseDown(at: second)
        panel.mouseUp(at: second)
        #expect(recorder.calls == [.select(1)])
    }

    @Test func releasingOnAnotherCandidateSelectsNothing() throws {
        let (panel, recorder) = panel()
        panel.show(Fixtures.pinyinPage, near: caret)
        defer { panel.hide() }
        panel.mouseDown(at: try center(of: 1, in: panel))
        panel.mouseUp(at: try center(of: 2, in: panel))
        #expect(recorder.calls.isEmpty)
        // Squirrel compares with the highlighted row when the press missed
        // every candidate.
        panel.mouseDown(at: CGPoint(x: -10, y: -10))
        panel.mouseUp(at: try center(of: 1, in: panel))
        #expect(recorder.calls == [.select(1)])
    }

    @Test func hoveringHighlightsOnlyInTheWindow() throws {
        let (panel, recorder) = panel()
        panel.show(Fixtures.pinyinPage, near: caret)
        defer { panel.hide() }
        panel.mouseMoved(to: try center(of: 3, in: panel))
        #expect(panel.displayedIndex == 3)
        panel.mouseExited()
        #expect(panel.displayedIndex == 0)
        #expect(recorder.calls.isEmpty)
    }

    @Test func pagingArrowsPage() throws {
        var theme = Fixtures.squirrelDefaults
        theme.showPaging = true
        let (panel, recorder) = panel(theme)
        panel.show(CandidateSnapshot(entries: Fixtures.pinyinPage.entries, pageNumber: 1, isLastPage: false), near: caret)
        defer { panel.hide() }
        // The arrows sit in the 24-point paging strip, a third and two
        // thirds down the first row with its line spacing, below the top
        // inset; pressing one and releasing on the other does nothing.
        let height = try #require(panel.view.textRect(ofCandidate: 0)).height + 5
        let top = 5 - 2.5
        let down = CGPoint(x: 12, y: top + height * 2 / 3)
        let up = CGPoint(x: 12, y: top + height / 3)
        #expect(panel.view.hit(at: down).page == .down)
        #expect(panel.view.hit(at: up).page == .up)
        panel.mouseDown(at: down)
        panel.mouseUp(at: down)
        panel.mouseDown(at: up)
        panel.mouseUp(at: down)
        #expect(recorder.calls == [.page(.down)])
    }

    @Test func clickingThePreeditMovesTheCaretOneStep() throws {
        var theme = Fixtures.squirrelDefaults
        theme.inlinePreedit = false
        let (panel, recorder) = panel(theme)
        var snapshot = Fixtures.pinyinPage
        snapshot.preedit = Preedit(text: "zhong shu", selectedRange: 0..<9, caret: 6)
        panel.show(snapshot, near: caret)
        defer { panel.hide() }
        let row = try #require(panel.view.textRect(ofCandidate: 0))
        let preeditY = row.minY - 12
        func click(_ x: CGFloat) {
            let point = CGPoint(x: x, y: preeditY)
            panel.mouseDown(at: point)
            panel.mouseUp(at: point)
        }
        click(row.minX + 3)
        #expect(panel.view.hit(at: CGPoint(x: row.minX + 3, y: preeditY)).preeditIndex == 0)
        click(row.minX + 60)
        #expect(recorder.calls == [.caret(.towardStart), .caret(.towardEnd)])
    }

    @Test func windowShowsWhatTheRendererDraws() throws {
        var theme = Fixtures.aqua
        theme.shadowSize = 4
        theme.hilitedCornerRadius = 4
        let (panel, _) = panel(theme)
        panel.show(Fixtures.pinyinPage, near: caret)
        defer { panel.hide() }
        let layer = try #require(panel.view.layer)
        let scale = panel.backingScale
        let size = panel.view.bounds.size
        let context = try #require(CGContext(
            data: nil, width: Int((size.width * scale).rounded(.up)), height: Int((size.height * scale).rounded(.up)),
            bitsPerComponent: 8, bytesPerRow: 0, space: PanelRenderer.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // The view is flipped, and so is its layer's geometry. The window
        // cuts the panel where AppKit rounds its content view.
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: scale, y: -scale)
        context.clip(to: PanelRenderer.windowClip(viewSize: size, screenSize: size, vertical: false, scale: scale))
        layer.render(in: context)
        let window = try #require(context.makeImage())
        let expected = try #require(PanelRenderer.render(
            Fixtures.content(Fixtures.pinyinPage),
            theme: PanelTheme(theme, palette: Fixtures.lightPalette),
            appearance: Fixtures.light,
            scale: scale
        ))
        let comparison = Snapshot.Comparison(expected: expected, actual: window)
        #expect(comparison.matches, "\(comparison)")
        if !comparison.matches {
            let failures = Snapshot.artifactsDirectory.appending(path: "window")
            try? Snapshot.write(expected, to: failures.appending(path: "renderer.png"))
            try? Snapshot.write(window, to: failures.appending(path: "window.png"))
        }
    }

    /// The window turns a vertical panel with a layer transform, so the
    /// panel itself draws unturned, as the renderer draws it.
    @Test func verticalPanelsTurnAsLayers() throws {
        var theme = Fixtures.squirrelDefaults
        theme.orientation = .vertical
        let (panel, _) = panel(theme)
        panel.show(Fixtures.pinyinPage, near: caret)
        defer { panel.hide() }
        let contentLayer = try #require(panel.contentView?.layer)
        let turn = contentLayer.affineTransform()
        #expect(abs(turn.a) < 1e-9 && abs(turn.d) < 1e-9)
        #expect(turn.b == -1 && turn.c == 1)
        #expect(panel.view.layer?.affineTransform() == .identity)
        // Lines run down the screen: the window is as tall as the view is wide.
        #expect(abs(panel.frame.height - panel.view.frame.width) < 1)
        #expect(abs(panel.frame.width - panel.view.frame.height) < 1)
    }

    @Test func commentMarksFromTheSnapshotReachTheDrawing() throws {
        var theme = Fixtures.lostTemple
        theme.colors.accentText = Fixtures.color("0x3c9cff")
        theme.colors.warningText = Fixtures.color("0x3030ff")
        let (panel, _) = panel(theme)
        // Rows 1 and 3 have comments; row 0 is highlighted.
        var snapshot = Fixtures.pinyinPage
        snapshot.accentCommentIndices = [1]
        snapshot.warningCommentIndices = [3]
        panel.show(snapshot, near: caret)
        defer { panel.hide() }
        let text = try #require(panel.view.text)
        func commentColor(_ row: Int) -> NSColor? {
            text.string.attribute(.foregroundColor, at: NSMaxRange(text.candidateRanges[row]) - 1, effectiveRange: nil) as? NSColor
        }
        let drawn = PanelTheme(theme, palette: Fixtures.lightPalette)
        #expect(commentColor(1) == drawn.accentCommentTextColor)
        #expect(commentColor(3) == drawn.warningCommentTextColor)
    }

    /// Squirrel's choice: the dark theme in dark mode when there is one;
    /// a light-only scheme that is not native keeps the light appearance.
    @Test func darkModeUsesTheDarkThemeWhenThereIsOne() {
        let panel = themedPanel(Appearance(light: Fixtures.aqua, dark: Fixtures.lostTemple), system: Fixtures.dark)
        defer { panel.hide() }
        #expect(panel.view.theme?.backgroundColor == PanelTheme(Fixtures.lostTemple, palette: Fixtures.darkPalette).backgroundColor)
        #expect(panel.windowAppearance?.name == .darkAqua)

        panel.systemAppearance = { Fixtures.light }
        panel.show(Fixtures.pinyinPage, near: caret)
        #expect(panel.view.theme?.backgroundColor == PanelTheme(Fixtures.aqua, palette: Fixtures.lightPalette).backgroundColor)
        #expect(panel.windowAppearance?.name == .aqua)
    }

    @Test func aLightOnlySchemeStaysLightInDarkMode() {
        let appearance = Appearance(light: Fixtures.aqua, dark: nil)
        #expect(appearance.forcesLightAppearance)
        let panel = themedPanel(appearance, system: Fixtures.dark)
        defer { panel.hide() }
        #expect(panel.view.theme?.backgroundColor == PanelTheme(Fixtures.aqua, palette: Fixtures.lightPalette).backgroundColor)
        #expect(panel.windowAppearance?.name == .aqua)
    }

    @Test func nativeColoursFollowTheSystemWithoutADarkTheme() {
        let panel = themedPanel(Appearance(light: Fixtures.squirrelDefaults, dark: nil), system: Fixtures.dark)
        defer { panel.hide() }
        #expect(panel.view.theme?.backgroundColor == Fixtures.darkPalette.windowBackground)
        #expect(panel.windowAppearance?.name == .darkAqua)
    }

    private func themedPanel(_ appearance: Appearance, system: NSAppearance) -> CandidatePanel {
        let panel = CandidatePanel()
        panel.appearance = appearance
        panel.palette = { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? Fixtures.darkPalette : Fixtures.lightPalette }
        panel.systemAppearance = { system }
        panel.screenFrame = { _ in PanelRenderer.referenceScreen }
        panel.show(Fixtures.pinyinPage, near: caret)
        return panel
    }

    @Test func pointsOutsideThePanelHitNothing() throws {
        let (panel, _) = panel()
        panel.show(Fixtures.pinyinPage, near: caret)
        defer { panel.hide() }
        #expect(panel.view.hit(at: CGPoint(x: -5, y: 10)) == PanelHit())
        #expect(panel.view.hit(at: try center(of: 4, in: panel)).candidate == 4)
    }
}
