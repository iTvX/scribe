import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Bindable var model: ImportModel
    @State private var isChoosingSource = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: "导入配置", subtitle: "把熟悉的输入习惯带到中书。")
            if case .finished(let report) = model.phase {
                MigrationReportView(report: report, userWords: model.userWords, onDone: model.reset)
            } else {
                form
            }
        }
    }

    private var form: some View {
        SettingsScroll {
            SettingsCard(title: "从鼠须管迁移", subtitle: "导入方案、外观和学到的词，继续熟悉的输入方式。", icon: "square.and.arrow.down") {
                HStack(spacing: 14) {
                    Image(systemName: "folder").font(.system(size: 25)).foregroundStyle(SettingsStyle.accent)
                        .frame(width: 50, height: 50).background(SettingsStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("配置来源").font(.callout.weight(.medium))
                        Text(model.source.displayPath).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button("选择目录…") { isChoosingSource = true }.disabled(model.isImporting)
                }
                Divider()
                HStack {
                    Text("导入到中书").font(.callout)
                    Spacer()
                    Text(model.destination.displayPath).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            SettingsCard(title: "原来的配置会保留", icon: "checkmark.shield") {
                SettingsHint(text: "鼠须管目录只读取，不修改。", icon: "checkmark")
                SettingsHint(text: "中书已有配置会先完整备份，再导入新内容。", icon: "checkmark")
                SettingsHint(text: "学到的用户词会合并；个别失败会在导入报告中列出。", icon: "checkmark")
            }
            HStack(spacing: 12) {
                if case .importing(let progress) = model.phase {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.callout).foregroundStyle(.secondary)
                } else if case .failed(let message) = model.phase {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                } else {
                    Text("导入后会显示完整结果。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
                Button(isFailed ? "重新导入" : "开始导入", action: model.requestImport)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction).disabled(model.isImporting)
            }.padding(.vertical, 2)
            SettingsDisclosure(title: "查看导入范围", subtitle: "文件处理、用户词库与同步目录") {
                Text("方案、词库、补丁、Lua 脚本、OpenCC 数据、squirrel.yaml 和 .git 仓库会复制到中书。")
                Text("部署产生的 build、sync、trash 和 .DS_Store 不复制。中书重新部署时生成所需文件。")
                Text("用户词库先从副本导出，再合并进中书；installation.yaml 重新生成，中书使用独立安装 ID，沿用原来的同步目录。")
            }.font(.callout)
        }
        .fileImporter(isPresented: $isChoosingSource, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.source = url }
        }
        .confirmationDialog("备份现有配置并导入？", isPresented: $model.isConfirmingBackup, titleVisibility: .visible) {
            Button("备份并导入", action: model.startImport)
            Button("取消", role: .cancel) {}
        } message: {
            Text("\(model.destination.displayPath) 中的现有内容会完整移到旁边的备份文件夹。鼠须管的原始配置不会改变。")
        }
    }
    private var isFailed: Bool { if case .failed = model.phase { true } else { false } }
}

extension URL {
    var displayPath: String {
        var path = (self.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
