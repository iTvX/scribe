import AppKit
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case schemas, looks, shortcuts, importing
    var id: Self { self }
    var title: String {
        switch self {
        case .schemas: "输入方案"
        case .looks: "外观"
        case .shortcuts: "快捷键"
        case .importing: "导入配置"
        }
    }
    var systemImage: String {
        switch self {
        case .schemas: "character.book.closed"
        case .looks: "paintpalette"
        case .shortcuts: "keyboard"
        case .importing: "square.and.arrow.down"
        }
    }
}

struct SettingsView: View {
    var importModel: ImportModel
    var defaults: DefaultsModel
    var looks: LooksModel
    @State private var selection: SettingsPage = .schemas

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(SettingsStyle.line).frame(width: 1)
            Group {
                switch selection {
                case .schemas: SchemasView(model: defaults)
                case .looks: LooksView(model: looks)
                case .shortcuts: ShortcutsView(model: defaults)
                case .importing: ImportView(model: importModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SettingsStyle.canvas)
        }
        .tint(SettingsStyle.accent)
        .frame(minWidth: 850, minHeight: 620)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(nsImage: NSImage(named: "Scribe") ?? NSImage())
                    .resizable().frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("中书").font(.system(size: 19, weight: .semibold))
                    Text("输入法设置").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 34)
            Text("偏好设置").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                .padding(.horizontal, 24).padding(.bottom, 10)
            VStack(spacing: 5) {
                ForEach(SettingsPage.allCases) { page in
                    Button {
                        selection = page
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: page.systemImage).font(.system(size: 15)).frame(width: 22)
                            Text(page.title).font(.system(size: 13, weight: selection == page ? .semibold : .regular))
                            Spacer(minLength: 0)
                            if hasEdits(page) {
                                Circle().fill(SettingsStyle.accent).frame(width: 5, height: 5)
                                    .accessibilityLabel("有未保存的修改")
                            }
                        }
                        .foregroundStyle(selection == page ? SettingsStyle.accent : Color.primary.opacity(0.8))
                        .padding(.horizontal, 12).padding(.vertical, 12)
                        .background(
                            selection == page ? SettingsStyle.accent.opacity(0.085) : .clear,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == page ? .isSelected : [])
                    .accessibilityIdentifier("settings.page.\(page.rawValue)")
                }
            }.padding(.horizontal, 12)
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Link(destination: URL(string: "https://github.com/iTvX/scribe#readme")!) {
                    Label("使用帮助", systemImage: "questionmark.circle")
                }.font(.callout).foregroundStyle(.secondary)
                Text("中书 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.caption).foregroundStyle(.tertiary)
            }.padding(24)
        }
        .frame(width: 188).frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private func hasEdits(_ page: SettingsPage) -> Bool {
        switch page {
        case .schemas: defaults.hasEdits(.schemas)
        case .shortcuts: defaults.hasEdits(.shortcuts)
        case .looks: looks.hasEdits
        case .importing: false
        }
    }
}
