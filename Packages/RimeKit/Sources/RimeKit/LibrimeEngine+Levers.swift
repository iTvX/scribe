internal import librime
import Foundation

/// A value for a `*.custom.yaml` patch.
public enum CustomValue: Equatable, Sendable {
    case bool(Bool), int(Int), double(Double), string(String)
    /// A list or map, written as YAML and loaded with config_load_string.
    case yaml(String)
}

/// Deployment tasks, user dictionary maintenance and configuration patches,
/// through librime's levers module. Every method needs `isRunning` and
/// returns false or nil without it.
extension LibrimeEngine {
    /// Runs one deployment task, such as "installation_update" or "user_dict_sync", synchronously.
    public func runTask(_ name: String) -> Bool {
        guard isRunning, let loadDeployer = api.pointee.deployer_initialize, let runTask = api.pointee.run_task
        else { return false }
        // librime registers the tasks with its deployer module, which it only
        // loads for maintenance. With no traits this keeps the directories.
        loadDeployer(nil)
        return runTask(name)
    }

    /// Snapshot of `<name>.userdb` written to `<sync dir>/<installation id>/<name>.userdb.txt`.
    public func backupUserDictionary(_ name: String) -> URL? {
        guard isRunning, let backup = levers?.pointee.backup_user_dict, backup(name),
              let directory = userDataSyncDirectory
        else { return nil }
        let snapshot = directory.appending(path: "\(name).userdb.txt", directoryHint: .notDirectory)
        return FileManager.default.fileExists(atPath: snapshot.path(percentEncoded: false)) ? snapshot : nil
    }

    /// Merges a `*.userdb.txt` snapshot into the user dictionary it names.
    public func restoreUserDictionary(from snapshot: URL) -> Bool {
        guard isRunning, let restore = levers?.pointee.restore_user_dict else { return false }
        return restore(snapshot.path(percentEncoded: false))
    }

    /// The names of the `*.userdb` dictionaries in the user data directory.
    public func userDictionaryNames() -> [String] {
        guard isRunning, let levers,
              let initialize = levers.pointee.user_dict_iterator_init,
              let next = levers.pointee.next_user_dict,
              let destroy = levers.pointee.user_dict_iterator_destroy
        else { return [] }
        var iterator = RimeUserDictIterator()
        // False when there are no user dictionaries.
        guard initialize(&iterator) else { return [] }
        defer { destroy(&iterator) }
        var names: [String] = []
        while let name = next(&iterator) {
            names.append(String(cString: name))
        }
        return names
    }

    /// `<sync dir>/<installation id>`, where this installation's snapshots go.
    public var userDataSyncDirectory: URL? {
        guard isRunning, let getDirectory = api.pointee.get_user_data_sync_dir else { return nil }
        var buffer = [CChar](repeating: 0, count: 4096)
        getDirectory(&buffer, buffer.count)
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return path.isEmpty ? nil : URL(filePath: path, directoryHint: .isDirectory)
    }

    /// Patches `<configID>.custom.yaml` through levers (load, customize each change, save).
    public func customize(_ configID: String, _ changes: [(key: String, value: CustomValue)],
                          generator: String = "Scribe") -> Bool {
        guard isRunning, let levers,
              let initialize = levers.pointee.custom_settings_init,
              let destroy = levers.pointee.custom_settings_destroy,
              let load = levers.pointee.load_settings,
              let save = levers.pointee.save_settings,
              let settings = initialize(configID, generator)
        else { return false }
        defer { destroy(settings) }
        // False when the custom file does not exist yet.
        _ = load(settings)
        for (key, value) in changes {
            guard customize(settings, key, value, levers: levers.pointee) else { return false }
        }
        return changes.isEmpty || save(settings)
    }

    private func customize(_ settings: UnsafeMutablePointer<RimeCustomSettings>, _ key: String, _ value: CustomValue,
                           levers: RimeLeversApi_stdbool) -> Bool {
        switch value {
        case .bool(let value):
            return levers.customize_bool?(settings, key, value) ?? false
        case .int(let value):
            guard let value = Int32(exactly: value) else { return false }
            return levers.customize_int?(settings, key, value) ?? false
        case .double(let value):
            return levers.customize_double?(settings, key, value) ?? false
        case .string(let value):
            return levers.customize_string?(settings, key, value) ?? false
        case .yaml(let yaml):
            guard let initialize = api.pointee.config_init,
                  let loadString = api.pointee.config_load_string,
                  let close = api.pointee.config_close,
                  let customizeItem = levers.customize_item
            else { return false }
            var config = RimeConfig()
            guard initialize(&config) else { return false }
            defer { _ = close(&config) }
            return loadString(&config, yaml) && customizeItem(settings, key, &config)
        }
    }

    /// librime's levers API, or nil if this librime lacks it or has an older one.
    private var levers: UnsafeMutablePointer<RimeLeversApi_stdbool>? {
        guard let module = api.pointee.find_module?("levers"),
              let getAPI = module.pointee.get_api,
              let custom = getAPI()
        else { return nil }
        let levers = UnsafeMutableRawPointer(custom).assumingMemoryBound(to: RimeLeversApi_stdbool.self)
        let expectedSize = MemoryLayout<RimeLeversApi_stdbool>.stride - MemoryLayout<Int32>.stride
        return Int(levers.pointee.data_size) >= expectedSize ? levers : nil
    }
}
