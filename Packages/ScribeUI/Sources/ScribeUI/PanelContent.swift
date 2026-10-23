import Foundation
import ScribeCore

/// Everything the candidate window shows at one moment: ScribeCore's
/// snapshot, or a status message.
struct PanelContent: Equatable, Sendable {
    /// Nil when nothing is being composed.
    var snapshot: CandidateSnapshot?
    /// Shown alone, such as "中文" after switching modes, when there is
    /// nothing else to show.
    var statusMessage: String?

    init(_ snapshot: CandidateSnapshot?, statusMessage: String? = nil) {
        self.snapshot = snapshot
        self.statusMessage = statusMessage
    }
}
