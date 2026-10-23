import AppKit

/// The menu bar item that shows the input mode while one of Scribe's modes
/// is the input source, as Squirrel's status icon does (`status_icon/show`).
@MainActor
final class ModeStatusItem {
    private var item: NSStatusItem?

    var isEnabled = true {
        didSet { refresh() }
    }

    var isScribeCurrent = false {
        didSet { refresh() }
    }

    var title = "中" {
        didSet { item?.button?.title = title }
    }

    private func refresh() {
        guard isEnabled else {
            if let item {
                NSStatusBar.system.removeStatusItem(item)
            }
            item = nil
            return
        }
        if item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            item.button?.toolTip = Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String ?? "Scribe"
            item.button?.title = title
            self.item = item
        }
        item?.isVisible = isScribeCurrent
    }
}
