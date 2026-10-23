import AppKit
import SwiftUI
import ScribeConfig

/// 外观: the candidate window's themes, layout, text and sizes, saved to
/// scribe.custom.yaml. Each control shows the effective value with the
/// pending edits applied, and says where it comes from.
struct LooksView: View {
    var model: LooksModel
    @State private var showingConversion = false

    var body: some View {
        VStack(spacing: 0) {
            if let settings = model.settings, let preview = model.preview {
                Form {
                    if let offer = model.conversionOffer {
                        ConversionBanner(model: model, offer: offer) { showingConversion = true }
                    }
                    if !settings.diagnostics.isEmpty {
                        Section("scribe.custom.yaml 里的问题") {
                            ForEach(settings.diagnostics, id: \.path) { diagnostic in
                                Label(LooksModel.message(for: diagnostic), systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    ThemeSection(model: model, settings: settings)
                    WindowSection(model: model, theme: preview.light)
                    TextSection(model: model, theme: preview.light)
                    SizeSection(model: model, theme: preview.light)
                    PreviewSection(appearance: preview)
                }
                .formStyle(.grouped)
                .disabled(model.readOnlyReason != nil)
            } else if let error = model.loadError {
                LoadErrorView(message: error)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            SaveBar(status: model.status, readOnlyReason: model.readOnlyReason, hasEdits: model.hasEdits,
                    revert: model.revert, save: model.save)
        }
        .navigationTitle("外观")
        .onAppear(perform: model.reloadIfNeeded)
        .sheet(isPresented: $showingConversion) {
            if let offer = model.conversionOffer {
                ConversionSheet(offer: offer, cancel: { showingConversion = false }, convert: {
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
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("鼠须管格式的设置")
                    .font(.headline)
                let files = model.hasUserSquirrelYAML ? "squirrel.yaml 和 squirrel.custom.yaml" : "squirrel.custom.yaml"
                Text(verbatim: "\(files) 里有 \(offer.conversion.entries.count) 项设置，中书照常读取。"
                     + "转换会把它们写进 scribe.custom.yaml，以后都在这里修改。鼠须管的文件不会改动，删掉这些条目就回到原样。")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                content()
                if model.isEdited(path) {
                    Text("已修改")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if model.canReset(path) {
                    Button("恢复默认") { model.reset(path) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            ForEach(model.notes(for: path), id: \.self) { note in
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        Section("主题") {
            SettingRow(model: model, path: "appearance/theme") {
                Picker("浅色主题", selection: Binding(get: { lightID }, set: { model.set("appearance/theme", .scalar($0)) })) {
                    ForEach(options(including: lightID), id: \.id) { theme in
                        Text(verbatim: title(theme)).tag(theme.id)
                    }
                }
                .help(settings.themes.first { $0.id == lightID }?.author ?? "")
            }
            if settings.themes.first(where: { $0.id == lightID })?.hasDark == true {
                Text("这个主题自带深色配色")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingRow(model: model, path: "appearance/dark_theme") {
                Picker("深色主题", selection: Binding(get: { darkID }, set: { id in
                    if id.isEmpty {
                        model.reset("appearance/dark_theme")
                    } else {
                        model.set("appearance/dark_theme", .scalar(id))
                    }
                })) {
                    Text("跟随浅色主题").tag("")
                    ForEach(options(including: darkID), id: \.id) { theme in
                        Text(verbatim: title(theme)).tag(theme.id)
                    }
                }
                .help(settings.themes.first { $0.id == darkID }?.author ?? "")
            }
        }
    }

    /// The listed themes, plus the current one if the list lacks it.
    private func options(including id: String) -> [ThemeInfo] {
        guard !id.isEmpty, !settings.themes.contains(where: { $0.id == id }) else { return settings.themes }
        return settings.themes + [ThemeInfo(id: id, name: nil, author: nil, hasDark: false, origin: .squirrel)]
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
        Section("候选窗") {
            SettingRow(model: model, path: "appearance/layout") {
                Picker("候选排列", selection: Binding(get: { theme.layout }, set: { model.set("appearance/layout", .scalar($0.rawValue)) })) {
                    Text("竖排").tag(CandidateListLayout.stacked)
                    Text("横排").tag(CandidateListLayout.linear)
                }
            }
            SettingRow(model: model, path: "appearance/orientation") {
                Picker("文字方向", selection: Binding(get: { theme.orientation }, set: { model.set("appearance/orientation", .scalar($0.rawValue)) })) {
                    Text("横写").tag(TextOrientation.horizontal)
                    Text("竖写").tag(TextOrientation.vertical)
                }
            }
            SettingRow(model: model, path: "appearance/status_message") {
                Picker("状态提示", selection: Binding(get: { theme.statusMessageType }, set: { model.set("appearance/status_message", .scalar($0.rawValue)) })) {
                    Text("完整").tag(StatusMessageType.long)
                    Text("简短").tag(StatusMessageType.short)
                    Text("混合").tag(StatusMessageType.mix)
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
            Toggle(title, isOn: Binding(get: { value }, set: { model.set(path, AppearanceEdits.flag($0)) }))
        }
    }
}

private struct TextSection: View {
    var model: LooksModel
    var theme: Theme

    var body: some View {
        Section("文字") {
            SettingRow(model: model, path: "appearance/font/face") {
                CommitField(title: "候选字体", value: FontFace.squirrelString(theme.candidateFont.faces), prompt: "系统字体") { text in
                    model.set("appearance/font/face", .scalar(FontFace.squirrelString(FontFace.list(squirrel: text))))
                }
            }
            sizeRow("候选字号", "appearance/font/size", theme.candidateFont.pointSize)
            sizeRow("序号字号", "appearance/label_font/size", theme.labelFont.pointSize)
            sizeRow("注释字号", "appearance/comment_font/size", theme.commentFont.pointSize)
            SettingRow(model: model, path: "appearance/candidate_format") {
                CommitField(title: "候选格式", value: theme.candidateFormat.template, prompt: "[label]. [candidate] [comment]") { text in
                    model.set("appearance/candidate_format", .scalar(text))
                }
            }
        }
    }

    private func sizeRow(_ title: String, _ path: String, _ size: Double?) -> some View {
        SettingRow(model: model, path: path) {
            NumberField(title: title, value: size ?? NSFont.systemFontSize, range: 1...200) { model.set(path, AppearanceEdits.number($0)) }
        }
    }
}

private struct SizeSection: View {
    var model: LooksModel
    var theme: Theme

    var body: some View {
        Section("尺寸") {
            row("圆角", "appearance/corner_radius", theme.cornerRadius)
            row("高亮圆角", "appearance/highlight_corner_radius", theme.hilitedCornerRadius)
            row("行距", "appearance/line_spacing", theme.lineSpacing)
            row("编码与候选的间距", "appearance/preedit_spacing", theme.spacing)
            row("水平内边距", "appearance/padding/horizontal", theme.borderWidth, range: -100...100)
            row("垂直内边距", "appearance/padding/vertical", theme.borderHeight, range: -100...100)
            row("阴影", "appearance/shadow_size", theme.shadowSize)
            SettingRow(model: model, path: "appearance/alpha") {
                LabeledContent("不透明度") {
                    HStack {
                        Slider(value: Binding(get: { theme.alpha }, set: { value in
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
            NumberField(title: title, value: value, range: range) { model.set(path, AppearanceEdits.number($0)) }
        }
    }
}

/// A number with a text field and a stepper; the text field commits on Return.
private struct NumberField: View {
    var title: String
    var value: Double
    var range: ClosedRange<Double>
    var commit: (Double) -> Void

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: Binding(get: { value }, set: { commit(min(max($0, range.lowerBound), range.upperBound)) }),
                          format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Stepper(title, value: Binding(get: { value }, set: { commit($0) }), in: range, step: 1)
                    .labelsHidden()
            }
        }
    }
}

/// A text field that commits on Return and follows the value when it changes elsewhere.
private struct CommitField: View {
    var title: String
    var value: String
    var prompt: String
    var commit: (String) -> Void
    @State private var draft = ""

    var body: some View {
        TextField(title, text: $draft, prompt: Text(verbatim: prompt))
            .onSubmit { commit(draft) }
            .onAppear { draft = value }
            .onChange(of: value) { draft = value }
    }
}

/// Swatches of both palettes and the main sizes, with the edits applied.
private struct PreviewSection: View {
    var appearance: Appearance

    var body: some View {
        Section("预览") {
            palette("浅色", appearance.light)
            if let dark = appearance.dark {
                palette("深色", dark)
            } else {
                LabeledContent("深色") {
                    Text("沿用浅色主题")
                        .foregroundStyle(.secondary)
                }
            }
            let theme = appearance.light
            LabeledContent("排列") {
                Text(verbatim: "\(theme.layout == .linear ? "横排" : "竖排") · \(theme.orientation == .vertical ? "竖写" : "横写")")
            }
            LabeledContent("字体") {
                let faces = theme.candidateFont.faces.map(\.name).joined(separator: "、")
                Text(verbatim: "\(faces.isEmpty ? "系统字体" : faces) \(Int((theme.candidateFont.pointSize ?? NSFont.systemFontSize).rounded())) 点")
            }
            LabeledContent("圆角与不透明度") {
                Text(verbatim: "\(Int(theme.cornerRadius.rounded())) · \(String(format: "%.2f", theme.alpha))")
            }
        }
    }

    private func palette(_ title: String, _ theme: Theme) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                if theme.isNative {
                    Text("系统")
                        .foregroundStyle(.secondary)
                }
                ForEach(swatches(theme), id: \.0) { name, color in
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        .overlay(Circle().strokeBorder(.separator))
                        .frame(width: 18, height: 18)
                        .help(name)
                }
            }
        }
    }

    private func swatches(_ theme: Theme) -> [(String, ThemeColor)] {
        let colors = theme.colors
        let entries: [(String, ThemeColor?)] = [
            ("背景", colors.background),
            ("高亮背景", colors.hilitedCandidateBackground),
            ("编码", colors.text),
            ("候选", colors.candidateText),
            ("高亮候选", colors.hilitedCandidateText),
            ("序号", colors.label),
            ("注释", colors.commentText),
        ]
        return entries.compactMap { name, color in color.map { (name, $0) } }
    }
}

extension ThemeColor {
    /// The colour for a swatch.
    var nsColor: NSColor {
        switch self {
        case .rgba(let color):
            let components = (color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
            return color.colorSpace == .displayP3
                ? NSColor(displayP3Red: components.0, green: components.1, blue: components.2, alpha: components.3)
                : NSColor(srgbRed: components.0, green: components.1, blue: components.2, alpha: components.3)
        case .system(let color):
            switch color {
            case .windowBackground: return .windowBackgroundColor
            case .label: return .labelColor
            case .secondaryLabel: return .secondaryLabelColor
            case .selectedTextBackground: return .selectedTextBackgroundColor
            case .gray: return .gray
            }
        case .blend(let foreground, let background):
            guard let front = foreground.nsColor.usingColorSpace(.deviceRGB),
                  let back = background.nsColor.usingColorSpace(.deviceRGB)
            else { return foreground.nsColor }
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { (2 * a + b) / 3 }
            return NSColor(deviceRed: mix(front.redComponent, back.redComponent),
                           green: mix(front.greenComponent, back.greenComponent),
                           blue: mix(front.blueComponent, back.blueComponent),
                           alpha: mix(front.alphaComponent, back.alphaComponent))
        }
    }
}
