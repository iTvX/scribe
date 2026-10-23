/// Which Squirrel key (squirrel.yaml) each Scribe key (scribe.yaml) stands for.
///
/// Paths are librime paths. In `entries`, a segment "{app}", "{option}" or
/// "{id}" stands for any key; "{id}" is a theme ID, which has no ":". A Scribe
/// theme is served to Squirrel as two presets: "{id}" from its light palette
/// and "{id}:dark" from its dark one. The theme's own `style`, `name`,
/// `author` and `color_space` apply to both; a palette's `style` beats the
/// theme's.
public enum ScribeKeyMap {
    public enum ValueKind: Equatable, Sendable {
        case bool, int, double, string
        /// One of these config values.
        case enumeration([String])
        /// "#RRGGBB" or "#RRGGBBAA" in Scribe, "0xAABBGGRR" in Squirrel.
        case color
    }

    public struct Entry: Equatable, Sendable {
        public var scribePath: String
        public var squirrelPath: String
        public var kind: ValueKind

        public init(scribePath: String, squirrelPath: String, kind: ValueKind) {
            self.scribePath = scribePath
            self.squirrelPath = squirrelPath
            self.kind = kind
        }
    }

    /// A key under `appearance` (and, for scheme-level keys, under a theme's
    /// `style`) with its key under Squirrel's `style` (or a preset).
    struct StyleKey {
        var scribe: String
        var squirrel: String
        var kind: ValueKind
    }

    /// The keys a colour scheme may set as well as `style`.
    static let schemeStyleKeys: [StyleKey] = {
        var keys = [
            StyleKey(scribe: "layout", squirrel: "candidate_list_layout",
                     kind: .enumeration(CandidateListLayout.allCases.map(\.rawValue))),
            StyleKey(scribe: "orientation", squirrel: "text_orientation",
                     kind: .enumeration(TextOrientation.allCases.map(\.rawValue))),
            StyleKey(scribe: "inline_preedit", squirrel: "inline_preedit", kind: .bool),
            StyleKey(scribe: "inline_candidate", squirrel: "inline_candidate", kind: .bool),
            StyleKey(scribe: "translucency", squirrel: "translucency", kind: .bool),
            StyleKey(scribe: "mutual_exclusive", squirrel: "mutual_exclusive", kind: .bool),
            StyleKey(scribe: "show_paging", squirrel: "show_paging", kind: .bool),
            StyleKey(scribe: "candidate_format", squirrel: "candidate_format", kind: .string),
        ]
        for font in ["font", "label_font", "comment_font", "preedit_font"] {
            keys.append(StyleKey(scribe: "\(font)/face", squirrel: "\(font)_face", kind: .string))
            keys.append(StyleKey(scribe: "\(font)/size", squirrel: "\(font)_point", kind: .double))
        }
        keys += [
            StyleKey(scribe: "alpha", squirrel: "alpha", kind: .double),
            StyleKey(scribe: "corner_radius", squirrel: "corner_radius", kind: .double),
            StyleKey(scribe: "highlight_corner_radius", squirrel: "hilited_corner_radius", kind: .double),
            StyleKey(scribe: "padding/horizontal", squirrel: "border_width", kind: .double),
            StyleKey(scribe: "padding/vertical", squirrel: "border_height", kind: .double),
            StyleKey(scribe: "line_spacing", squirrel: "line_spacing", kind: .double),
            StyleKey(scribe: "preedit_spacing", squirrel: "spacing", kind: .double),
            StyleKey(scribe: "baseline_offset", squirrel: "base_offset", kind: .double),
            StyleKey(scribe: "shadow_size", squirrel: "shadow_size", kind: .double),
            StyleKey(scribe: "highlight_expansion", squirrel: "surrounding_extra_expansion", kind: .double),
        ]
        return keys
    }()

    /// The keys only `appearance` sets, apart from `theme` and `dark_theme`.
    static let globalStyleKeys = [
        StyleKey(scribe: "memorize_size", squirrel: "memorize_size", kind: .bool),
        StyleKey(scribe: "status_message", squirrel: "status_message_type",
                 kind: .enumeration(StatusMessageType.allCases.map(\.rawValue))),
    ]

