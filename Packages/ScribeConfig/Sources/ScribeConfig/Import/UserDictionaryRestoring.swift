import Foundation

/// Merges a `*.userdb.txt` snapshot into Scribe's user dictionaries.
/// RimeKit implements it with librime's restore_user_dict after M1's RimeKit PR.
public protocol UserDictionaryRestoring: Sendable {
    func restoreUserDictionary(from snapshot: URL) async throws
}

/// A snapshot that could not be merged, and why.
public struct UserDictionaryRestoreFailure: Error, Sendable {
    public var snapshot: URL
    public var message: String
}

extension UserDictionaryImport {
    /// Restores every snapshot in order, continuing past failures; returns the failures.
    public func restore(using restorer: some UserDictionaryRestoring) async -> [UserDictionaryRestoreFailure] {
        var failures: [UserDictionaryRestoreFailure] = []
        for snapshot in snapshots {
            do {
                try await restorer.restoreUserDictionary(from: snapshot)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                failures.append(UserDictionaryRestoreFailure(snapshot: snapshot, message: message))
            }
        }
        return failures
    }
}
