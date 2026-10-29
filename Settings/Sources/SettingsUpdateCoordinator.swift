import AppKit

/// All model access is serialized on the main actor. Only one window can edit
/// a transaction: old freezes before launch; new stays frozen until commit.
@MainActor
final class SettingsUpdateCoordinator {
    let runtime: any SettingsUpdateRuntime
    let store: SettingsHandoffStore
    let session: SettingsSession
    let defaults: DefaultsModel
    let looks: LooksModel
    let importer: ImportModel
    var timeout: TimeInterval = 30
    private var timer: Timer?
    private var installObserver: NSObjectProtocol?
    private var outgoing: UUID?
    private var incoming: UUID?
    private var recovery: UUID?
    private var deadline = Date.distantFuture
    private var candidate: SettingsManifest?
    private var failedBuild: String?
    private(set) var isQuitting = false
    private var started = false

    init(runtime: any SettingsUpdateRuntime, store: SettingsHandoffStore, session: SettingsSession,
         defaults: DefaultsModel, looks: LooksModel, importer: ImportModel) {
        self.runtime = runtime
        self.store = store
        self.session = session
        self.defaults = defaults
        self.looks = looks
        self.importer = importer
    }

    /// Returns true when restoring a session, so launch-time import/conversion
    /// automation cannot mutate its files before the draft has been restored.
    @discardableResult
    func start(token: UUID? = nil, scheduled: Bool = true) -> Bool {
        guard !started else { return true }
        started = true
        var restored = false
        do {
            try store.register(SettingsLease(process: runtime.process, build: runtime.loadedBuild))
            if let token {
                session.isFrozen = true
                let record = try store.read(token)
                guard record.targetBuild == runtime.loadedBuild, record.phase == .waiting else {
                    throw SettingsHandoffError.incompatibleVersion
                }
                try restore(record.draft)
                guard try store.transition(token, from: .waiting, to: .ready, receiver: runtime.process) else {
                    throw SettingsHandoffError.invalidRecord
                }
                incoming = token
                session.updateMessage = "正在接续未保存的修改…"
                restored = true
            } else if let record = try store.records().first(where: {
                $0.draft.userDirectory == defaults.directories.user.standardizedFileURL
                    && !runtime.isAlive($0.source) && !($0.receiver.map(runtime.isAlive) ?? false)
            }) {
                // A previous receiver or source crashed. Claim the archive before
                // enabling input, so a second launch cannot recover it concurrently.
                try restore(record.draft)
                guard try store.claim(record, by: runtime.process) else {
                    isQuitting = true
                    runtime.quit()
                    return true
                }
                recovery = record.token
                session.updateMessage = "已恢复上次更新时未保存的修改，请检查后保存。"
                restored = true
            }
        } catch {
            session.updateMessage = "无法接续设置，原窗口和草稿已保留。"
            if token != nil {
                isQuitting = true
                runtime.quit()
                return true
            }
            // No private store means no automatic restart, not lost edits.
            session.canRetryUpdate = true
        }
        if scheduled {
            installObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(SettingsInstallationBridge.completedNotification),
                object: runtime.identifier, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.retry() }
            }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
        return restored
    }

    func tick(now: Date = .now) {
        guard !isQuitting else { return }
        do {
            if let incoming {
                let record = try store.read(incoming)
                if record.phase == .cancelled {
                    isQuitting = true
                    runtime.quit()
                } else if record.phase == .committed || (record.phase == .ready && !runtime.isAlive(record.source)) {
                    if record.phase == .ready { try store.transition(incoming, from: .ready, to: .committed) }
                    self.incoming = nil
                    recovery = incoming
                    session.isFrozen = false
                    session.updateMessage = "已切换到新版设置，未保存的修改已保留。"
                }
                return
            }
            if let outgoing {
                let record = try store.read(outgoing)
                if record.phase == .ready, let receiver = record.receiver, runtime.isAlive(receiver) {
                    guard try store.transition(outgoing, from: .ready, to: .committed) else { return }
                    if let recovery { try? store.remove(recovery) }
                    self.recovery = nil
                    isQuitting = true
                    runtime.quit()
                } else if record.phase == .ready || now >= deadline {
                    failOutgoing()
                }
                return
            }
            try checkpoint()
            guard let installed = runtime.installed, installed.identifier == runtime.identifier,
                  installed.build != runtime.loadedBuild, installed.protocolVersion == 1,
                  installed.build != failedBuild else { candidate = nil; return }
            guard candidate == installed else { candidate = installed; return }
            guard !isBusy, runtime.flushEditing() else {
                session.updateMessage = "新版已准备好，当前操作结束后会自动切换，修改会保留。"
                return
            }
            begin(installed, now: now)
        } catch {
            if outgoing != nil {
                // Reading a receipt failed: never assume the new process owns it.
                // Keep the old draft frozen until cancellation can be recorded.
                session.updateMessage = "暂时无法确认新版已接收修改，草稿仍保留。正在重试…"
            } else {
                session.updateMessage = "暂时无法保留更新草稿，当前窗口继续可用。"
                session.canRetryUpdate = true
            }
        }
    }

    var isBusy: Bool { importer.handoffBlocked || session.isRecordingShortcut || runtime.interactionBlocked }

    private func begin(_ installed: SettingsManifest, now: Date) {
        session.isFrozen = true
        session.canRetryUpdate = false
        do {
            let record = SettingsHandoff(source: runtime.process, targetBuild: installed.build, draft: snapshot())
            try store.create(record)
            outgoing = record.token
            deadline = now.addingTimeInterval(timeout)
            session.updateMessage = "正在切换到新版设置…"
            Task {
                do { try await runtime.launch(token: record.token) }
                catch {
                    guard outgoing == record.token, !isQuitting else { return }
                    failOutgoing()
                }
            }
        } catch {
            session.isFrozen = false
            failedBuild = installed.build
            session.canRetryUpdate = true
            session.updateMessage = "无法暂存修改，当前窗口已保留。请稍后重试更新切换。"
        }
    }

    private func failOutgoing() {
        guard let token = outgoing else { return }
        do {
            let record = try store.read(token)
            // A valid ACK wins over a timeout or late launch callback.
            if record.phase == .ready, let receiver = record.receiver, runtime.isAlive(receiver) {
                tick()
                return
            }
            guard try store.transition(token, from: record.phase, to: .cancelled) else { return }
            if let recovery { try? store.remove(recovery) }
            recovery = token
            failedBuild = record.targetBuild
            outgoing = nil
            session.isFrozen = false
            session.canRetryUpdate = true
            session.updateMessage = "新版暂时未能接收修改，当前窗口和草稿已保留。"
        } catch {
            session.updateMessage = "暂时无法确认交接状态，草稿已保留。正在重试…"
        }
    }

    func retry() {
        failedBuild = nil
        candidate = nil
        session.canRetryUpdate = false
        tick()
    }

    func showLegacy() { runtime.showLegacy(session.legacyPIDs) }

    /// Quitting during the brief handshake would violate the single-editor
    /// guarantee. A normal quit also checkpoints any recovered edits.
    func prepareToQuit() -> Bool {
        if isQuitting { store.unregister(runtime.process); return true }
        guard outgoing == nil, incoming == nil else { return false }
        do { try checkpoint() }
        catch {
            session.updateMessage = "草稿备份未完成，窗口已保留。请保存修改后再关闭。"
            return false
        }
        timer?.invalidate()
        if let installObserver { DistributedNotificationCenter.default().removeObserver(installObserver) }
        store.unregister(runtime.process)
        return true
    }

    private func snapshot() -> SettingsDraft {
        SettingsDraft(defaults: defaults, looks: looks, importer: importer, session: session)
    }

    private func restore(_ draft: SettingsDraft) throws {
        try draft.restore(defaults: defaults, looks: looks, importer: importer, session: session)
    }

    private func checkpoint() throws {
        if let recovery {
            let draft = snapshot()
            if draft.hasPendingChanges { try store.checkpoint(recovery, draft: draft) }
            else { try store.remove(recovery); self.recovery = nil }
        }
    }
}
