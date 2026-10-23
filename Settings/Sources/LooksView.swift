import AppKit
import SwiftUI
import ScribeConfig

/// 外观: the light and dark themes, read-only until Scribe has its own
/// configuration format.
struct LooksView: View {
    var model: LooksModel

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
            case .unavailable(let message):
                LoadErrorView(message: message)
            case .loaded(let deployed):
                Form {
                    Section {
                        Text("外观修改等中书自己的配置格式完成后开放")
                            .foregroundStyle(.secondary)
                        if let schemaID = model.schemaID {
                            LabeledContent("方案", value: schemaID)
                        }
                    }
                    ThemeSection(title: "浅色", theme: deployed.appearance.light, names: deployed.colorSchemeNames)
                    if let dark = deployed.appearance.dark {
                        ThemeSection(title: "深色", theme: dark, names: deployed.colorSchemeNames)
                    } else {
                        Section("深色") {
                            Text("深色模式沿用浅色主题")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle("外观")
    }
}

private struct ThemeSection: View {
    var title: String
    var theme: Theme
    var names: [String: String]

    var body: some View {
        Section(title) {
            LabeledContent("配色") {
                if theme.isNative {
                    Text("系统")
                } else {
                    let id = theme.colorSchemeID ?? ""
                    Text(verbatim: names[id].map { "\($0)（\(id)）" } ?? id)
                }
            }
            LabeledContent("候选排列", value: theme.layout == .linear ? "横排" : "竖排")
            LabeledContent("文字方向", value: theme.orientation == .vertical ? "竖写" : "横写")
            LabeledContent("候选字体") {
                Text(verbatim: font(theme.candidateFont))
            }
            LabeledContent("序号字体") {
                Text(verbatim: font(theme.labelFont))
            }
            LabeledContent("圆角") {
                Text(verbatim: "\(Int(theme.cornerRadius.rounded()))")
            }
            LabeledContent("颜色") {
                HStack(spacing: 6) {
                    ForEach(swatches, id: \.0) { name, color in
                        Circle()
                            .fill(Color(nsColor: color.nsColor))
                            .overlay(Circle().strokeBorder(.separator))
                            .frame(width: 18, height: 18)
                            .help(name)
                    }
                }
            }
        }
    }

    private var swatches: [(String, ThemeColor)] {
        let colors = theme.colors
        let entries: [(String, ThemeColor?)] = [
            ("背景", colors.background),
            ("文字", colors.text),
            ("候选", colors.candidateText),
            ("高亮背景", colors.hilitedCandidateBackground),
            ("高亮候选", colors.hilitedCandidateText),
            ("序号", colors.label),
            ("注释", colors.commentText),
            ("边框", colors.border),
        ]
        return entries.compactMap { name, color in color.map { (name, $0) } }
    }

    private func font(_ font: ThemeFont) -> String {
        let faces = font.faces.map(\.name).joined(separator: "、")
        let size = font.pointSize.map { " \(Int($0.rounded())) 点" } ?? ""
        return (faces.isEmpty ? "系统字体" : faces) + size
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
