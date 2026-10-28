import AppKit
import ScribeConfig
import ScribeCore
import ScribeUI
import SwiftUI

struct AppearancePreview: View {
    let appearance: Appearance
    @State private var dark = false
    @State private var image: NSImage?
    private var theme: Theme { appearance.theme(isDark: dark) }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("实时预览", systemImage: "eye").font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("预览配色", selection: $dark) {
                    Text("浅色").tag(false)
                    Text("深色").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 124)
            }
            GeometryReader { geometry in
                VStack(spacing: 12) {
                    if theme.inlinePreedit || theme.inlineCandidate {
                        Text(theme.inlineCandidate ? "你好" : "ni hao").underline()
                            .font(.system(size: 15)).foregroundStyle(dark ? .white : .black)
                    }
                    if let image {
                        let scale = min(
                            1, (geometry.size.width - 32) / max(1, image.size.width),
                            (geometry.size.height - 38) / max(1, image.size.height))
                        Image(nsImage: image).resizable()
                            .frame(width: image.size.width * scale, height: image.size.height * scale)
                            .opacity(theme.alpha)
                            .shadow(color: .black.opacity(0.12), radius: min(12, max(2, theme.shadowSize)), y: 2)
                            .accessibilityLabel("候选窗预览：你好、你、拟好")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 100)
            .background(
                dark ? Color(red: 0.14, green: 0.15, blue: 0.17) : Color(red: 0.96, green: 0.95, blue: 0.93),
                in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text("随修改更新，保存后应用到输入法。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(theme.layout == .linear ? "横向排列" : "纵向排列").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(SettingsStyle.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SettingsStyle.line, lineWidth: 1))
        .onChange(of: appearance, initial: true) { render() }
        .onChange(of: dark) { render() }
    }

    private func render() {
        let snapshot = CandidateSnapshot(
            entries: [
                .init(label: "1", text: "你好"), .init(label: "2", text: "你"), .init(label: "3", text: "拟好"),
            ], preedit: theme.inlinePreedit ? nil : Preedit(text: "ni hao", selectedRange: 0..<6, caret: 6))
        image = CandidatePreview.render(snapshot, theme: theme, isDark: dark)
    }
}
