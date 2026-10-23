internal import librime
import Foundation
import os

/// Where librime finds its data and writes its logs.
public struct RimeConfiguration: Sendable {
    /// Read-only data shipped with the app, such as default schemas.
    public var sharedDataDirectory: URL
    /// The user's configuration, dictionaries and deployed files.
    public var userDataDirectory: URL
    /// Nil writes logs to standard error only.
    public var logDirectory: URL?
    /// 0 info, 1 warning, 2 error, 3 fatal.
    public var minimumLogLevel: Int
    /// In the form "rime.x"; librime cleans up old logs with this prefix.
    public var appName: String
    public var distributionName: String
    public var distributionCodeName: String
    public var distributionVersion: String

    public init(
        sharedDataDirectory: URL,
        userDataDirectory: URL,
        logDirectory: URL? = nil,
        minimumLogLevel: Int = 0,
        appName: String = "rime.scribe",
        distributionName: String = "Scribe",
        distributionCodeName: String = "Scribe",
        distributionVersion: String = "0"
    ) {
        self.sharedDataDirectory = sharedDataDirectory
        self.userDataDirectory = userDataDirectory
        self.logDirectory = logDirectory
        self.minimumLogLevel = minimumLogLevel
        self.appName = appName
        self.distributionName = distributionName
        self.distributionCodeName = distributionCodeName
        self.distributionVersion = distributionVersion
    }
}

/// The librime instance of this process. librime keeps global state, so there
/// is exactly one, and every call goes through the main actor: the input
/// method has to answer each key synchronously, and a single executor keeps
/// calls serialized.
@MainActor
public final class LibrimeEngine: RimeEngine {
    public static let shared = LibrimeEngine()

    /// Called on the main actor for every librime notification.
    public var notificationHandler: ((RimeNotification) -> Void)?

    public private(set) var isRunning = false

    /// librime's C API, for extensions in this module.
    let api: UnsafeMutablePointer<RimeApi_stdbool>
    private var isSetUp = false
    /// The strings passed to librime's setup. glog keeps the app name for
    /// the life of the process and names log files it opens later after it,
    /// so these are never freed.
    private var setupStrings: [UnsafeMutablePointer<CChar>?] = []

    private init() {
        api = rime_get_api_stdbool()
    }

    /// Sets up librime (once per process) and initializes it with
    /// `configuration`. Does not deploy.
    public func start(_ configuration: RimeConfiguration) {
        precondition(!isRunning, "librime is already running")
        if !isSetUp {
            setupStrings = withTraits(configuration, freeingStrings: false) { traits in
                api.pointee.setup(traits)
            }
            api.pointee.set_notification_handler(handleNotification, nil)
            isSetUp = true
        }
        // librime copies the directories it is initialized with.
        _ = withTraits(configuration, freeingStrings: true) { traits in
            api.pointee.initialize(traits)
        }
        isRunning = true
    }

    /// Compiles the configuration and schemas in `directory` in place, the
    /// way a distribution prebuilds its shared data. Use instead of `start`,
    /// in a process that runs nothing else.
    public func buildWorkspace(in directory: URL) -> Bool {
        precondition(!isSetUp, "librime is already set up")
        let configuration = RimeConfiguration(
            sharedDataDirectory: directory,
            userDataDirectory: directory,
            minimumLogLevel: 2,
            appName: "rime.scribe-builder"
        )
        setupStrings = withTraits(configuration, freeingStrings: false) { traits in
            api.pointee.setup(traits)
            api.pointee.deployer_initialize(traits)
        }
        isSetUp = true
        return api.pointee.deploy()
    }

    /// Finalizes librime, closing all sessions. `start` may be called again.
    public func stop() {
        guard isRunning else { return }
        api.pointee.finalize()
        isRunning = false
    }

    /// Starts deploying in librime's maintenance thread. With `fullCheck`
    /// false, librime only deploys when it detects changed files. Returns
    /// false if no maintenance was started.
    @discardableResult
    public func startMaintenance(fullCheck: Bool) -> Bool {
        lastDeployResult.withLock { $0 = nil }
        return api.pointee.start_maintenance(fullCheck)
    }

    public var isInMaintenance: Bool {
        isRunning && api.pointee.is_maintenance_mode()
    }

    public func joinMaintenance() {
        api.pointee.join_maintenance_thread()
    }

