import Foundation

/// The snapshot cases in Tests/Fixtures/snapshots/cases.json, as ScribeUI's
/// tests read them.
struct Cases: Decodable {
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

    /// The config as librime paths: the shared style with the case's style
    /// on top, and the case's scheme with its colours on top; or the file
    /// the case names, with its style on top.
    func config(for testCase: Case, configs: URL) throws -> [String: String] {
        if let name = testCase.config {
            var config = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: configs.appending(path: "\(name).json")))
            for (key, value) in testCase.style ?? [:] {
                config["style/\(key)"] = value
            }
            return config
        }
        let scheme = testCase.scheme ?? "native"
        var config: [String: String] = [:]
        for (key, value) in style.merging(testCase.style ?? [:], uniquingKeysWith: { $1 }) {
            config["style/\(key)"] = value
        }
        config["style/color_scheme"] = scheme
        for (key, value) in (schemes[scheme] ?? [:]).merging(testCase.colors ?? [:], uniquingKeysWith: { $1 }) {
            config["preset_color_schemes/\(scheme)/\(key)"] = value
        }
        return config
    }

    func content(for testCase: Case) -> Content {
        switch testCase.content {
        case let .named(name): contents[name]!
        case let .inline(content): content
        }
    }
}
