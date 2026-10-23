import AppKit
import Foundation
import Observation
import ScribeConfig
import ScribeCore

/// The default.yaml settings the 方案 and 快捷键 pages edit. One model for
/// both, since both save to default.custom.yaml: a save on one page leaves
/// the other page's unsaved edits in place.
@MainActor @Observable
final class DefaultsModel {
    /// A selected schema. Its node keeps keys besides `schema`, such as `case`.
    struct SchemaItem: Identifiable, Equatable {
        let id = UUID()
        var node: ConfigNode

        var schemaID: String { node.string(at: "schema") ?? "" }

        static func == (lhs: SchemaItem, rhs: SchemaItem) -> Bool {
            lhs.node == rhs.node
        }
    }

    /// The outcome of the last save on a page.
    struct Status: Equatable {
        var message: String
        var isError: Bool
        /// The file to show in Finder after a failure.
        var file: URL?
    }

    enum Page { case schemas, shortcuts }

    let directories: SettingsDirectories
    /// Nil until loaded, or when loading failed.
    private(set) var loaded: RimeDefaults?
    /// Why the values cannot be shown, or nil.
    private(set) var loadError: String?
    /// Why changes cannot be saved, such as a missing Scribe, or nil.
    private(set) var readOnlyReason: String?
    private(set) var catalog: [SchemaInfo] = []
    private(set) var activeSchema: String?
    private(set) var overrides: [SchemaOverride] = []
    private(set) var statuses: [Page: Status] = [:]

    var schemaItems: [SchemaItem] = []
    var pageSize = DefaultsModel.defaultPageSize
    var hotkeys: [String] = []
    var switchKey: [String: String] = [:]

    /// librime's page size when default.yaml sets none.
    static let defaultPageSize = 5
    static let switchKeyNames = ["Shift_L", "Shift_R", "Control_L", "Control_R", "Caps_Lock", "Eisu_toggle"]

    init(directories: SettingsDirectories) {
        self.directories = directories
    }

    // MARK: - Loading

    /// Reads everything from the user directory, keeping the unsaved edits of
    /// `keeping` (the page that did not save).
    func load(keeping page: Page? = nil) {
        let kept = (schemaItems, pageSize, hotkeys, switchKey)
        statuses = statuses.filter { $0.key == page }
        guard let shared = directories.shared else {
            loaded = nil
            loadError = "找不到中书，没法校验修改"
            readOnlyReason = loadError
            emit("Settings load failed: Scribe not found")
            return
        }
        catalog = SchemaCatalog.scan(userDirectory: directories.user, sharedDirectory: shared)
        activeSchema = SchemaCatalog.activeSchema(userDirectory: directories.user)
        do {
            let defaults = try RimeDefaults.load(userDirectory: directories.user, sharedDirectory: shared)
            loaded = defaults
            loadError = nil
            readOnlyReason = defaults.editProblem.map(Self.message(for:))
            schemaItems = defaults.schemaList.listItems.map { SchemaItem(node: $0) }
            pageSize = defaults.pageSize ?? Self.defaultPageSize
            hotkeys = defaults.switcherHotkeys
            switchKey = defaults.switchKey
        } catch {
            loaded = nil
            loadError = Self.message(for: error)
            readOnlyReason = loadError
        }
        switch page {
        case .schemas:
            (schemaItems, pageSize) = (kept.0, kept.1)
        case .shortcuts:
            (hotkeys, switchKey) = (kept.2, kept.3)
        case nil:
            break
        }
        overrides = SchemaCatalog.overrides(for: schemaItems.map(\.schemaID), userDirectory: directories.user)
        emit(loadSummary)
    }

    private var loadSummary: String {
        guard let loaded else { return "Settings load failed: \(loadError ?? "")" }
        return "Settings loaded: schemas \(loaded.schemaIDs.joined(separator: ", "))"
            + "; page size \(loaded.pageSize.map(String.init) ?? "default")"
            + "; hotkeys \(loaded.switcherHotkeys.joined(separator: ", "))"
            + "; switch keys \(loaded.switchKey.count)"
            + "; catalog \(catalog.count) schemas; active \(activeSchema ?? "none"); overrides \(overrides.count)"
            + "; default.custom.yaml \(loaded.customText == nil ? "absent" : "present")"
            + (readOnlyReason.map { "; read-only: \($0)" } ?? "")
            + "; user \(directories.user.path(percentEncoded: false))"
            + "; shared \(directories.shared?.path(percentEncoded: false) ?? "none"); live \(directories.isLive)"
    }

    // MARK: - Edits

    var schemaList: ConfigNode { .list(schemaItems.map(\.node)) }

    func hasEdits(_ page: Page) -> Bool {
        guard let loaded else { return false }
        switch page {
        case .schemas:
            return schemaList != loaded.schemaList || pageSize != (loaded.pageSize ?? Self.defaultPageSize)
        case .shortcuts:
            return hotkeys != loaded.switcherHotkeys || switchKey != loaded.switchKey
        }
    }

    func addSchema(_ id: String) {
        guard !schemaItems.contains(where: { $0.schemaID == id }) else { return }
        schemaItems.append(SchemaItem(node: ["schema": .scalar(id)]))
    }

    func removeSchema(_ item: SchemaItem) {
        guard schemaItems.count > 1 else { return }
        schemaItems.removeAll { $0.id == item.id }
    }

    /// Adds a recorded key; returns why not, if it cannot be added.
    func addHotkey(_ name: String) -> String? {
        guard !hotkeys.contains(name) else { return "\(KeySymbols.display(name)) 已经在列表里了" }
        hotkeys.append(name)
        return nil
    }

    func removeHotkey(_ name: String) {
        guard hotkeys.count > 1 else { return }
        hotkeys.removeAll { $0 == name }
    }

