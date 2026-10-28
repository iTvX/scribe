import AppKit
import ScribeConfig
import SwiftUI

/// What an import did, grouped by how Scribe uses each file.
struct MigrationReportView: View {
    let report: MigrationReport
    let userWords: UserWordsOutcome
    var onDone: () -> Void

    var body: some View {
        SettingsScroll {
            SettingsCard(title: "导入完成", icon: "checkmark.circle") {
                Text("已导入 \(report.imported.count) 个文件")
                    .font(.system(size: 21, weight: .semibold))
                DisclosureGroup("查看来源与目标目录") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("来源：\(report.source.displayPath)")
                        Text("目标：\(report.destination.displayPath)")
                    }.font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let backup = report.backup {
                    SettingsFieldRow(title: "原配置已备份") {
                        HStack {
                            Text(backup.lastPathComponent)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle).help(backup.displayPath)
                                .textSelection(.enabled)
                            Button("在访达中显示") {
                                NSWorkspace.shared.activateFileViewerSelecting([backup])
                            }
                        }
                    }
                }
            }

            itemSection("原样生效", effect: .asIs)
            itemSection("通过鼠须管兼容层生效", effect: .squirrelCompatibility)
            itemSection("已复制，中书不读取", effect: .notRead)

            SettingsDisclosure(title: "需要留意", subtitle: "\(report.notices.count) 条说明") {
                if report.notices.isEmpty {
                    Text("没有")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(report.notices.enumerated()), id: \.offset) { _, notice in
                    NoticeRow(notice: notice)
                }
            }

            SettingsCard(title: "用户词", icon: "text.bubble") {
                LabeledContent("用户词库") {
                    Text(
                        report.userDictionaries.dictionaries.isEmpty
                            ? "没有"
                            : report.userDictionaries.dictionaries.joined(separator: "、"))
                }
                if !userWords.merged.isEmpty {
                    LabeledContent("已合并") {
                        Label(userWords.merged.joined(separator: "、"), systemImage: "checkmark.circle")
                    }
                }
                if let staging = userWords.staging {
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Label(userWords.syncState.title, systemImage: userWords.syncState == .merged ? "checkmark.circle" : "clock")
                            Text(staging.folder.displayPath)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    } label: {
                        Text(verbatim: "中书同步时合并：\(userWords.staged.joined(separator: "、"))")
                    }
                }
                ForEach(userWords.failed.keys.sorted(), id: \.self) { name in
                    LabeledContent {
                        Text(userWords.failed[name] ?? "")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    } label: {
                        Text(verbatim: "失败：\(name)")
                    }
                }
            }

            SettingsDisclosure(title: "未复制的文件", subtitle: "\(report.skipped.count) 项，查看原因") {
                if report.skipped.isEmpty {
                    Text("没有")
                        .foregroundStyle(.secondary)
                }
                ForEach(report.skipped, id: \.path) { item in
                    LabeledContent(item.path) {
                        Text(item.reason.title)
                    }
                }
            }

            SettingsDisclosure(title: "安装与同步信息", subtitle: "安装标识、同步目录及迁移说明") {
                LabeledContent("中书的安装 ID") {
                    Text(report.installationID)
                        .textSelection(.enabled)
                }
                LabeledContent("鼠须管的安装 ID") {
                    Text(report.squirrelInstallationID ?? "没有")
                        .textSelection(.enabled)
                }
                LabeledContent("同步目录") {
                    Text(report.syncDirectory.map { "沿用 \($0)" } ?? "默认（中书目录里的 sync 文件夹）")
                        .textSelection(.enabled)
                }
                Text("installation.yaml 已重新生成，librime 首次部署时补全其余字段。")
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("导入结果已列出，原始文件保持不变。").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("完成", action: onDone).buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(20).background(SettingsStyle.card)
        }
    }

    @ViewBuilder
    private func itemSection(_ title: String, effect: ImportEffect) -> some View {
        let groups = ImportedFileKind.allCases.compactMap { kind -> KindGroup? in
            let paths = report.imported.filter { $0.kind == kind && $0.effect == effect }.map(\.path)
            return paths.isEmpty ? nil : KindGroup(kind: kind, paths: paths)
        }
        if !groups.isEmpty {
            SettingsDisclosure(title: title, subtitle: "\(groups.reduce(0) { $0 + $1.paths.count }) 个文件，按类型查看") {
                ForEach(groups) { group in
                    DisclosureGroup {
                        ForEach(group.paths, id: \.self) { path in
                            Text(path)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                    } label: {
                        LabeledContent(group.kind.title) {
                            Text(verbatim: "\(group.paths.count)")
                        }
                    }
                }
            }
        }
    }
}

private struct KindGroup: Identifiable {
    var kind: ImportedFileKind
    var paths: [String]

    var id: ImportedFileKind { kind }
}

private struct NoticeRow: View {
    let notice: MigrationNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch notice {
            case .luaChecksFrontend(let file, let line, let text):
                Text(verbatim: "\(file) 第 \(line) 行按前端名称判断，这段脚本在中书里可能走另一条分支。")
                Text(text)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            case .otherFrontendConfig(let file):
                Text(verbatim: "\(file) 是其他输入法前端（小狼毫、仓输入法等）的配置，已复制，中书不读取。")
            case .symbolicLink(let path, let target):
                Text(verbatim: "\(path) 指向 \(target)，链接失效或形成循环，已跳过。请检查来源后重新导入。")
            case .copiedSymbolicLink(let path, let target):
                Text(verbatim: "\(path) 原来指向 \(target)，已复制为独立内容；中书里的修改不会写回原位置。")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension ImportedFileKind {
    var title: String {
        switch self {
        case .schema: "输入方案"
        case .dictionary: "词库"
        case .customPatch: "补丁"
        case .squirrelConfig: "鼠须管配置"
        case .otherFrontendConfig: "其他前端的配置"
        case .sharedConfig: "共用配置"
        case .installation: "安装信息"
        case .lua: "Lua 脚本"
        case .opencc: "OpenCC 数据"
        case .customPhrase: "自定义短语"
        case .languageModel: "语言模型"
        case .gitRepository: "Git 仓库"
        case .other: "其他文件"
        }
    }
}

extension SkipReason {
    var title: String {
        switch self {
        case .buildOutput: "部署生成的文件，中书部署时重新生成"
        case .userDictionary: "用户词库，导出后合并进中书词库"
        case .syncDirectory: "同步文件夹"
        case .trash: "librime 替换下来的旧文件"
        case .systemFile: "访达的系统文件"
        case .unavailableLink: "失效或循环的符号链接"
        }
    }
}

extension UserWordsOutcome.SyncState {
    var title: String {
        switch self {
        case .none: ""
        case .nextSync: "中书下次同步时合并"
        case .waiting: "等待中书同步"
        case .merged: "已合并"
        }
    }
}