    static let themeMetadataKeys = [
        StyleKey(scribe: "name", squirrel: "name", kind: .string),
        StyleKey(scribe: "author", squirrel: "author", kind: .string),
        StyleKey(scribe: "color_space", squirrel: "color_space", kind: .enumeration(["srgb", "display_p3"])),
    ]

    static let paletteColorKeys = [
        StyleKey(scribe: "background", squirrel: "back_color", kind: .color),
        StyleKey(scribe: "border", squirrel: "border_color", kind: .color),
        StyleKey(scribe: "preedit_background", squirrel: "preedit_back_color", kind: .color),
        StyleKey(scribe: "candidate_background", squirrel: "candidate_back_color", kind: .color),
        StyleKey(scribe: "preedit_highlight_background", squirrel: "hilited_back_color", kind: .color),
        StyleKey(scribe: "highlight_background", squirrel: "hilited_candidate_back_color", kind: .color),
        StyleKey(scribe: "preedit_text", squirrel: "text_color", kind: .color),
        StyleKey(scribe: "preedit_highlight_text", squirrel: "hilited_text_color", kind: .color),
        StyleKey(scribe: "candidate_text", squirrel: "candidate_text_color", kind: .color),
        StyleKey(scribe: "highlight_text", squirrel: "hilited_candidate_text_color", kind: .color),
        StyleKey(scribe: "label", squirrel: "label_color", kind: .color),
        StyleKey(scribe: "highlight_label", squirrel: "hilited_candidate_label_color", kind: .color),
        StyleKey(scribe: "comment", squirrel: "comment_text_color", kind: .color),
        StyleKey(scribe: "highlight_comment", squirrel: "hilited_comment_text_color", kind: .color),
        StyleKey(scribe: "accent", squirrel: "accent_text_color", kind: .color),
        StyleKey(scribe: "warning", squirrel: "warning_text_color", kind: .color),
    ]

    /// The global keys outside `appearance`.
    static let globalKeys = [
        StyleKey(scribe: "keyboard_layout", squirrel: "keyboard_layout", kind: .string),
        StyleKey(scribe: "chord_duration", squirrel: "chord_duration", kind: .double),
        StyleKey(scribe: "notifications", squirrel: "show_notifications_when",
                 kind: .enumeration(NotificationPolicy.allCases.map(\.rawValue))),
        StyleKey(scribe: "status_icon", squirrel: "status_icon/show", kind: .bool),
        StyleKey(scribe: "report_bundle_id", squirrel: "unsafe/report_bundleid", kind: .bool),
        StyleKey(scribe: "app_options/{app}/{option}", squirrel: "app_options/{app}/{option}", kind: .bool),
    ]

    /// Every key, one entry per Scribe path and per Squirrel path. The light
    /// palette's `style` and the dark preset's metadata are not entries: see
    /// `squirrelPath(forScribe:)` and `scribePath(forSquirrel:)`.
    public static let entries: [Entry] = {
        var entries = globalKeys.map { Entry(scribePath: $0.scribe, squirrelPath: $0.squirrel, kind: $0.kind) }
        entries.append(Entry(scribePath: "appearance/theme", squirrelPath: "style/color_scheme", kind: .string))
        entries.append(Entry(scribePath: "appearance/dark_theme", squirrelPath: "style/color_scheme_dark", kind: .string))
        for key in schemeStyleKeys + globalStyleKeys {
            entries.append(Entry(scribePath: "appearance/\(key.scribe)", squirrelPath: "style/\(key.squirrel)", kind: key.kind))
        }
        for key in themeMetadataKeys {
            entries.append(Entry(
                scribePath: "themes/{id}/\(key.scribe)",
                squirrelPath: "preset_color_schemes/{id}/\(key.squirrel)",
                kind: key.kind
            ))
        }
        for key in schemeStyleKeys {
            entries.append(Entry(
                scribePath: "themes/{id}/style/\(key.scribe)",
                squirrelPath: "preset_color_schemes/{id}/\(key.squirrel)",
                kind: key.kind
            ))
            entries.append(Entry(
                scribePath: "themes/{id}/dark/style/\(key.scribe)",
                squirrelPath: "preset_color_schemes/{id}:dark/\(key.squirrel)",
                kind: key.kind
            ))
        }
        for key in paletteColorKeys {
            entries.append(Entry(
                scribePath: "themes/{id}/light/\(key.scribe)",
                squirrelPath: "preset_color_schemes/{id}/\(key.squirrel)",
                kind: key.kind
            ))
            entries.append(Entry(
                scribePath: "themes/{id}/dark/\(key.scribe)",
                squirrelPath: "preset_color_schemes/{id}:dark/\(key.squirrel)",
                kind: key.kind
            ))
        }
        return entries
    }()

