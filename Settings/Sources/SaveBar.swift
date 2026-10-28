import AppKit
import SwiftUI

/// The outcome of the last save on a page.
struct SaveStatus: Equatable {
    var message: String
    var isError: Bool
    /// The file to show in Finder after a failure.
    var file: URL?
}

/// The bottom of an editing page: the outcome of the last save, and 还原
/// and 保存.
struct SaveBar: View {
    var status: SaveStatus?
    var readOnlyReason: String?
    var hasEdits: Bool
    var revert: () -> Void
    var save: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let status {
                Label(status.message, systemImage: status.isError ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .foregroundStyle(status.isError ? .red : .secondary)
                    .textSelection(.enabled)
                if status.isError, let file = status.file {
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([file])
                    }
                }
            } else if let readOnlyReason {
                Label(readOnlyReason, systemImage: "lock")
                    .foregroundStyle(.secondary)
            } else if hasEdits {
                Label("有未保存的修改", systemImage: "circle.fill")
                    .font(.callout).foregroundStyle(SettingsStyle.accent)
            } else {
                Text("修改后保存生效").font(.callout).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            Button("撤销修改", action: revert)
                .disabled(!hasEdits)
            Button("保存") {
                NSApp.keyWindow?.makeFirstResponder(nil)
                save()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s")
            .disabled(!hasEdits || readOnlyReason != nil)
        }
        .controlSize(.large)
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(SettingsStyle.card)
    }
}

extension SaveBar {
    init(model: DefaultsModel, page: DefaultsModel.Page) {
        self.init(
            status: model.statuses[page], readOnlyReason: model.readOnlyReason, hasEdits: model.hasEdits(page),
            revert: { model.revert(page) }, save: { model.save(page) })
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
