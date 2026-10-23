import AppKit
import SwiftUI
import ScribeConfig

/// 快捷键: the keys that open the schema menu and the keys that switch
/// between Chinese and English, saved to default.custom.yaml.
struct ShortcutsView: View {
    @Bindable var model: DefaultsModel
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
            if model.loaded == nil, let error = model.loadError {
                LoadErrorView(message: error)
            } else {
                list
            }
            Divider()
            SaveBar(model: model, page: .shortcuts)
        }
        .navigationTitle("快捷键")
        .onDisappear(perform: stopRecording)
    }

    private var editable: Bool {
        model.readOnlyReason == nil
    }

    private var list: some View {
        List {
            Section {
                ForEach(model.hotkeys, id: \.self) { name in
                    HStack {
                        Text(verbatim: KeySymbols.display(name))
                            .font(.body.monospaced())
                            .help(name)
                        Text(verbatim: name)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            model.removeHotkey(name)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("移除")
                        .disabled(!editable || model.hotkeys.count <= 1)
                    }
                }
                HStack {
                    Button(monitor == nil ? "录制" : "请按下按键…（Esc 取消）", action: startRecording)
                        .disabled(!editable || monitor != nil)
                    if let recordingMessage {
                        Text(verbatim: recordingMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("方案菜单")
            } footer: {
                Text("按下其中任何一个键都会打开方案菜单。至少要留一个。")
                    .foregroundStyle(.secondary)
            }

            Section("中英切换") {
                ForEach(model.switchKeyRows, id: \.self) { key in
                    Picker(selection: action(for: key)) {
                        ForEach(options(for: key), id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    } label: {
                        Text(verbatim: KeySymbols.display(key))
                            .help(key)
                    }
                    .disabled(!editable)
                }
                ForEach(switchKeyNotes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
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
    }
}
