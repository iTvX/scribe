import Foundation
import RimeKit
import ScribeConfig
@testable import ScribeUI
import Testing

/// The flattened configs in Tests/Fixtures/snapshots/configs match the YAML
/// they come from, so the Squirrel references and Scribe's renders keep
/// starting from what librime reads.
@MainActor
@Suite(.serialized) struct SnapshotConfigTests {
    @Test(arguments: SnapshotConfigs.names)
    func configMatchesItsYAML(_ name: String) throws {
        let generated = SnapshotConfigs.flatten(try SnapshotConfigs.generate(name))
        if Snapshot.isRecording {
            try SnapshotConfigs.write(generated, name: name)
            Issue.record("Recorded \(SnapshotConfigs.url(name).path); run again without SCRIBE_RECORD_SNAPSHOTS")
            return
        }
        let committed = try SnapshotConfigs.load(name)
        #expect(committed == generated, "Record \(SnapshotConfigs.url(name).path) again with SCRIBE_RECORD_SNAPSHOTS=1")
    }

    /// Squirrel's shim in the oracle reads numbers with Double(_:); librime
    /// accepts more (such as "16px"), so the configs must not rely on that.
    @Test(arguments: SnapshotConfigs.names)
    func numbersReadTheSameInTheOracle(_ name: String) throws {
        let config = try SnapshotConfigs.load(name)
        let node = SnapshotConfigs.node(from: config)
        for (path, value) in config where path.hasPrefix("style/") || path.hasPrefix("preset_color_schemes/") {
            if let librime = node.double(at: path), !value.hasPrefix("0x") {
                #expect(Double(value) == librime, "\(path) = \(value)")
            }
        }
    }

    /// The deployed sample gives the themes ScribeConfig's own tests recorded
    /// for it.
    @Test(arguments: [false, true])
    func maxSampleMatchesScribeConfigsSnapshot(dark: Bool) throws {
        let appearance = Appearance(squirrel: SnapshotConfigs.node(from: try SnapshotConfigs.load("max-sample")))
        let theme = appearance.theme(isDark: dark)
        let url = Snapshot.repositoryRoot.appending(path: "Tests/Fixtures/config/snapshots/max-sample-\(dark ? "dark" : "light").txt")
        let recorded = try String(contentsOf: url, encoding: .utf8)
        func line(_ key: String) -> String? {
            recorded.split(separator: "\n").first { $0.hasPrefix("\(key) = ") }.map { String($0.dropFirst(key.count + 3)) }
        }
        func describe(_ color: ThemeColor?) -> String {
            switch color {
            case nil: "nil"
            case let .rgba(rgba)?: rgba.hex + (rgba.colorSpace == .displayP3 ? " displayP3" : "")
            case let .system(system)?: system.rawValue
            case let .blend(foreground, background)?: "blend(\(describe(foreground)), \(describe(background)))"
            }
        }
        let colors = theme.colors
        let fields: [(String, ThemeColor?)] = [
            ("background", colors.background), ("hilitedCandidateBackground", colors.hilitedCandidateBackground),
            ("candidateText", colors.candidateText), ("hilitedCandidateText", colors.hilitedCandidateText),
            ("label", colors.label), ("hilitedCandidateLabel", colors.hilitedCandidateLabel),
            ("commentText", colors.commentText), ("hilitedCommentText", colors.hilitedCommentText),
            ("text", colors.text), ("border", colors.border),
        ]
        for (key, color) in fields {
            #expect(line("colors.\(key)") == describe(color), "colors.\(key)")
        }
        #expect(line("colorSchemeID") == "\"wechat_\(dark ? "dark" : "light")\"")
        #expect(line("layout") == theme.layout.rawValue)
        #expect(line("borderWidth") == "\(theme.borderWidth)")
        #expect(line("cornerRadius") == "\(theme.cornerRadius)")
        #expect(line("labelFont.pointSize") == theme.labelFont.pointSize.map { "\($0)" })
        #expect(line("inlinePreedit") == "\(theme.inlinePreedit)")
    }
}
