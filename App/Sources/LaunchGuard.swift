import Foundation

/// Notices when Scribe is launched again within two seconds of the last
/// launch, which means it is crashing at startup, most likely because of a
/// broken configuration. Scribe then starts without Rime, as Squirrel does,
/// so the user can still type and fix the configuration.
struct LaunchGuard {
    /// Key into Localizable.strings for the spoken warning.
    static let warningKey = "launch_problem"

    let file: URL

    static let standard = LaunchGuard(
        file: FileManager.default.temporaryDirectory.appending(path: "scribe-launch.json")
    )

    /// Records this launch and returns whether the previous one was less
    /// than two seconds ago.
    func isRelaunchTooSoon(now: Date = Date()) -> Bool {
        let previous = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Double.self, from: $0) }
        try? JSONEncoder().encode(now.timeIntervalSince1970).write(to: file, options: .atomic)
        guard let previous else { return false }
        let elapsed = now.timeIntervalSince1970 - previous
        return elapsed >= 0 && elapsed < 2
    }
}
