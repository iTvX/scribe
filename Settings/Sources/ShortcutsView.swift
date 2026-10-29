import AppKit
import ScribeConfig
import SwiftUI

/// 快捷键: the keys that open the schema menu and the keys that switch
/// between Chinese and English, saved to default.custom.yaml.
struct ShortcutsView: View {
    @Bindable var model: DefaultsModel
    var session: SettingsSession
    @State private var monitor: Any?
    @State private var recordingMessage: String?

    static let actions: [(String, String)] = [
        ("inline_ascii", "临时英文（编码留在输入框）"),
        ("commit_text", "上屏候选后切英文"),
        ("commit_code", "上屏编码后切英文"),
        ("clear", "清空编码后切英文"),
        ("noop", "不切换"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: "快捷键", subtitle: "切换方案与中英文，让每一次按键符合习惯。")
            if model.loaded == nil, let error = model.loadError {
                LoadErrorView(message: error)
            } else {
                list
            }
            Divider()
            SaveBar(model: model, page: .shortcuts)
        }
        .onDisappear(perform: stopRecording)
    }

    private var editable: Bool {
        model.readOnlyReason == nil
    }

    private var list: some View {
        SettingsScroll {
            SettingsCard(title: "切换输入方案", subtitle: "按下任一快捷键，打开方案菜单。", icon: "command") {
                ForEach(model.hotkeys, id: \.self) { name in
                    HStack {
                        Text(KeySymbols.display(name)).font(.system(.body, design: .monospaced).weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(SettingsStyle.canvas, in: RoundedRectangle(cornerRadius: 6))
                            .help(name)
                        Spacer()
                        Button {
                            model.removeHotkey(name)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .accessibilityLabel("移除快捷键 \(KeySymbols.display(name))")
                        .disabled(!editable || model.hotkeys.count <= 1)
                    }
                }
                HStack {
                    Button {
                        startRecording()
                    } label: {
                        Label(monitor == nil ? "添加快捷键" : "请按下快捷键…", systemImage: monitor == nil ? "plus" : "record.circle")
                    }.disabled(!editable || monitor != nil)
                    if monitor != nil { Button("取消", action: stopRecording).buttonStyle(.link) }
                }
                if let recordingMessage { SettingsHint(text: recordingMessage, icon: "exclamationmark.circle") }
                if monitor != nil { Text("按 Esc 取消录制。").font(.caption).foregroundStyle(.secondary) }
            }
            SettingsCard(title: "中英文切换", subtitle: "选择按下这些键时如何处理正在输入的文字。", icon: "character.cursor.ibeam") {
                ForEach(model.switchKeyRows, id: \.self) { key in
                    HStack {
                        Text(KeySymbols.display(key)).font(.system(.body, design: .monospaced)).help(key)
                        Spacer()
                        Picker("\(KeySymbols.display(key))的操作", selection: action(for: key)) {
                            ForEach(options(for: key), id: \.0) { option in Text(option.1).tag(option.0) }
                        }.labelsHidden().frame(maxWidth: 270).disabled(!editable)
                    }.padding(.vertical, 3)
                }
                if !switchKeyNotes.isEmpty {
                    DisclosureGroup("部分方案有自己的切换设置") {
                        ForEach(switchKeyNotes, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                    }.font(.callout)
                }
            }
            SettingsHint(text: "“上屏”是将拼音或候选文字插入当前输入框。保留至少一个方案切换快捷键。")
        }
    }

    private func action(for key: String) -> Binding<String> {
        Binding(get: { model.switchKey[key] ?? "noop" }, set: { model.setSwitchKey(key, to: $0) })
    }

    /// The five actions, plus whatever else the file has for this key.
    private func options(for key: String) -> [(String, String)] {
        guard let current = model.switchKey[key], !Self.actions.contains(where: { $0.0 == current }) else {
            return Self.actions
        }
        return Self.actions + [(current, current)]
    }

    private var switchKeyNotes: [String] {
        model.overrides.compactMap { override in
            guard override.switchKey != nil, model.schemaItems.contains(where: { $0.schemaID == override.schemaID })
            else { return nil }
            return "\(model.name(ofSchema: override.schemaID)) 自己设了中英切换键"
        }
    }

    // MARK: - Recording

    private func startRecording() {
        recordingMessage = nil
        session.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                record(event)
            }
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if event.keyCode == 53 && modifiers.isEmpty {
            stopRecording()
            return
        }
        guard let name = KeySymbols.rimeName(of: event) else {
            recordingMessage = "这个键不能用：⌘ 组合键或 Rime 不认识的键"
            return
        }
        if let problem = model.addHotkey(name) {
            recordingMessage = problem
        } else {
            recordingMessage = nil
            stopRecording()
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        session.isRecordingShortcut = false
    }
}
