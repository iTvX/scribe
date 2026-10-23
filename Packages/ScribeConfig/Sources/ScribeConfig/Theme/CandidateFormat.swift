/// How one candidate is laid out, from `candidate_format`.
public struct CandidateFormat: Equatable, Sendable {
    public static let `default` = CandidateFormat("[label]. [candidate] [comment]")

    /// The template with Squirrel's legacy tokens replaced.
    public var template: String

    /// Replaces every "%@" with "[candidate] [comment]", then every "%c" with
    /// "[label]", as Squirrel does.
    public init(_ squirrelTemplate: String) {
        template = squirrelTemplate
            .replacing(/%@/, with: "[candidate] [comment]")
            .replacing(/%c/, with: "[label]")
    }

    public enum Segment: Equatable, Sendable {
        case text(String)
        case label
        case candidate
        case comment
    }

    /// The template split at its tokens. Literal text is drawn in the label
    /// style, as in Squirrel.
    public var segments: [Segment] {
        var segments: [Segment] = []
        var rest = template[...]
        while let match = rest.firstMatch(of: /\[(label|candidate|comment)\]/) {
            if match.range.lowerBound > rest.startIndex {
                segments.append(.text(String(rest[..<match.range.lowerBound])))
            }
            switch match.output.1 {
            case "label": segments.append(.label)
            case "candidate": segments.append(.candidate)
            default: segments.append(.comment)
            }
            rest = rest[match.range.upperBound...]
        }
        if !rest.isEmpty {
            segments.append(.text(String(rest)))
        }
        return segments
    }

    /// False when the template has no "[label]"; Squirrel then computes no
    /// labels.
    public var showsLabel: Bool {
        template.contains(/\[label\]/)
    }
}
