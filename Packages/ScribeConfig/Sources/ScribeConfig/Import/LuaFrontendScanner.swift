import Foundation

/// Finds Lua lines that mention Squirrel, which usually means the script
/// behaves differently depending on the frontend, for example through
/// `rime_api.get_distribution_name()`.
enum LuaFrontendScanner {
    static let frontendNames = ["Squirrel", "鼠鬚管", "鼠须管"]

    /// One notice per non-comment line that names Squirrel. `file` is the
    /// path reported in the notices.
    static func notices(in text: String, file: String) -> [MigrationNotice] {
        var notices: [MigrationNotice] = []
        for (index, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.hasPrefix("--"),
                  frontendNames.contains(where: { trimmed.contains($0) })
            else { continue }
            notices.append(.luaChecksFrontend(file: file, line: index + 1, text: trimmed))
        }
        return notices
    }
}
