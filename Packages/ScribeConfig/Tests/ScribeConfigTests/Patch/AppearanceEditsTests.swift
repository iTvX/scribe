import Foundation
import ScribeConfig
import Testing

struct AppearanceEditsTests {
    static let settings = AppearanceSettings(
        squirrel: ["style": ["font_point": "16.0", "color_scheme": "native", "candidate_list_layout": "stacked"]],
        scribe: ["appearance": ["layout": "linear", "corner_radius": "4"]],
        customKeys: ["appearance/layout", "appearance"]
    )

    @Test func writesNumbersMinimally() {
        #expect(AppearanceEdits.number(16) == "16")
        #expect(AppearanceEdits.number(12.0) == "12")
        #expect(AppearanceEdits.number(0.85) == "0.85")
        #expect(AppearanceEdits.number(1.5) == "1.5")
        #expect(AppearanceEdits.number(-2) == "-2")
        #expect(AppearanceEdits.number(-0.0) == "0")
        #expect(AppearanceEdits.flag(true) == "true")
        #expect(AppearanceEdits.flag(false) == "false")
    }

    @Test func setsAndDropsValues() {
        var edits = AppearanceEdits()
        edits.set("appearance/font/size", to: AppearanceEdits.number(18), loaded: Self.settings)
        edits.set("appearance/alpha", to: AppearanceEdits.number(0.85), loaded: Self.settings)
        #expect(edits.changes == [.set("appearance/alpha", "0.85"), .set("appearance/font/size", "18")])

        // Back to what was loaded: Squirrel's 16.0 reads as the same number.
        edits.set("appearance/font/size", to: AppearanceEdits.number(16), loaded: Self.settings)
        #expect(edits.changes == [.set("appearance/alpha", "0.85")])
        edits.discard()
        #expect(edits.isEmpty)
        #expect(edits.changes.isEmpty)
    }

    @Test func resetRemovesOwnEntriesOnly() {
        var edits = AppearanceEdits()
        edits.reset("appearance/layout", loaded: Self.settings)
        #expect(edits.changes == [.remove("appearance/layout")])
        #expect(edits.pending == ["appearance/layout": nil])
        #expect(Self.settings.appearance(with: edits.pending).light.layout == .stacked)
        #expect(Self.settings.appearance().light.layout == .linear)

        // Setting the loaded value again keeps the entry.
        edits.set("appearance/layout", to: "linear", loaded: Self.settings)
        #expect(edits.isEmpty)

        // Inside the `appearance` entry, or not in the file: nothing to remove.
        edits.set("appearance/corner_radius", to: AppearanceEdits.number(8), loaded: Self.settings)
        edits.reset("appearance/corner_radius", loaded: Self.settings)
        edits.reset("appearance/font/size", loaded: Self.settings)
        #expect(edits.isEmpty)
    }

    @Test func pathsAreEditedInPlace() {
        let pending: [String: ConfigNode?] = ["appearance/font/size": "20", "appearance/corner_radius": nil, "appearance/padding/horizontal": "3"]
        #expect(Self.settings.scribe(with: pending) == ["appearance": [
            "layout": "linear",
            "font": ["size": "20"],
            "padding": ["horizontal": "3"],
        ]])
        #expect(Self.settings.effectiveValue(at: "appearance/font/size", with: pending) == "20")
        #expect(Self.settings.loadedValue(at: "appearance/font/size") == "16.0")
        #expect(Self.settings.loadedValue(at: "appearance/theme") == "native")
        #expect(Self.settings.loadedValue(at: "appearance/translucency") == nil)
    }

    @Test func tellsWhereValuesComeFrom() {
        #expect(Self.settings.provenance(of: "appearance/layout") == .ownEntry)
        #expect(Self.settings.provenance(of: "appearance/corner_radius") == .insideEntry("appearance"))
        #expect(AppearanceSettings(squirrel: [:], scribe: [:]).provenance(of: "appearance/layout") == .squirrelOrDefault)
    }
}
