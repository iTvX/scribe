import Foundation

/// A reserved librime property, which plugins set to talk to the frontend,
/// read the way Squirrel reads them (rime/squirrel#1124). librime reports a
/// property change as "key=value". Index values are a comma list, or a query
/// string with the list in its "value" field.
public enum ReservedProperty: Equatable, Sendable {
    /// Rows on the page whose comment uses the accent colour.
    case commentHighlight(Set<Int>)
    /// Rows on the page whose comment uses the warning colour.
    case commentWarning(Set<Int>)
    /// Redraw, keeping the comment marks.
    case refreshUI

    /// Nil for other properties and for values that do not parse.
    public init?(_ notificationValue: String) {
        guard notificationValue.hasPrefix("_"), let equals = notificationValue.firstIndex(of: "=") else { return nil }
        let value = String(notificationValue[notificationValue.index(after: equals)...])
        guard !value.isEmpty else { return nil }
        switch notificationValue[..<equals] {
        case "_refresh_ui":
            self = .refreshUI
        case "_comment_highlight":
            guard let indices = Self.indices(value) else { return nil }
            self = .commentHighlight(indices)
        case "_comment_warning":
            guard let indices = Self.indices(value) else { return nil }
            self = .commentWarning(indices)
        default:
            return nil
        }
    }

    private static func indices(_ value: String) -> Set<Int>? {
        var list = value
        if value.contains("=") {
            guard let field = URLComponents(string: "?\(value)")?.queryItems?.last(where: { $0.name == "value" }) else { return nil }
            list = field.value ?? ""
        }
        var indices = Set<Int>()
        for part in list.split(separator: ",") {
            guard let index = Int(part.trimmingCharacters(in: .whitespaces)), index >= 0 else { return nil }
            indices.insert(index)
        }
        return indices
    }
}
