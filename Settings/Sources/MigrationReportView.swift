import AppKit
import ScribeConfig
import SwiftUI

/// What an import did, grouped by how Scribe uses each file.
struct MigrationReportView: View {
    let report: MigrationReport
    var onDone: () -> Void

    var body: some View {
        Form {
            Section {
                Text(verbatim: "从 \(report.source.displayPath) 导入到 \(report.destination.displayPath)，共 \(report.imported.count) 个文件")
                    .font(.headline)
                    .textSelection(.enabled)
                if let backup = report.backup {
                    LabeledContent("原来的中书目录已移到") {
                        HStack {
                            Text(backup.displayPath)
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

            Section("需要留意") {
                if report.notices.isEmpty {
                    Text("没有")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(report.notices.enumerated()), id: \.offset) { _, notice in
                    NoticeRow(notice: notice)
                }
            }

            Section("用户词") {
                LabeledContent("用户词库") {
                    Text(report.userDictionaries.dictionaries.isEmpty
                         ? "没有"
                         : report.userDictionaries.dictionaries.joined(separator: "、"))
                }
                if report.userDictionaries.snapshots.isEmpty {
                    LabeledContent("同步快照") {
                        Text("没有找到")
                    }
                }
                ForEach(report.userDictionaries.snapshots, id: \.self) { snapshot in
                    LabeledContent {
                        Label("部署后合并进中书词库", systemImage: "clock")
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(snapshot.displayPath)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("未复制") {
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

            Section("同步") {
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
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem {
                Button("完成", action: onDone)
            }
        }
    }

    @ViewBuilder
    private func itemSection(_ title: String, effect: ImportEffect) -> some View {
        let groups = ImportedFileKind.allCases.compactMap { kind -> KindGroup? in
            let paths = report.imported.filter { $0.kind == kind && $0.effect == effect }.map(\.path)
            return paths.isEmpty ? nil : KindGroup(kind: kind, paths: paths)
        }
        if !groups.isEmpty {
            Section(title) {
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
            case .userDictionariesNotSynced(let names):
                Text(verbatim: "有用户词库 \(names.joined(separator: "、"))，但没有找到鼠须管的同步快照。先在鼠须管里“同步用户数据”，再重新导入，才能把用户词带过来。")
            case .symbolicLink(let path, let target):
                Text(verbatim: "\(path) 是符号链接，指向 \(target)。导入时原样复制了链接，它仍然指向原来的位置。")
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
        case .userDictionary: "用户词库，通过同步快照合并"
        case .syncDirectory: "同步文件夹"
        case .trash: "librime 替换下来的旧文件"
        case .systemFile: "访达的系统文件"
        }
    }
}
