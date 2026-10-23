import AppKit
import ScribeConfig
import ScribeCore
@testable import ScribeUI

/// The snapshot cases in `Tests/Fixtures/snapshots/cases.json`, which
/// Tools/squirrel-oracle renders with Squirrel's own code too.
struct SnapshotCases: Decodable {
    struct Case: Decodable {
        var name: String
        /// A file in configs/ to start from instead of `style` and
        /// `schemes`.
        var config: String?
        var scheme: String?
        var style: [String: String]?
        var colors: [String: String]?
        var content: ContentReference
        var dark: Bool?
    }

    enum ContentReference: Decodable {
        case named(String)
        case inline(Content)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let name = try? container.decode(String.self) {
                self = .named(name)
            } else {
                self = .inline(try container.decode(Content.self))
            }
        }
    }

    struct Content: Decodable {
        struct Candidate: Decodable {
            var text: String
            var comment: String?
        }

        struct Preedit: Decodable {
            var text: String
            var selection: [Int]
            var caret: Int
        }

        var candidates: [Candidate]
        var labels: [String]?
        var highlighted: Int?
        var page: Int?
        var lastPage: Bool?
        var preedit: Preedit?
        var accent: [Int]?
        var warning: [Int]?
        var status: String?
    }

    var style: [String: String]
    var schemes: [String: [String: String]]
    var contents: [String: Content]
    var suites: [String: [Case]]

    static let shared: SnapshotCases = {
        let url = Snapshot.repositoryRoot.appending(path: "Tests/Fixtures/snapshots/cases.json")
        do {
            return try JSONDecoder().decode(SnapshotCases.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Cannot read \(url.path): \(error)")
        }
    }()

    /// The theme squirrel.yaml would give: the shared style with `style`
    /// on top, and `scheme` with `colors` on top as the colour scheme.
    func theme(scheme: String = "native", style: [String: String] = [:], colors: [String: String] = [:]) -> Theme {
        var styleMap = self.style.merging(style) { $1 }
        styleMap["color_scheme"] = scheme
        let schemeMap = (schemes[scheme] ?? [:]).merging(colors) { $1 }
        let config: ConfigNode = .map([
            "style": .map(styleMap.mapValues(ConfigNode.scalar)),
            "preset_color_schemes": .map([scheme: .map(schemeMap.mapValues(ConfigNode.scalar))]),
        ])
        return Theme(source: config, colorSchemeKey: "style/color_scheme")
    }

    func theme(for testCase: Case) -> Theme {
        guard let config = testCase.config else {
            return theme(scheme: testCase.scheme ?? "native", style: testCase.style ?? [:], colors: testCase.colors ?? [:])
        }
        var values = (try? SnapshotConfigs.load(config)) ?? [:]
        for (key, value) in testCase.style ?? [:] {
            values["style/\(key)"] = value
        }
        return Appearance(squirrel: SnapshotConfigs.node(from: values)).theme(isDark: testCase.dark ?? false)
    }

    func content(for testCase: Case) -> PanelContent {
        let content = switch testCase.content {
        case let .named(name): contents[name]!
        case let .inline(content): content
        }
        var snapshot: CandidateSnapshot?
        if !content.candidates.isEmpty || content.preedit != nil {
            let labels = content.labels ?? content.candidates.indices.map { "\($0 + 1)" }
            snapshot = CandidateSnapshot(
                entries: content.candidates.enumerated().map { index, candidate in
                    CandidateSnapshot.Entry(label: labels[index], text: candidate.text, comment: candidate.comment)
                },
                highlightedIndex: content.highlighted ?? 0,
                pageNumber: content.page ?? 0,
                isLastPage: content.lastPage ?? true,
                preedit: content.preedit.map { Preedit(text: $0.text, selectedRange: $0.selection[0]..<$0.selection[1], caret: $0.caret) }
            )
        }
        return PanelContent(
            snapshot,
            accentCommentIndices: Set(content.accent ?? []),
            warningCommentIndices: Set(content.warning ?? []),
            statusMessage: content.status
        )
    }

    /// The cases of `suite`, ready to render.
    func cases(in suite: String) -> [SnapshotCase] {
        (suites[suite] ?? []).map { testCase in
            SnapshotCase(suite: suite, name: testCase.name, theme: theme(for: testCase), content: content(for: testCase), dark: testCase.dark ?? false)
        }
    }
}
