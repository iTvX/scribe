/// The one-click conversion to scribe.custom.yaml as Scribe Settings shows
/// it: the entries in groups, each with a short value instead of YAML.
public struct ConversionOffer: Equatable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case general, appearance, apps, themes

        public var title: String {
            switch self {
            case .general: "通用"
            case .appearance: "外观"
            case .apps: "应用"
            case .themes: "主题"
            }
        }

        /// The group of a patch key.
        public init(key: String) {
            if key.hasPrefix("appearance/") {
                self = .appearance
            } else if key.hasPrefix("app_options/") {
                self = .apps
            } else if key.hasPrefix("themes/") {
                self = .themes
            } else {
                self = .general
            }
        }
    }

    public struct Row: Equatable, Sendable, Identifiable {
        /// The Scribe path, which is also the patch key.
        public var path: String
        public var value: String
        public var note: String?

        public var id: String { path }
    }

    public struct Section: Equatable, Sendable, Identifiable {
        public var group: Group
        public var rows: [Row]

        public var id: Group { group }
    }

    public var conversion: ScribeConversion
    /// Non-empty groups in group order; rows keep the converter's order.
    public var sections: [Section]
    /// The Squirrel paths that keep deciding a setting.
    public var unconverted: [String]

    /// `themes` names the themes that `appearance/theme` may refer to besides
    /// the ones the conversion creates.
    public init(conversion: ScribeConversion, themes: [ThemeInfo] = []) {
        self.conversion = conversion
        unconverted = conversion.unconverted.map(\.squirrelPath)
        var themeNames: [String: String] = [:]
        for theme in themes {
            themeNames[theme.id] = theme.name
        }
        for entry in conversion.entries where Group(key: entry.key) == .themes {
            themeNames[String(entry.key.dropFirst("themes/".count))] = entry.value.string(at: "name")
        }
        let renamed = Dictionary(conversion.themeIDs.filter { $0.key != $0.value }.map { ($0.value, $0.key) },
                                 uniquingKeysWith: { first, _ in first })
        sections = Group.allCases.compactMap { group in
            let rows = conversion.entries.filter { Group(key: $0.key) == group }.map { entry in
                Self.row(entry, group: group, themeNames: themeNames, renamed: renamed)
            }
            return rows.isEmpty ? nil : Section(group: group, rows: rows)
        }
    }

    /// The number of entries in a group.
    public func count(_ group: Group) -> Int {
        sections.first { $0.group == group }?.rows.count ?? 0
    }

    /// Why the conversion cannot run now, or nil when it can.
    public static func unavailableReason(conversion: ScribeConversion?, hasEdits: Bool, readOnlyReason: String?) -> String? {
        guard let conversion, !conversion.isEmpty else { return "没有要转换的设置" }
        if let readOnlyReason {
            return readOnlyReason
        }
        return hasEdits ? "先保存或还原未保存的修改" : nil
    }

    private static func row(_ entry: ScribeConversion.Entry, group: Group, themeNames: [String: String],
                            renamed: [String: String]) -> Row {
        switch group {
        case .apps:
            let options = optionSummary(entry.value)
            return Row(path: entry.key, value: options.isEmpty ? "不再使用中书默认给这个应用的设置" : options)
        case .themes:
            let id = String(entry.key.dropFirst("themes/".count))
            let colours = ["light", "dark"].reduce(0) { $0 + (entry.value.mapKeys(at: $1)?.count ?? 0) }
            return Row(path: entry.key, value: "\(themeNames[id] ?? id) · \(colours) 种颜色",
                       note: renamed[id].map { "鼠须管里叫 \($0)" })
        case .appearance where entry.key == "appearance/theme" || entry.key == "appearance/dark_theme":
            guard case .scalar(let id) = entry.value else { return Row(path: entry.key, value: summary(entry.value)) }
            let name = themeNames[id]
            return Row(path: entry.key, value: name.map { $0 == id ? id : "\($0)（\(id)）" } ?? id)
        default:
            return Row(path: entry.key, value: summary(entry.value))
        }
    }

    /// "ascii_mode 开、inline 关" for an app's options.
    private static func optionSummary(_ options: ConfigNode) -> String {
        guard case .map(let map) = options else { return summary(options) }
        return map.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { key in
            switch map[key] {
            case .scalar(let value)?:
                switch LibrimeScalar.bool(value) {
                case true?: "\(key) 开"
                case false?: "\(key) 关"
                case nil: "\(key) \(value)"
                }
            default:
                key
            }
        }.joined(separator: "、")
    }

    private static func summary(_ value: ConfigNode) -> String {
        switch value {
        case .null: "（空）"
        case .scalar(let text): text
        case .list(let items): "\(items.count) 项"
        case .map(let map): "\(map.count) 项设置"
        }
    }
}
