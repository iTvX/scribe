import AppKit

struct SettingsManifest: Equatable {
    var build: String
    var identifier: String
    var protocolVersion: Int

    /// Bundle caches Info.plist. Read the installed bytes to detect replacement.
    static func read(at app: URL) -> Self? {
        guard let data = try? Data(contentsOf: app.appending(path: "Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let build = info["CFBundleVersion"] as? String,
              let identifier = info["CFBundleIdentifier"] as? String,
              let executable = info["CFBundleExecutable"] as? String,
              !executable.contains("/"),
              FileManager.default.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/\(executable)").path)
        else { return nil }
        return Self(build: build, identifier: identifier, protocolVersion: info["ScribeSettingsHandoffVersion"] as? Int ?? 0)
    }
}

@MainActor
protocol SettingsUpdateRuntime: AnyObject {
    var process: SettingsProcess { get }
    var loadedBuild: String { get }
    var identifier: String { get }
    var installed: SettingsManifest? { get }
    var interactionBlocked: Bool { get }
    func isAlive(_ process: SettingsProcess) -> Bool
    func flushEditing() -> Bool
    func launch(token: UUID) async throws
    func quit()
    func showLegacy(_ pids: [Int32])
}

@MainActor
final class NativeSettingsUpdateRuntime: SettingsUpdateRuntime {
    let process = NativeSettingsUpdateRuntime.identity(NSRunningApplication.current)
    let loadedBuild: String
    let identifier: String
    let appURL: URL
    let directories: SettingsDirectories
    let store: SettingsHandoffStore

    init(directories: SettingsDirectories, bundle: Bundle = .main) {
        self.directories = directories
        loadedBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        identifier = bundle.bundleIdentifier ?? ""
        appURL = bundle.bundleURL.standardizedFileURL
        let root: URL
        if !directories.isLive, let path = UserDefaults.standard.string(forKey: "ScribeHandoffRoot") {
            root = URL(filePath: path)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/\(identifier)/SettingsHandoff")
        }
        store = SettingsHandoffStore(root: root)
    }

    var installed: SettingsManifest? {
        guard let value = SettingsManifest.read(at: appURL) else { return nil }
        // An embedded helper must agree with its enclosing app before launch.
        let outer = appURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if outer.pathExtension == "app" {
            guard SettingsManifest.read(at: outer)?.build == value.build else { return nil }
        }
        return value
    }

    var interactionBlocked: Bool {
        NSApp.modalWindow != nil || NSApp.windows.contains { window in
            window.attachedSheet != nil || (window.firstResponder as? NSTextView)?.hasMarkedText() == true
        }
    }

    func flushEditing() -> Bool {
        NSApp.windows.filter(\.isVisible).allSatisfy { $0.makeFirstResponder(nil) }
    }

    func isAlive(_ process: SettingsProcess) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: process.pid), !app.isTerminated else { return false }
        return Self.identity(app) == process
    }

    func launch(token: UUID) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.activates = NSApp.isActive
        configuration.addsToRecentItems = false
        configuration.arguments = ["--settings-handoff", token.uuidString]
        if !directories.isLive {
            configuration.arguments += ["-ScribeUserDirectory", directories.user.path,
                                        "-ScribeHandoffRoot", store.root.path]
            if let shared = directories.shared { configuration.arguments += ["-ScribeSharedDirectory", shared.path] }
        }
        _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    func quit() { NSApp.terminate(nil) }

    func showLegacy(_ pids: [Int32]) {
        for pid in pids {
            guard let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == identifier,
                  app.bundleURL?.standardizedFileURL == appURL else { continue }
            app.activate(options: [.activateAllWindows])
        }
    }

    static func identity(_ app: NSRunningApplication) -> SettingsProcess {
        SettingsProcess(pid: app.processIdentifier, launchedAt: app.launchDate?.timeIntervalSince1970 ?? 0)
    }
}
