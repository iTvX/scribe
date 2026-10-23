import SwiftUI

/// A page that arrives with the settings model.
struct PlaceholderView: View {
    var title: String
    var systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text("这一页会和设置模型一起加入。")
        }
        .navigationTitle(title)
    }
}