    /// Sets a switch key's action; "noop" for a key the file never had leaves it out.
    func setSwitchKey(_ key: String, to action: String) {
        if action == "noop" && loaded?.switchKey[key] == nil {
            switchKey.removeValue(forKey: key)
        } else {
            switchKey[key] = action
        }
    }

    /// The keys the 中英切换 section lists: the usual ones, then any others.
    var switchKeyRows: [String] {
        Self.switchKeyNames + switchKey.keys.filter { !Self.switchKeyNames.contains($0) }.sorted()
    }

    func name(ofSchema id: String) -> String {
        catalog.first { $0.id == id }?.name ?? id
    }

    // MARK: - Saving

    func revert(_ page: Page) {
        load(keeping: page == .schemas ? .shortcuts : .schemas)
    }

    func save(_ page: Page) {
        guard let loaded, let shared = directories.shared, readOnlyReason == nil else { return }
        var changes: [PatchChange] = []
        switch page {
        case .schemas:
            if schemaList != loaded.schemaList {
                changes.append(.set("schema_list", schemaList))
            }
            if pageSize != (loaded.pageSize ?? Self.defaultPageSize) {
                changes.append(.set("menu/page_size", .scalar(String(pageSize))))
            }
        case .shortcuts:
            if hotkeys != loaded.switcherHotkeys {
                changes.append(.set("switcher/hotkeys", .list(hotkeys.map { .scalar($0) })))
            }
            if switchKey != loaded.switchKey {
                changes.append(.set("ascii_composer/switch_key", .map(switchKey.mapValues { .scalar($0) })))
            }
        }
        guard !changes.isEmpty else { return }

        let writer = CustomPatchWriter(userDirectory: directories.user, sharedDirectory: shared)
        let keys = changes.map { if case .set(let key, _) = $0 { key } else { "" } }
        do {
            let result = try writer.save("default", changes: changes, expectedOriginal: loaded.customText)
            var message: String
            var notified = false
            if !directories.isLive {
                message = "已保存（测试目录，没有通知中书）"
            } else if directories.isScribeRunning {
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name(ServerNotification.reload), object: nil, userInfo: nil, deliverImmediately: true)
                notified = true
                message = "已保存，中书正在重新部署"
            } else {
                message = "已保存，中书下次启动时生效"
            }
            if !result.supersededKeys.isEmpty {
                message += "。合并了 \(result.supersededKeys.joined(separator: "、")) 这几个补丁项"
            }
            emit("Settings saved default.custom.yaml: set \(keys.joined(separator: ", "))"
                 + "; superseded \(result.supersededKeys.joined(separator: ", ")); file \(result.file.path(percentEncoded: false))"
                 + "; posted reload \(notified)")
            load(keeping: page == .schemas ? .shortcuts : .schemas)
            statuses[page] = Status(message: message, isError: false)
        } catch {
            emit("Settings save failed: \(error)")
            statuses[page] = Status(message: Self.message(for: error), isError: true,
                                    file: directories.user.appending(path: "default.custom.yaml").resolvingSymlinksInPath())
        }
    }

    // MARK: - Messages

    static func message(for error: PatchSaveError) -> String {
        switch error {
        case .changedOnDisk:
            "default.custom.yaml 在读取之后被改过了，没有保存。点「还原」重新读取。"
        case .notUTF8:
            "default.custom.yaml 不是 UTF-8 编码，没法安全地修改"
        case .engineBusy:
            "librime 正在忙，稍后再试。"
        case .unsupportedLayout(let line, let reason):
            "default.custom.yaml 第 \(line) 行\(reason.title)，没法安全地修改。"
        case .unreadable:
            "librime 读不了修改后的文件，没有保存。"
        case .unexpectedKeys(let expected, let actual):
            "修改后的补丁项不对：应为 \(expected.joined(separator: "、"))，实际是 \(actual.joined(separator: "、"))。"
        case .topLevelChanged(let key):
            "修改会改到 patch 以外的 \(key)，没有保存。"
        case .deployFailed(let reason):
            "部署检查失败：\(reason)"
        case .notEffective(let key, let expected, let actual):
            "\(key) 部署后不是想要的值：想要 \(expected.summary)，实际是 \(actual.summary)。没有保存。"
        case .writeFailed(let reason):
            "写入失败：\(reason)"
        }
    }

    /// Prints a line to stdout right away and logs it, so a smoke test can follow along.
    private func emit(_ line: String) {
        Log.settings.notice("\(line, privacy: .public)")
        print(line)
        fflush(nil)
    }
}

extension UnsupportedLayout {
    var title: String {
        switch self {
        case .flowPatch: "的 patch 写在一行的花括号里"
        case .tabIndentation: "用了 Tab 缩进"
        case .anchorOrAlias: "用了锚点或别名（& 或 *）"
        case .tag: "用了 ! 标签"
        case .duplicateKey: "的键重复了"
        case .complexKey: "用了 ? 复杂键"
        case .multipleDocuments: "开始了第二个 YAML 文档"
        case .indentedPatch: "的 patch 没有顶格写"
        case .inconsistentIndentation: "的缩进和其他补丁项不一致"
        case .invalidEntry: "不是「键: 值」的写法"
        }
    }
}

extension ConfigNode {
    var listItems: [ConfigNode] {
        if case .list(let items) = self { items } else { [] }
    }

    /// A short, readable rendering for messages.
    var summary: String {
        switch self {
        case .null: "（空）"
        case .scalar(let value): value
        case .list(let items): "[" + items.map(\.summary).joined(separator: ", ") + "]"
        case .map(let map):
            "{" + map.keys.sorted().map { "\($0): \(map[$0]?.summary ?? "")" }.joined(separator: ", ") + "}"
        }
    }
}
