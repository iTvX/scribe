import Darwin
import Foundation

/// Versioned and private: a receipt is also a durable recovery copy until the
/// receiving window has saved/discarded its drafts or handed them on again.
enum SettingsHandoffError: Error {
    case unsafeStore, invalidRecord, wrongDirectory, cannotRestore, incompatibleVersion, launchFailed
}

struct SettingsProcess: Codable, Equatable {
    var pid: Int32
    var launchedAt: TimeInterval
}

struct SettingsHandoff: Codable, Equatable {
    enum Phase: String, Codable { case waiting, ready, committed, cancelled }
    var format = 1
    var token = UUID()
    var source: SettingsProcess
    var receiver: SettingsProcess?
    var targetBuild: String
    var createdAt = Date()
    var phase: Phase = .waiting
    var draft: SettingsDraft
}

struct SettingsLease: Codable {
    var format = 1
    var process: SettingsProcess
    var build: String
}

struct SettingsHandoffStore {
    let root: URL
    private let limit = 8 * 1024 * 1024

    func create(_ record: SettingsHandoff) throws {
        try locked { try write(record, name: record.token.uuidString + ".json") }
    }

    func read(_ token: UUID) throws -> SettingsHandoff {
        try locked { try record(token) }
    }

    /// Compare-and-swap prevents a late acknowledgement racing cancellation.
    @discardableResult
    func transition(_ token: UUID, from: SettingsHandoff.Phase, to: SettingsHandoff.Phase,
                    receiver: SettingsProcess? = nil) throws -> Bool {
        try locked {
            var value = try record(token)
            guard value.phase == from else { return false }
            let allowed = (from == .waiting && (to == .ready || to == .cancelled))
                || (from == .ready && (to == .committed || to == .cancelled))
            guard allowed else { throw SettingsHandoffError.invalidRecord }
            value.phase = to
            if let receiver { value.receiver = receiver }
            try write(value, name: token.uuidString + ".json")
            return true
        }
    }

    func claim(_ expected: SettingsHandoff, by process: SettingsProcess) throws -> Bool {
        try locked {
            guard try record(expected.token) == expected else { return false }
            var claimed = expected
            claimed.source = process
            claimed.receiver = process
            claimed.phase = .committed
            try write(claimed, name: claimed.token.uuidString + ".json")
            return true
        }
    }

    func checkpoint(_ token: UUID, draft: SettingsDraft) throws {
        try locked {
            var value = try record(token)
            guard value.phase == .committed || value.phase == .cancelled else { throw SettingsHandoffError.invalidRecord }
            guard value.draft != draft else { return }
            value.draft = draft
            try write(value, name: token.uuidString + ".json")
        }
    }

    func remove(_ token: UUID) throws {
        try locked { try FileManager.default.removeItem(at: root.appending(path: token.uuidString + ".json")) }
    }

    func records() throws -> [SettingsHandoff] {
        try locked {
            try FileManager.default.contentsOfDirectory(atPath: root.path).compactMap { name in
                guard name.hasSuffix(".json"), let token = UUID(uuidString: String(name.dropLast(5))) else { return nil }
                return try? record(token)
            }.sorted { $0.createdAt > $1.createdAt }
        }
    }

    /// Repeated completed-install jobs must not race before the new app has
    /// registered its lease. This short-lived claim contains no user drafts.
    func claimLegacyLaunch(build: String, now: Date = .now) throws -> Bool {
        struct Claim: Codable { var build: String; var createdAt: Date }
        return try locked {
            if let claim = try? decode(Claim.self, name: "legacy-launch.json"),
               claim.build == build, now.timeIntervalSince(claim.createdAt) < 30 { return false }
            try write(Claim(build: build, createdAt: now), name: "legacy-launch.json")
            return true
        }
    }

    func register(_ lease: SettingsLease) throws {
        try locked { try write(lease, name: "process-\(lease.process.pid).json") }
    }

    func lease(for process: SettingsProcess) throws -> SettingsLease? {
        try locked {
            guard let value = try? decode(SettingsLease.self, name: "process-\(process.pid).json"),
                  value.format == 1, value.process == process else { return nil }
            return value
        }
    }

    func unregister(_ process: SettingsProcess) {
        try? locked {
            let name = "process-\(process.pid).json"
            if let value = try? decode(SettingsLease.self, name: name), value.process == process {
                try FileManager.default.removeItem(at: root.appending(path: name))
            }
        }
    }

    private func record(_ token: UUID) throws -> SettingsHandoff {
        let value = try decode(SettingsHandoff.self, name: token.uuidString + ".json")
        guard value.format == 1, value.token == token else { throw SettingsHandoffError.invalidRecord }
        return value
    }

    private func decode<T: Decodable>(_ type: T.Type, name: String) throws -> T {
        let path = root.appending(path: name).path
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw SettingsHandoffError.invalidRecord }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o077 == 0, info.st_size <= limit else { throw SettingsHandoffError.unsafeStore }
        let data = try FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd() ?? Data()
        return try JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, name: String) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= limit else { throw SettingsHandoffError.invalidRecord }
        let temporary = root.appending(path: UUID().uuidString + ".tmp").path
        let fd = open(temporary, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw SettingsHandoffError.unsafeStore }
        defer { close(fd); unlink(temporary) }
        try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: data)
        guard fsync(fd) == 0, rename(temporary, root.appending(path: name).path) == 0 else {
            throw SettingsHandoffError.unsafeStore
        }
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & 0o077 == 0 else { throw SettingsHandoffError.unsafeStore }
        let fd = open(root.appending(path: ".lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw SettingsHandoffError.unsafeStore }
        defer { close(fd) }
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o077 == 0, flock(fd, LOCK_EX) == 0 else { throw SettingsHandoffError.unsafeStore }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }
}
