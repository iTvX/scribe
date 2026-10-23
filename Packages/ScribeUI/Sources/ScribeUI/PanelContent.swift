import Foundation
import ScribeConfig
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