    /// The Squirrel path a Scribe path feeds, or nil when it has none. A light
    /// palette's `style` key feeds the light preset like the theme's `style`.
    public static func squirrelPath(forScribe path: String) -> String? {
        if let (entry, bindings) = match(path, \.scribePath) {
            return PathPattern(entry.squirrelPath).fill(bindings)
        }
        if let bindings = PathPattern("themes/{id}/light/style/{key}").match(path) {
            return squirrelPath(forScribe: "themes/\(bindings["id"]!)/style/\(bindings["key"]!)")
        }
        return nil
    }

    /// The Scribe path a Squirrel path is read from first, or nil when it has
    /// none. A dark preset's name, author and colour space are its theme's.
    public static func scribePath(forSquirrel path: String) -> String? {
        if let (entry, bindings) = match(path, \.squirrelPath) {
            return PathPattern(entry.scribePath).fill(bindings)
        }
        for key in themeMetadataKeys {
            if let bindings = PathPattern("preset_color_schemes/{id}:dark/\(key.squirrel)").match(path) {
                return "themes/\(bindings["id"]!)/\(key.scribe)"
            }
        }
        return nil
    }

    /// The entry whose Scribe path matches `path`.
    public static func entry(forScribe path: String) -> Entry? {
        match(path, \.scribePath)?.0
    }

    private static func match(_ path: String, _ side: KeyPath<Entry, String>) -> (Entry, [String: String])? {
        for entry in entries {
            if let bindings = PathPattern(entry[keyPath: side]).match(path) {
                return (entry, bindings)
            }
        }
        return nil
    }
}

/// A path whose segments may be placeholders such as "{id}" or "{id}:dark".
/// A placeholder matches a non-empty key; "{id}" matches no ":". The last
/// placeholder "{key}" matches the rest of the path.
struct PathPattern {
    private enum Segment {
        case literal(Substring)
        case placeholder(name: Substring, suffix: Substring)
    }

    private let segments: [Segment]

    init(_ pattern: String) {
        segments = pattern.split(separator: "/", omittingEmptySubsequences: false).map { segment in
            guard segment.first == "{", let close = segment.firstIndex(of: "}") else { return .literal(segment) }
            return .placeholder(
                name: segment[segment.index(after: segment.startIndex)..<close],
                suffix: segment[segment.index(after: close)...]
            )
        }
    }

    func match(_ path: String) -> [String: String]? {
        let parts = path.drop { $0 == "/" }.split(separator: "/", omittingEmptySubsequences: false)
        var bindings: [String: String] = [:]
        for (index, segment) in segments.enumerated() {
            guard index < parts.count else { return nil }
            switch segment {
            case .literal(let literal):
                guard parts[index] == literal else { return nil }
            case .placeholder(let name, _) where name == "key" && index == segments.count - 1:
                bindings["key"] = parts[index...].joined(separator: "/")
                return bindings
            case .placeholder(let name, let suffix):
                let part = parts[index]
                guard part.hasSuffix(suffix) else { return nil }
                let value = part.dropLast(suffix.count)
                guard !value.isEmpty, name != "id" || !value.contains(":") else { return nil }
                bindings[String(name)] = String(value)
            }
        }
        return parts.count == segments.count ? bindings : nil
    }

    func fill(_ bindings: [String: String]) -> String {
        segments.map { segment in
            switch segment {
            case .literal(let literal): String(literal)
            case .placeholder(let name, let suffix): (bindings[String(name)] ?? "") + suffix
            }
        }.joined(separator: "/")
    }
}
