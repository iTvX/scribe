import AppKit
import ScribeConfig
import SwiftUI

/// 外观: the candidate window's themes, layout, text and sizes, saved to
/// scribe.custom.yaml. Each control shows the effective value with the
/// pending edits applied, and says where it comes from.
struct LooksView: View {
    var model: LooksModel
    @State private var showingConversion = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: "外观", subtitle: "选一个喜欢的主题，或把细节调成自己的样子。")
            if let settings = model.settings, let preview = model.preview {
                AppearancePreview(appearance: preview)
                    .padding(.horizontal, 28).padding(.bottom, 18)
                SettingsScroll {
                    if !settings.diagnostics.isEmpty {
                        SettingsCard(title: "有设置需要检查", icon: "exclamationmark.triangle") {
                            ForEach(settings.diagnostics, id: \.path) { diagnostic in
                                Text(LooksModel.message(for: diagnostic)).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                            }
                        }
                    }
                    ThemeSection(model: model, settings: settings)
                    WindowSection(model: model, theme: preview.light)
                    TextSection(model: model, theme: preview.light)
                    SizeSection(model: model, theme: preview.light)
                    if let offer = model.conversionOffer {
                        ConversionBanner(model: model, offer: offer) { showingConversion = true }
                    }
                }
                .disabled(model.readOnlyReason != nil)
            } else if let error = model.loadError {
                LoadErrorView(message: error)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            SaveBar(
                status: model.status, readOnlyReason: model.readOnlyReason, hasEdits: model.hasEdits,
                revert: model.revert, save: model.save)
        }
        .onAppear(perform: model.reloadIfNeeded)
        .sheet(isPresented: $showingConversion) {
            if let offer = model.conversionOffer {
                ConversionSheet(
                    offer: offer, cancel: { showingConversion = false },
                    convert: {
                        showingConversion = false
                        model.convert()
                    })
            }
        }
    }
}

/// The offer at the top of the page while settings are in Squirrel's format.
private struct ConversionBanner: View {
    var model: LooksModel
    var offer: ConversionOffer
    var open: () -> Void

    var body: some View {
        SettingsDisclosure(title: "兼容与配置转换", subtitle: "已导入的鼠须管设置可继续使用，也可转换为中书格式") {
            VStack(alignment: .leading, spacing: 8) {
                Text("鼠须管格式的设置")
                    .font(.headline)
                let files = model.hasUserSquirrelYAML ? "squirrel.yaml 和 squirrel.custom.yaml" : "squirrel.custom.yaml"
                Text(
                    verbatim: "\(files) 里有 \(offer.conversion.entries.count) 项设置，中书照常读取。"
                        + "转换会把它们写进 scribe.custom.yaml，以后都在这里修改。鼠须管的文件不会改动，删掉这些条目就回到原样。"
                )
                .fixedSize(horizontal: false, vertical: true)
                Button("查看并转换…", action: open)
                    .disabled(model.conversionUnavailableReason != nil)
                    .help(model.conversionUnavailableReason ?? "")
            }
            .padding(.vertical, 4)
        }
    }
}

