import AppKit
import ObjectiveC

/// The frame each window last asked for, before AppKit rounds it.
var requestedFrames: [ObjectIdentifier: NSRect] = [:]

extension NSWindow {
    /// Swapped with setFrame(_:display:), so this calls the original.
    @objc func oracle_setFrame(_ frame: NSRect, display: Bool) {
        requestedFrames[ObjectIdentifier(self)] = frame
        oracle_setFrame(frame, display: display)
    }
}

func recordRequestedFrames() {
    guard let original = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.setFrame(_:display:))),
          let recording = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.oracle_setFrame(_:display:))) else {
        fail("cannot watch setFrame(_:display:)")
    }
    method_exchangeImplementations(original, recording)
}

/// The cases in Tests/Fixtures/snapshots/placements.json.
struct Placements: Decodable {
    struct Step: Decodable {
        var caret: [Double]?
        var content: Cases.ContentReference?
        var hide: Bool?
    }

    struct Case: Decodable {
        var name: String
        var style: [String: String]
        var steps: [Step]
    }

    var screen: [Double]
    var contents: [String: Cases.Content]
    var cases: [Case]
}

/// Runs each case's steps in one SquirrelPanel and writes, per step, the
/// window frame Squirrel asked for, its panel view's size and the content
/// view's bounds rotation; a hide step gives null.
@MainActor
func recordPlacements(from url: URL, cases: Cases, to output: URL, only: Set<String>) {
    let placements: Placements
    do {
        placements = try JSONDecoder().decode(Placements.self, from: Data(contentsOf: url))
    } catch {
        fail("cannot read \(url.path): \(error)")
    }
    guard placements.screen == [fixedScreen.minX, fixedScreen.minY, fixedScreen.width, fixedScreen.height].map(Double.init) else {
        fail("placements.json must use the oracle's fixed screen \(fixedScreen)")
    }
    func content(_ reference: Cases.ContentReference) -> Cases.Content {
        switch reference {
        case let .named(name):
            guard let content = placements.contents[name] ?? cases.contents[name] else { fail("no content named \(name)") }
            return content
        case let .inline(content):
            return content
        }
    }
    app.appearance = NSAppearance(named: .aqua)
    // Cases left out by a name filter keep what was recorded before.
    var results: [String: Any] = [:]
    if !only.isEmpty, let data = try? Data(contentsOf: output),
       let recorded = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let recordedCases = recorded["cases"] as? [String: Any] {
        results = recordedCases
    }
    for placementCase in placements.cases where only.isEmpty || only.contains(placementCase.name) {
        let base = Cases.Case(name: placementCase.name, style: placementCase.style, content: .named("pinyin"))
        let config: [String: String]
        do {
            config = try cases.config(for: base, configs: url.deletingLastPathComponent().appending(path: "configs"))
        } catch {
            fail("cannot read the config of \(placementCase.name): \(error)")
        }
        guard let first = placementCase.steps.first(where: { $0.caret != nil }), let firstCaret = first.caret, let firstContent = first.content else {
            fail("\(placementCase.name) has no step that shows the panel")
        }
        let panel = SquirrelPanel(position: NSRect(x: firstCaret[0], y: firstCaret[1], width: firstCaret[2], height: firstCaret[3]))
        load(panel, config: SquirrelConfig(config), content: content(firstContent))
        var frames: [Any] = []
        for step in placementCase.steps {
            if step.hide == true {
                panel.hide()
                frames.append(NSNull())
                continue
            }
            guard let caret = step.caret, let reference = step.content else { fail("a step of \(placementCase.name) has no caret or content") }
            panel.position = NSRect(x: caret[0], y: caret[1], width: caret[2], height: caret[3])
            requestedFrames[ObjectIdentifier(panel)] = nil
            update(panel, with: content(reference))
            panel.alphaValue = 0
            guard let frame = requestedFrames[ObjectIdentifier(panel)],
                  let contentView = panel.contentView,
                  let view = contentView.subviews.first(where: { $0 is SquirrelView }) else {
                fail("\(placementCase.name) did not show its panel")
            }
            frames.append([
                "frame": [frame.minX, frame.minY, frame.width, frame.height],
                "view": [view.frame.width, view.frame.height],
                "rotation": contentView.boundsRotation,
            ])
        }
        panel.orderOut(nil)
        results[placementCase.name] = frames
        print("placements/\(placementCase.name)")
    }
    do {
        let data = try JSONSerialization.data(withJSONObject: ["screen": placements.screen, "cases": results], options: [.prettyPrinted, .sortedKeys])
        try (data + Data("\n".utf8)).write(to: output)
    } catch {
        fail("cannot write \(output.path): \(error)")
    }
    print("Recorded placements; \(results.count) cases in \(output.lastPathComponent)")
}
