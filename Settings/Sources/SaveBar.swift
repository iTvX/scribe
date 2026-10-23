import AppKit
import SwiftUI

/// The bottom of the 方案 and 快捷键 pages: the outcome of the last save,
/// and 还原 and 保存.
struct SaveBar: View {
    var model: DefaultsModel
    var page: DefaultsModel.Page

    var body: some View {
        HStack(spacing: 12) {
            if let status = model.statuses[page] {
                Label(status.message, systemImage: status.isError ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .foregroundStyle(status.isError ? .red : .secondary)
                    .textSelection(.enabled)
                if status.isError, let file = status.file {
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([file])
                    }
                }
            } else if let reason = model.readOnlyReason {
                Label(reason, systemImage: "lock")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("还原") { model.revert(page) }
                .disabled(!model.hasEdits(page))
            Button("保存") { model.save(page) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s")
                .disabled(!model.hasEdits(page) || model.readOnlyReason != nil)
        }
        .padding(12)
        .background(.bar)
    }
}

/// Shown instead of a page that could not load.
struct LoadErrorView: View {
    var message: String

    var body: some View {
        ContentUnavailableView {
            Label("读不到设置", systemImage: "exclamationmark.triangle")
        } description: {
            Text(verbatim: message)
        }
    }
}
