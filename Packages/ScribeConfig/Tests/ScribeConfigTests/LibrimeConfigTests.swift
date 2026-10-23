import Foundation
import RimeKit
import ScribeConfig
import Testing

/// Tests that read configs through librime. Each test that starts the engine
/// stops it again before returning, with no suspension in between, so tests
/// in other suites that use LibrimeEngine.shared cannot interleave with it.
@MainActor
@Suite("librime configs", .serialized)
struct LibrimeConfigTests {
    let engine = LibrimeEngine.shared

    static let trickyYAML = """
        scalars:
          true_cap: True
          yes: yes
          px: 16px
          hex: 0x10
          hex_upper: 0x1F
          hex_max: 0xFFFFFFFF
          hex_bad: 0x1G
          upper_x: 0X10
          spaced: " 8"
          inf: inf
          nan: nan
          frac: 1.5
          negative: -2
          huge: 99999999999999999999
          tiny: 1e-400
          overflow: 1e400
          empty: ""
          blank: " "
          null_value: null
          tilde: ~
          quoted_true: "TRUE"
          unicode: "%c\\u2005%@"
        keys:
          B: upper
          a: lower
          "": empty key
          "@": at
          "e\\u0301": decomposed
          _: underscore
        lists:
          nested: [[1, 2], [3, [4, 5]], {k: v}]
          empty: []
          with_null: [~, x]
          strings: [a, b, c]
        """

    /// Paths that exercise librime's path syntax beyond the plain leaf paths.
    static let extraPaths = [
        "", "/", "//", "/scalars/px", "//scalars/px", "scalars//px", "scalars/px/", "keys/", "keys//",
        "lists/strings/@0", "lists/strings/@last", "lists/strings/@3", "lists/strings/@next",
        "lists/strings/@before 1", "lists/strings/@before last", "lists/strings/@after 0", "lists/strings/@after last",
        "lists/strings/@after1", "lists/strings/@abc", "lists/strings/@lastly", "lists/strings/@1x",
        "lists/strings/@4294967297", "lists/strings/@before -1", "lists/strings/0",
        "lists/empty/@0", "lists/empty/@last", "lists/nested/@last/k", "lists/nested/@1/@1/@last",
        "lists/with_null/@0", "lists/with_null/@0/x", "scalars/null_value/x", "keys/@", "keys/@-1", "missing/@0",
        "scalars/@0",
    ]

