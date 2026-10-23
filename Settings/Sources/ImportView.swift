import SwiftUI
import UniformTypeIdentifiers

/// The first screen: where to import from and to, and the button that does it.
struct ImportView: View {
    @Bindable var model: ImportModel
    @State private var isChoosingSource = false

    var body: some View {
        Group {
            if case .finished(let report) = model.phase {
                MigrationReportView(report: report, onDone: model.reset)
            } else {
                form
            }
        }
        .navigationTitle("导入")
    }

    private var form: some View {
        Form {
            Section {
                LabeledContent("来源") {
                    Text(model.source.displayPath)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("选择其他目录…") { isChoosingSource = true }
                        .disabled(model.isImporting)
                }
                LabeledContent("中书目录") {
                    Text(model.destination.displayPath)
                        .textSelection(.enabled)
                }
            } header: {
                Text("从鼠须管导入")
            } footer: {
                if model.destinationHasContents {
                    Text("中书目录里已有内容，导入前会整个移到旁边的备份文件夹。")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("""
                    方案、词库、补丁、Lua 脚本、OpenCC 数据、squirrel.yaml 和 .git 仓库都会原样复制。\
                    部署生成的 build 文件夹、用户词库、sync 同步文件夹、trash 和 .DS_Store 不复制：\
                    中书部署时会重新生成，用户词通过鼠须管的同步快照合并。\
                    installation.yaml 会重新生成，中书有自己的安装 ID，沿用原来的同步目录。\
                    鼠须管的目录只读不写。
                    """)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                HStack(spacing: 12) {
                    if case .failed(let message) = model.phase {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    if model.isImporting {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在导入…")
                            .foregroundStyle(.secondary)
                    }
                    Button(isFailed ? "重试" : "一键导入", action: model.requestImport)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.isImporting)
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isChoosingSource, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.source = url
            }
        }
        .confirmationDialog("中书目录里已有内容，导入前会整个移到备份文件夹，不会删除",
                            isPresented: $model.isConfirmingBackup, titleVisibility: .visible) {
            Button("移到备份并导入", action: model.startImport)
            Button("取消", role: .cancel) {}
        } message: {
            Text(model.destination.displayPath)
        }
    }

    private var isFailed: Bool {
        if case .failed = model.phase { true } else { false }
    }
}

extension URL {
    /// The path with `~` for the home folder and no trailing slash.
    var displayPath: String {
        var path = (self.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
