import Foundation
import ScribeConfig
import ScribeCore

/// Everything the candidate window shows at one moment: ScribeCore's
/// snapshot plus what ScribeCore does not report yet.
struct PanelContent: Equatable, Sendable {
    /// Nil when nothing is being composed.
    var snapshot: CandidateSnapshot?
    /// Rows whose comment uses the accent or warning colour, unless the row
    /// is highlighted. Accent wins when a row is in both.
    var accentCommentIndices: Set<Int> = []
    var warningCommentIndices: Set<Int> = []
    /// Shown alone, such as "中文" after switching modes, when there is
    /// nothing else to show.
    var statusMessage: String?

    init(
        _ snapshot: CandidateSnapshot?,
        accentCommentIndices: Set<Int> = [],
        warningCommentIndices: Set<Int> = [],
        statusMessage: String? = nil
    ) {
        self.snapshot = snapshot
        self.accentCommentIndices = accentCommentIndices
        self.warningCommentIndices = warningCommentIndices
        self.statusMessage = statusMessage
    }

    /// The status message to show for a mode change, picked the way
    /// Squirrel's `status_message_type` picks it.
    static func statusMessage(long: String, short: String, type: StatusMessageType) -> String {
        switch type {
        case .mix:
            short.isEmpty ? long : short
        case .long:
            long
        case .short:
            if !short.isEmpty {
                short
            } else if let initial = long.first {
                String(initial)
            } else {
                ""
            }
        }
    }
}