    @Test func configNodeReadsLikeLibrime() throws {
        let checked = try #require(engine.withConfig(.yaml(Self.trickyYAML)) { reader -> Int in
            let snapshot = ConfigNode(snapshotOf: reader)
            let paths = Self.leafAndBranchPaths(of: snapshot) + Self.extraPaths
            for path in paths {
                #expect(snapshot.string(at: path) == reader.string(at: path), "string at \(path)")
                #expect(snapshot.bool(at: path) == reader.bool(at: path), "bool at \(path)")
                #expect(snapshot.int(at: path) == reader.int(at: path), "int at \(path)")
                let (mine, theirs) = (snapshot.double(at: path), reader.double(at: path))
                #expect(mine == theirs || (mine?.isNaN == true && theirs?.isNaN == true), "double at \(path)")
                #expect(snapshot.mapKeys(at: path) == reader.mapKeys(at: path), "mapKeys at \(path)")
                #expect(snapshot.listCount(at: path) == reader.listCount(at: path), "listCount at \(path)")
            }
            return paths.count
        })
        #expect(checked > 60)
    }

    @Test func snapshotOfTrickyValues() throws {
        let snapshot = try #require(engine.withConfig(.yaml(Self.trickyYAML)) { ConfigNode(snapshotOf: $0) })
        #expect(snapshot.mapKeys(at: "keys") == ["", "@", "B", "_", "a", "e\u{301}"])
        #expect(snapshot.string(at: "keys/e\u{301}") == "decomposed")
        #expect(snapshot.mapKeys(at: "scalars")?.contains("null_value") == true)
        #expect(snapshot.int(at: "scalars/hex_max") == -1)
        #expect(snapshot.int(at: "scalars/hex_bad") == 0)
        #expect(snapshot.double(at: "scalars/px") == 16)
        #expect(snapshot.string(at: "scalars/unicode") == "%c\u{2005}%@")
        #expect(snapshot.listCount(at: "lists/with_null") == 2)
        #expect(snapshot.string(at: "keys/") == "empty key")
    }

    @Test func presetsInSharedSupport() throws {
        let yaml = try ConfigFixtures.text(ConfigFixtures.squirrelYAML)
        let opened: Void? = try engine.withConfig(.yaml(yaml)) { squirrel in
            let ids = PresetColorScheme.ids(in: squirrel)
            #expect(ids == [
                "apathy", "aqua", "azure", "clean_white", "dark_temple", "dust", "google", "ink", "lost_temple",
                "luna", "mojave_dark", "native", "psionics", "purity_of_essence", "purity_of_form", "retro_green",
                "retro_orange", "solarized_dark", "solarized_light", "solarized_rock", "starcraft",
            ])
            for id in ids {
                try ConfigFixtures.expectSnapshot(snapshot(Self.lightTheme(id, in: squirrel)), named: "preset-\(id)")
                #expect(PresetColorScheme(id: id, source: squirrel)?.id == id)
            }

            let cleanWhite = Self.lightTheme("clean_white", in: squirrel)
            #expect(cleanWhite.candidateFormat.template == "[label] [candidate] [comment]")
            #expect(cleanWhite.layout == .linear)
            #expect(cleanWhite.labelFont.pointSize == 12)
            #expect(cleanWhite.colors.hilitedCandidateLabel == .rgba(RGBAColor(red: 0x15, green: 0x89, blue: 0xC9, alpha: 0xA0)))

            let solarized = Self.lightTheme("solarized_light", in: squirrel)
            #expect(solarized.colorSpace == .displayP3)
            #expect(solarized.colors.background == .rgba(RGBAColor(red: 0xFB, green: 0xF6, blue: 0xE5, alpha: 0xF0, colorSpace: .displayP3)))
            #expect(PresetColorScheme(id: "solarized_light", source: squirrel)?.colorSpace == .displayP3)

            let starcraft = Self.lightTheme("starcraft", in: squirrel)
            #expect(starcraft.borderWidth == 2)
            #expect(starcraft.borderHeight == 2)
            #expect(starcraft.cornerRadius == 8)
            #expect(starcraft.hilitedCornerRadius == 8)
            #expect(starcraft.colors.border == .rgba(RGBAColor(red: 0xA0, green: 0x10, blue: 0x10)))
            #expect(starcraft.colors.hilitedCandidateBackground == .rgba(RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)))
            // squirrel.yaml's own style: border -2, corner radius 7.
            let native = Self.lightTheme("native", in: squirrel)
            #expect(native.borderWidth == -2)
            #expect(native.cornerRadius == 7)
            #expect(native.isNative)
        }
        #expect(opened != nil)
    }

    @Test func rimeIceSettings() throws {
        let yaml = try ConfigFixtures.text(ConfigFixtures.rimeIceYAML)
        let settings = try #require(engine.withConfig(.yaml(yaml)) { ScribeSettings(squirrel: $0) })
        #expect(settings.configVersion == "2026-01-31")
        #expect(settings.appOptions == AppOptions())
        #expect(settings.appearance.light.colorSchemeID == "purity_of_form_custom")
        #expect(settings.appearance.dark?.colorSchemeID == "purity_of_form_custom")
        // font_face "" gives no faces; the label font keeps its own face.
        #expect(settings.appearance.light.candidateFont == ThemeFont(faces: [], pointSize: 18))
        #expect(settings.appearance.light.labelFont == ThemeFont(faces: [FontFace(name: "Helvetica")], pointSize: 12))
        try ConfigFixtures.expectSnapshot(snapshot(settings), named: "rime-ice-settings")
    }

    @Test func deployPatchesTheUserCopy() throws {
        let fileManager = FileManager.default
        let (root, shared, user) = try Self.makeDataDirectories()
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.copyItem(at: ConfigFixtures.squirrelYAML, to: shared.appending(path: "squirrel.yaml"))
        try fileManager.copyItem(at: ConfigFixtures.rimeIceYAML, to: user.appending(path: "squirrel.yaml"))
        try fileManager.copyItem(at: ConfigFixtures.maxSampleCustomYAML, to: user.appending(path: "squirrel.custom.yaml"))

        engine.start(Self.configuration(shared: shared, user: user))
        defer { engine.stop() }
        #expect(engine.deployConfigFile("squirrel.yaml", versionKey: "config_version"))
        #expect(!fileManager.fileExists(atPath: user.appending(path: "trash").path(percentEncoded: false)))
        #expect(fileManager.fileExists(atPath: user.appending(path: "squirrel.yaml").path(percentEncoded: false)))

        let deployed = try #require(engine.withConfig(.deployed("squirrel")) { squirrel in
            #expect(squirrel.string(at: "config_version") == "2026-01-31")
            // rime-ice's own 22 presets (its custom one and copies of the 21
            // built-in ones), with the two skins appended.
            let presets = squirrel.mapKeys(at: "preset_color_schemes") ?? []
            #expect(presets.count == 24)
            #expect(Set(presets).isSuperset(of: ["purity_of_form_custom", "aqua", "wechat_dark", "wechat_light"]))
            #expect(squirrel.mapKeys(at: "app_options") == ["com.googlecode.iterm2"])
            return ScribeSettings(squirrel: squirrel)
        })
        #expect(ScribeSettings.load(from: engine) == deployed)

        let expected = ScribeSettings(squirrel: maxSample).appearance
        #expect(deployed.appearance == expected)
        let light = deployed.appearance.light
        let dark = try #require(deployed.appearance.dark)
        for theme in [light, dark] {
            #expect(theme.colors.hilitedCandidateBackground == .rgba(RGBAColor(red: 0x00, green: 0xB1, blue: 0x75)))
            #expect(theme.candidateFormat.template == "[label]\u{2005}[candidate] [comment]\u{2005}")
            #expect(theme.inlinePreedit)
        }
        #expect(light.colorSchemeID == "wechat_light")
        #expect(dark.colorSchemeID == "wechat_dark")
        try ConfigFixtures.expectSnapshot(snapshot(light), named: "max-sample-light")
        try ConfigFixtures.expectSnapshot(snapshot(dark), named: "max-sample-dark")

        #expect(deployed.appOptions.options(for: "com.googlecode.iterm2") == ["ascii_mode": false])
        #expect(deployed.appOptions.options(for: "com.apple.Terminal") == [:])
        #expect(deployed.appOptions.byBundleID.count == 1)

        // A missing schema opens as an empty config, so the themes are squirrel.yaml's.
        #expect(Appearance.load(from: engine, schemaID: "missing_schema") == deployed.appearance)
        #expect(Appearance.load(from: engine, schemaID: ".default") == deployed.appearance)
        let missing = engine.withConfig(.deployed("missing_config")) { $0.mapKeys(at: "") }
        #expect(missing == .some(nil))
    }

    @Test func schemaStyleThroughLibrime() throws {
        let fileManager = FileManager.default
        let (root, shared, user) = try Self.makeDataDirectories()
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.copyItem(at: ConfigFixtures.squirrelYAML, to: shared.appending(path: "squirrel.yaml"))
        let build = user.appending(path: "build", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: build, withIntermediateDirectories: true)
        try """
            schema:
              schema_id: styled
            style:
              color_scheme: starcraft
              font_point: 20
            """.write(to: build.appending(path: "styled.schema.yaml"), atomically: true, encoding: .utf8)
        try """
            schema:
              schema_id: plain
            preset_color_schemes:
              native:
                back_color: 0x000000
            """.write(to: build.appending(path: "plain.schema.yaml"), atomically: true, encoding: .utf8)

        engine.start(Self.configuration(shared: shared, user: user))
        defer { engine.stop() }
        #expect(engine.deployConfigFile("squirrel.yaml", versionKey: "config_version"))

        let base = try #require(Appearance.load(from: engine, schemaID: ""))
        #expect(base.light.isNative)
        #expect(Appearance.load(from: engine, schemaID: "plain") == base)
        let styled = try #require(Appearance.load(from: engine, schemaID: "styled"))
        #expect(styled.light.colorSchemeID == "starcraft")
        #expect(styled.light.candidateFont.pointSize == 20)
        #expect(styled.light.candidateFont.faces == [FontFace(name: "Avenir")])
        #expect(styled.light.cornerRadius == 8)
    }

    @Test(arguments: [true, false])
    func scribeCompatibilityDeploy(patched: Bool) throws {
        let fileManager = FileManager.default
        let (root, shared, user) = try Self.makeDataDirectories()
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.copyItem(at: ConfigFixtures.scribeYAML, to: shared.appending(path: "scribe.yaml"))
        if patched {
            try "patch: {compatibility/report_as_squirrel: true}\n"
                .write(to: user.appending(path: "scribe.custom.yaml"), atomically: true, encoding: .utf8)
        }

        engine.start(Self.configuration(shared: shared, user: user))
        defer { engine.stop() }
        #expect(engine.deployConfigFile("scribe.yaml", versionKey: "config_version"))
        let compatibility = try #require(ScribeCompatibility.load(from: engine))
        #expect(compatibility.reportsAsSquirrel == patched)
        #expect(compatibility.distributionCodeName == (patched ? "Squirrel" : "Scribe"))
        #expect(compatibility.distributionName == (patched ? "鼠鬚管" : "Scribe"))
        #expect(engine.withConfig(.deployed("scribe")) { $0.string(at: "config_version") } == "0.1")
    }

    @Test func scribeFormatDeploys() throws {
        let fileManager = FileManager.default
        let (root, shared, user) = try Self.makeDataDirectories()
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.copyItem(at: ConfigFixtures.squirrelYAML, to: shared.appending(path: "squirrel.yaml"))
        try fileManager.copyItem(at: ConfigFixtures.scribeYAML, to: shared.appending(path: "scribe.yaml"))
        try fileManager.copyItem(
            at: ConfigFixtures.directory.appending(path: "max-sample/scribe.custom.yaml"),
            to: user.appending(path: "scribe.custom.yaml")
        )

        engine.start(Self.configuration(shared: shared, user: user))
        defer { engine.stop() }
        #expect(engine.deployConfigFile("squirrel.yaml", versionKey: "config_version"))
        #expect(engine.deployConfigFile("scribe.yaml", versionKey: "config_version"))

        let settings = try #require(ScribeSettings.load(from: engine))
        let expected = ScribeSettings(squirrel: maxSample).appearance
        #expect(settings.appearance.light.colorSchemeID == "wechat")
        #expect(settings.appearance.dark?.colorSchemeID == "wechat:dark")
        #expect(withoutID(settings.appearance.light) == withoutID(expected.light))
        #expect(try withoutID(#require(settings.appearance.dark)) == withoutID(#require(expected.dark)))
        #expect(Appearance.load(from: engine, schemaID: "") == settings.appearance)

        // squirrel.yaml's per-app table, with iTerm2's replaced by scribe.yaml's.
        #expect(settings.appOptions.options(for: "com.googlecode.iterm2") == ["ascii_mode": false])
        #expect(settings.appOptions.options(for: "com.apple.Terminal") == ["ascii_mode": true, "no_inline": true])
        #expect(ScribeCompatibility.load(from: engine) == ScribeCompatibility(reportsAsSquirrel: false))

        let themes = try #require(engine.withConfig(.deployed("squirrel")) { squirrel in
            engine.withConfig(.deployed("scribe")) { availableThemes(scribe: $0, squirrel: squirrel) }
        } ?? nil)
        #expect(themes.count == 22)
        #expect(themes.prefix(2).map(\.id) == ["native", "wechat"])
        #expect(themes[1].hasDark)
    }

    @Test func unquotedColorIsNull() throws {
        let yaml = """
            themes:
              wechat:
                light:
                  background: #FFFFFF
                  highlight_background: "#00B175"
            """
        let diagnostics = try #require(engine.withConfig(.yaml(yaml)) { scribe in
            #expect(scribe.mapKeys(at: "themes/wechat/light") == ["background", "highlight_background"])
            #expect(scribe.string(at: "themes/wechat/light/background") == nil)
            return ConfigDiagnostics.check(scribe: scribe, squirrel: ConfigNode.null)
        })
        #expect(diagnostics == [ConfigDiagnostic(path: "themes/wechat/light/background", problem: .missingColor)])
    }

    @Test func noConfigWhileStopped() {
        #expect(!engine.isRunning)
        #expect(engine.withConfig(.deployed("squirrel")) { _ in true } == nil)
        #expect(ScribeSettings.load(from: engine) == nil)
    }

    /// Empty shared and user data directories in a new temporary directory.
    private static func makeDataDirectories() throws -> (root: URL, shared: URL, user: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "scribe-config-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let shared = root.appending(path: "shared", directoryHint: .isDirectory)
        let user = root.appending(path: "user", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        return (root, shared, user)
    }

    private static func configuration(shared: URL, user: URL) -> RimeConfiguration {
        RimeConfiguration(
            sharedDataDirectory: shared,
            userDataDirectory: user,
            minimumLogLevel: 2,
            appName: "rime.scribe-config-tests"
        )
    }

    /// The light theme of squirrel.yaml with `style/color_scheme` set to `id`.
    private static func lightTheme(_ id: String, in squirrel: some ConfigSource) -> Theme {
        let override = ConfigNode.map(["style": ["color_scheme": .scalar(id)]])
        return Theme(source: FallbackConfigSource(primary: override, fallback: squirrel), colorSchemeKey: "style/color_scheme")
    }

    /// Every path in `node`, maps and lists included.
    private static func leafAndBranchPaths(of node: ConfigNode, at path: String = "") -> [String] {
        func child(_ key: String) -> String { path.isEmpty ? key : "\(path)/\(key)" }
        var paths = [path]
        switch node {
        case .map(let map):
            for (key, value) in map {
                paths += leafAndBranchPaths(of: value, at: child(key))
            }
        case .list(let list):
            for (index, value) in list.enumerated() {
                paths += leafAndBranchPaths(of: value, at: child("@\(index)"))
            }
        case .scalar, .null:
            break
        }
        return paths
    }
}