    /// Deploys and waits for it to finish. Returns true on success.
    public func deploy(fullCheck: Bool = true) -> Bool {
        guard startMaintenance(fullCheck: fullCheck) else { return false }
        joinMaintenance()
        return lastDeployResult.withLock { $0 } == "success"
    }

    /// Starts synchronizing user data with the sync directory, in librime's
    /// maintenance thread. librime closes all sessions first.
    @discardableResult
    public func syncUserData() -> Bool {
        api.pointee.sync_user_data()
    }

    /// Nil while librime is not running.
    public func createSession() -> RimeSessionID? {
        guard isRunning else { return nil }
        let id = api.pointee.create_session()
        return id == 0 ? nil : RimeSessionID(rawValue: UInt(id))
    }

    public func sessionExists(_ session: RimeSessionID) -> Bool {
        api.pointee.find_session(RimeSessionId(session.rawValue))
    }

    public func destroySession(_ session: RimeSessionID) {
        _ = api.pointee.destroy_session(RimeSessionId(session.rawValue))
    }

    public func processKey(_ keycode: Int32, modifiers: Int32, in session: RimeSessionID) -> Bool {
        api.pointee.process_key(RimeSessionId(session.rawValue), keycode, modifiers)
    }

    public func consumeCommit(in session: RimeSessionID) -> String? {
        var commit = RimeCommit()
        commit.data_size = dataSize(of: RimeCommit.self)
        guard api.pointee.get_commit(RimeSessionId(session.rawValue), &commit) else { return nil }
        defer { _ = api.pointee.free_commit(&commit) }
        return commit.text.map { String(cString: $0) }
    }

    public func context(in session: RimeSessionID) -> EngineContext {
        var context = RimeContext_stdbool()
        context.data_size = dataSize(of: RimeContext_stdbool.self)
        guard api.pointee.get_context(RimeSessionId(session.rawValue), &context) else { return EngineContext() }
        defer { _ = api.pointee.free_context(&context) }
        return EngineContext(
            composition: composition(from: context.composition),
            menu: menu(from: context.menu, labels: context.select_labels),
            commitPreview: context.commit_text_preview.map { String(cString: $0) }
        )
    }

    public func status(in session: RimeSessionID) -> EngineStatus? {
        var status = RimeStatus_stdbool()
        status.data_size = dataSize(of: RimeStatus_stdbool.self)
        guard api.pointee.get_status(RimeSessionId(session.rawValue), &status) else { return nil }
        defer { _ = api.pointee.free_status(&status) }
        return EngineStatus(
            schemaID: status.schema_id.map { String(cString: $0) } ?? "",
            schemaName: status.schema_name.map { String(cString: $0) } ?? "",
            isDisabled: status.is_disabled,
            isComposing: status.is_composing,
            isASCIIMode: status.is_ascii_mode
        )
    }

    public func selectCandidate(onCurrentPage index: Int, in session: RimeSessionID) -> Bool {
        api.pointee.select_candidate_on_current_page(RimeSessionId(session.rawValue), index)
    }

    public func changePage(backward: Bool, in session: RimeSessionID) -> Bool {
        api.pointee.change_page(RimeSessionId(session.rawValue), backward)
    }

    public func commitComposition(in session: RimeSessionID) -> Bool {
        api.pointee.commit_composition(RimeSessionId(session.rawValue))
    }

    public func clearComposition(in session: RimeSessionID) {
        api.pointee.clear_composition(RimeSessionId(session.rawValue))
    }

    public func setOption(_ option: String, _ value: Bool, in session: RimeSessionID) {
        api.pointee.set_option(RimeSessionId(session.rawValue), option, value)
    }

    public func option(_ option: String, in session: RimeSessionID) -> Bool {
        api.pointee.get_option(RimeSessionId(session.rawValue), option)
    }

    public func input(in session: RimeSessionID) -> String? {
        api.pointee.get_input(RimeSessionId(session.rawValue)).map { String(cString: $0) }
    }

    public func caretPosition(in session: RimeSessionID) -> Int {
        Int(api.pointee.get_caret_pos(RimeSessionId(session.rawValue)))
    }

    public func setCaretPosition(_ position: Int, in session: RimeSessionID) {
        api.pointee.set_caret_pos(RimeSessionId(session.rawValue), position)
    }

    public func stateLabel(_ option: String, state: Bool, abbreviated: Bool, in session: RimeSessionID) -> String? {
        let slice = api.pointee.get_state_label_abbreviated(RimeSessionId(session.rawValue), option, state, abbreviated)
        guard let start = slice.str, slice.length > 0 else { return nil }
        return String(decoding: UnsafeRawBufferPointer(start: start, count: slice.length), as: UTF8.self)
    }