/// What the conversion writes, before it writes it.
private struct ConversionSheet: View {
    var offer: ConversionOffer
    var cancel: () -> Void
    var convert: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("转换成中书的格式")
                .font(.title2)
            List {
                ForEach(offer.sections) { section in
                    Section(section.group.title) {
                        ForEach(section.rows) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                LabeledContent {
                                    Text(verbatim: row.value)
                                        .textSelection(.enabled)
                                } label: {
                                    Text(verbatim: row.path)
                                        .font(.callout.monospaced())
                                }
                                if let note = row.note {
                                    Text(verbatim: note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !offer.unconverted.isEmpty {
                    Section("仍由鼠须管的文件决定") {
                        ForEach(offer.unconverted, id: \.self) { path in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: path)
                                    .font(.callout.monospaced())
                                Text("中书的格式没法写“不设置”，保留鼠须管的文件它就照常生效")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Text("转换后 scribe.custom.yaml 优先。之后再改 squirrel.custom.yaml 里的同一项不会生效，请在这里改。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("取消", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("转换", action: convert)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 520)
    }
}

/// One setting with its markers: edited, 恢复默认, and the notes that say
/// where its value comes from or why an edit may not show.
private struct SettingRow<Content: View>: View {
    var model: LooksModel
    var path: String
    @ViewBuilder var content: () -> Content
    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            content().frame(maxWidth: .infinity)
            if model.isEdited(path) || model.canReset(path) || !model.notes(for: path).isEmpty {
                HStack(spacing: 9) {
                    if model.isEdited(path) { SettingsBadge(title: "已修改", accent: true) }
                    if !model.notes(for: path).isEmpty {
                        Button {
                            showingDetails.toggle()
                        } label: {
                            Label("配置来源", systemImage: "info.circle").font(.caption)
                        }.buttonStyle(.link).foregroundStyle(.secondary)
                            .popover(isPresented: $showingDetails) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("这项设置由哪里决定").font(.headline)
                                    ForEach(model.notes(for: path), id: \.self) { Text($0).font(.callout) }
                                    if model.canPersonalize { Text("在主题卡片中选择“自定义外观”，即可调整当前主题。").font(.callout).foregroundStyle(.secondary) }
                                }.padding(18).frame(width: 320)
                            }
                    }
                    if model.canReset(path) {
                        Button("恢复默认") { model.reset(path) }.buttonStyle(.link).font(.caption)
                    }
                    Spacer()
                }
            }
        }
    }
}

private struct ThemeSection: View {
    var model: LooksModel
    var settings: AppearanceSettings

    var body: some View {
        let lightID = model.value(at: "appearance/theme") ?? "native"
        let darkID = model.value(at: "appearance/dark_theme") ?? ""
        SettingsCard(title: "主题配色", icon: "paintpalette") {
            SettingRow(model: model, path: "appearance/theme") {
                SettingsFieldRow(title: "浅色主题") {
                    Picker("浅色主题", selection: Binding(get: { lightID }, set: { model.set("appearance/theme", .scalar($0)) })) {
                        ForEach(options(including: lightID), id: \.id) { theme in
                            Text(verbatim: title(theme)).tag(theme.id)
                        }
                    }
                    .labelsHidden().frame(width: 220)
                    .help(model.availableThemes.first { $0.id == lightID }?.author ?? "")
                }
            }
            if model.availableThemes.first(where: { $0.id == lightID })?.hasDark == true {
                Text("这个主题自带深色配色")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingRow(model: model, path: "appearance/dark_theme") {
                SettingsFieldRow(title: "深色主题") {
                    Picker(
                        "深色主题",
                        selection: Binding(
                            get: { darkID },
                            set: { id in
                                if id.isEmpty {
                                    model.reset("appearance/dark_theme")
                                } else {
                                    model.set("appearance/dark_theme", .scalar(id))
                                }
                            })
                    ) {
                        Text("跟随浅色主题").tag("")
                        ForEach(options(including: darkID), id: \.id) { theme in
                            Text(verbatim: title(theme)).tag(theme.id)
                        }
                    }
                    .labelsHidden().frame(width: 220)
                    .help(model.availableThemes.first { $0.id == darkID }?.author ?? "")
                }
            }
            Divider()
            if model.canPersonalize || model.isPersonalized {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.isPersonalized ? "正在自定义外观" : "喜欢配色，想调整细节？").font(.callout.weight(.medium))
                        Text(model.isPersonalized ? "调整字体、排列与间距，原主题仍然保留。" : "创建主题副本后，字体、排列和间距都能自由调整。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    if model.canPersonalize { Button("自定义外观", action: model.personalize) }
                }
            } else if !settings.schemaChoosesTheme {
                SettingsHint(text: "系统配色随 macOS 显示，下方的字体和布局可直接调整。")
            }
            if settings.schemaChoosesTheme {
                SettingsHint(text: "当前输入方案指定了主题。请在该方案的配置中修改，通用主题不会覆盖它。")
            }
        }
    }

    /// The listed themes, plus the current one if the list lacks it.
    private func options(including id: String) -> [ThemeInfo] {
        guard !id.isEmpty, !model.availableThemes.contains(where: { $0.id == id }) else { return model.availableThemes }
        return model.availableThemes + [ThemeInfo(id: id, name: nil, author: nil, hasDark: false, origin: .squirrel)]
    }

    private func title(_ theme: ThemeInfo) -> String {
        if case .native = theme.origin {
            return "系统"
        }
        return theme.name ?? theme.id
    }
}

private struct WindowSection: View {
    var model: LooksModel
    var theme: Theme

    var body: some View {
        SettingsCard(title: "排列与显示", icon: "rectangle.3.group") {
            SettingRow(model: model, path: "appearance/layout") {
                SettingsFieldRow(title: "候选排列") {
                    Picker("候选排列", selection: Binding(get: { theme.layout }, set: { model.set("appearance/layout", .scalar($0.rawValue)) }))
                    {
                        Text("纵向排列").tag(CandidateListLayout.stacked)
                        Text("横向排列").tag(CandidateListLayout.linear)
                    }.labelsHidden().frame(width: 180)
                }
            }
            SettingRow(model: model, path: "appearance/orientation") {
                SettingsFieldRow(title: "文字方向") {
                    Picker(
                        "文字方向",
                        selection: Binding(get: { theme.orientation }, set: { model.set("appearance/orientation", .scalar($0.rawValue)) })
                    ) {
                        Text("横写").tag(TextOrientation.horizontal)
                        Text("竖写").tag(TextOrientation.vertical)
                    }.labelsHidden().frame(width: 180)
                }
            }
            SettingRow(model: model, path: "appearance/status_message") {
                SettingsFieldRow(title: "状态提示") {
                    Picker(
                        "状态提示",
                        selection: Binding(
                            get: { theme.statusMessageType }, set: { model.set("appearance/status_message", .scalar($0.rawValue)) })
                    ) {
                        Text("完整").tag(StatusMessageType.long)
                        Text("简短").tag(StatusMessageType.short)
                        Text("混合").tag(StatusMessageType.mix)
                    }.labelsHidden().frame(width: 180)
                }
            }
            toggle("在输入框里显示编码", "appearance/inline_preedit", theme.inlinePreedit)
            toggle("在输入框里显示候选", "appearance/inline_candidate", theme.inlineCandidate)
            toggle("半透明", "appearance/translucency", theme.translucency)
            toggle("显示翻页按钮", "appearance/show_paging", theme.showPaging)
            toggle("记住候选窗大小", "appearance/memorize_size", theme.memorizeSize)
        }
    }

    private func toggle(_ title: String, _ path: String, _ value: Bool) -> some View {
        SettingRow(model: model, path: path) {
            SettingsFieldRow(title: title) {
                Toggle(title, isOn: Binding(get: { value }, set: { model.set(path, AppearanceEdits.flag($0)) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini).accessibilityLabel(title)
            }
        }
    }
}

private struct TextSection: View {
    var model: LooksModel
    var theme: Theme

    var body: some View {
        SettingsCard(title: "字体与文字", icon: "textformat") {
            SettingRow(model: model, path: "appearance/font/face") {
                CommitField(model: model, path: "appearance/font/face", title: "候选字体", value: FontFace.squirrelString(theme.candidateFont.faces), prompt: "系统字体")
            }
            sizeRow("候选字号", "appearance/font/size", theme.candidateFont.pointSize)
            sizeRow("序号字号", "appearance/label_font/size", theme.labelFont.pointSize)
            sizeRow("注释字号", "appearance/comment_font/size", theme.commentFont.pointSize)
            SettingRow(model: model, path: "appearance/candidate_format") {
                CommitField(model: model, path: "appearance/candidate_format", title: "候选格式", value: theme.candidateFormat.template, prompt: "[label]. [candidate] [comment]")
            }
        }
    }

    private func sizeRow(_ title: String, _ path: String, _ size: Double?) -> some View {
        SettingRow(model: model, path: path) {
            NumberField(model: model, path: path, title: title, value: size ?? NSFont.systemFontSize, range: 1...200)
        }
    }
}

private struct SizeSection: View {
    var model: LooksModel
    var theme: Theme

    var body: some View {
        SettingsDisclosure(title: "间距与细节", subtitle: "圆角、内边距、阴影和透明度") {
            row("圆角", "appearance/corner_radius", theme.cornerRadius)
            row("高亮圆角", "appearance/highlight_corner_radius", theme.hilitedCornerRadius)
            row("行距", "appearance/line_spacing", theme.lineSpacing)
            row("编码与候选的间距", "appearance/preedit_spacing", theme.spacing)
            row("水平内边距", "appearance/padding/horizontal", theme.borderWidth, range: -100...100)
            row("垂直内边距", "appearance/padding/vertical", theme.borderHeight, range: -100...100)
            row("阴影", "appearance/shadow_size", theme.shadowSize)
            SettingRow(model: model, path: "appearance/alpha") {
                SettingsFieldRow(title: "不透明度") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { theme.alpha },
                                set: { value in
                                    model.set("appearance/alpha", AppearanceEdits.number((value * 100).rounded() / 100))
                                }), in: 0...1)
                        Text(verbatim: String(format: "%.2f", theme.alpha))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func row(_ title: String, _ path: String, _ value: Double, range: ClosedRange<Double> = 0...100) -> some View {
        SettingRow(model: model, path: path) {
            NumberField(model: model, path: path, title: title, value: value, range: range)
        }
    }
}

/// Raw text is kept in the model, including incomplete or invalid input.
private struct NumberField: View {
    var model: LooksModel
    var path: String
    var title: String
    var value: Double
    var range: ClosedRange<Double>

    var body: some View {
        SettingsFieldRow(title: title) {
            HStack(spacing: 4) {
                TextField(title, text: Binding(
                    get: { model.fieldDrafts[path]?.text ?? value.formatted(.number.precision(.fractionLength(0...2))) },
                    set: { text in
                        let displayed = model.fieldDrafts[path]?.text ?? value.formatted(.number.precision(.fractionLength(0...2)))
                        if text != displayed { model.setField(path, text: text, range: range) }
                    }))
                    .labelsHidden().accessibilityLabel(title)
                    .multilineTextAlignment(.trailing).frame(width: 70)
                    .help(model.fieldDrafts[path]?.isValid == false ? "请输入范围内的完整数字" : "")
                Stepper(title, value: Binding(get: { value }, set: {
                    model.setField(path, text: $0.formatted(.number), range: range)
                }), in: range, step: 1)
                    .labelsHidden().accessibilityLabel("调整\(title)")
            }.accessibilityElement(children: .contain)
        }
    }
}

private struct CommitField: View {
    var model: LooksModel
    var path: String
    var title: String
    var value: String
    var prompt: String

    var body: some View {
        SettingsFieldRow(title: title) {
            TextField(title, text: Binding(
                get: { model.fieldDrafts[path]?.text ?? value },
                set: { text in
                    if text != (model.fieldDrafts[path]?.text ?? value) { model.setField(path, text: text) }
                }), prompt: Text(verbatim: prompt))
                .textFieldStyle(.roundedBorder).labelsHidden().frame(width: 220)
                .accessibilityLabel(title)
        }
    }
}
