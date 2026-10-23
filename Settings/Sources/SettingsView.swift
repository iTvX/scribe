import SwiftUI

/// The pages in the sidebar.
enum SettingsPage: String, CaseIterable, Identifiable {
    case importing
    case schemas
    case looks
    case shortcuts

    var id: Self { self }

    var title: String {
        switch self {
        case .importing: "导入"
        case .schemas: "方案"
        case .looks: "外观"
        case .shortcuts: "快捷键"
        }
    }

    var systemImage: String {
        switch self {
        case .importing: "square.and.arrow.down"
        case .schemas: "character.book.closed"
        case .looks: "paintpalette"
        case .shortcuts: "keyboard"
        }
    }
}

struct SettingsView: View {
    var model: ImportModel
    @State private var selection: SettingsPage? = .importing

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selection) { page in
                Label(page.title, systemImage: page.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            switch selection ?? .importing {
            case .importing:
                ImportView(model: model)
            case let page:
                PlaceholderView(title: page.title, systemImage: page.systemImage)
            }
        }
        .frame(minWidth: 760, minHeight: 540)
    }
}