    fileprivate func deliver(_ notification: RimeNotification) {
        notificationHandler?(notification)
    }

    /// Calls `body` with traits for `configuration` and returns the strings
    /// they point to, already freed unless `freeingStrings` is false.
    private func withTraits(
        _ configuration: RimeConfiguration,
        freeingStrings: Bool,
        _ body: (UnsafeMutablePointer<RimeTraits>) -> Void
    ) -> [UnsafeMutablePointer<CChar>?] {
        let strings = [
            configuration.sharedDataDirectory.path(percentEncoded: false),
            configuration.userDataDirectory.path(percentEncoded: false),
            configuration.distributionName,
            configuration.distributionCodeName,
            configuration.distributionVersion,
            configuration.appName,
            configuration.logDirectory?.path(percentEncoded: false) ?? "",
        ].map { strdup($0) }
        defer {
            if freeingStrings {
                strings.forEach { free($0) }
            }
        }

        var traits = RimeTraits()
        traits.data_size = dataSize(of: RimeTraits.self)
        traits.shared_data_dir = UnsafePointer(strings[0])
        traits.user_data_dir = UnsafePointer(strings[1])
        traits.distribution_name = UnsafePointer(strings[2])
        traits.distribution_code_name = UnsafePointer(strings[3])
        traits.distribution_version = UnsafePointer(strings[4])
        traits.app_name = UnsafePointer(strings[5])
        traits.log_dir = UnsafePointer(strings[6])
        traits.min_log_level = Int32(configuration.minimumLogLevel)
        body(&traits)
        return freeingStrings ? [] : strings
    }

    private func composition(from composition: RimeComposition) -> Composition? {
        guard composition.length > 0, let preedit = composition.preedit else { return nil }
        let length = Int(composition.length)
        let bytes = UnsafeRawBufferPointer(start: preedit, count: length)
        func utf16Offset(_ byteOffset: Int32) -> Int {
            let end = min(max(Int(byteOffset), 0), length)
            return String(decoding: bytes[..<end], as: UTF8.self).utf16.count
        }
        return Composition(
            preedit: String(decoding: bytes, as: UTF8.self),
            cursor: utf16Offset(composition.cursor_pos),
            selectionStart: utf16Offset(composition.sel_start),
            selectionEnd: utf16Offset(composition.sel_end)
        )
    }

    private func menu(from menu: RimeMenu_stdbool, labels: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> CandidateMenu? {
        let count = Int(menu.num_candidates)
        guard count > 0, let candidates = menu.candidates else { return nil }
        return CandidateMenu(
            candidates: (0..<count).map { index in
                let candidate = candidates[index]
                return Candidate(
                    text: candidate.text.map { String(cString: $0) } ?? "",
                    comment: candidate.comment.map { String(cString: $0) }
                )
            },
            pageSize: Int(menu.page_size),
            pageNumber: Int(menu.page_no),
            isLastPage: menu.is_last_page,
            highlightedIndex: Int(menu.highlighted_candidate_index),
            selectLabels: labels.map { labels in
                (0..<count).map { labels[$0].map { String(cString: $0) } ?? "" }
            },
            selectKeys: menu.select_keys.map { String(cString: $0) }
        )
    }
}

/// librime's self-versioned structs start with the size of the rest of the
/// struct.
private func dataSize<T>(of type: T.Type) -> Int32 {
    Int32(MemoryLayout<T>.stride - MemoryLayout<Int32>.stride)
}

/// The latest "deploy" notification value: "start", "success" or "failure".
/// Written from librime's maintenance thread.
private let lastDeployResult = OSAllocatedUnfairLock<String?>(initialState: nil)

private func handleNotification(
    _ context: UnsafeMutableRawPointer?,
    _ session: RimeSessionId,
    _ type: UnsafePointer<CChar>?,
    _ value: UnsafePointer<CChar>?
) {
    guard let type, let value else { return }
    let notification = RimeNotification(
        sessionID: RimeSessionID(rawValue: UInt(session)),
        type: String(cString: type),
        value: String(cString: value)
    )
    if notification.type == "deploy" {
        lastDeployResult.withLock { $0 = notification.value }
    }
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            LibrimeEngine.shared.deliver(notification)
        }
    }
}
