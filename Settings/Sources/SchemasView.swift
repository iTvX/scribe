import SwiftUI
import ScribeConfig

/// 方案: the selected schemas and the page size, saved to default.custom.yaml.
struct SchemasView: View {
    @Bindable var model: DefaultsModel

    var body: some View {
        VStack(spacing: 0) {
            if model.loaded == nil, let error = model.loadError {
                LoadErrorView(message: error)
            } else {
                list
            }
            Divider()
            SaveBar(model: model, page: .schemas)
        }
        .navigationTitle("方案")
    }

    private var editable: Bool {
        model.readOnlyReason == nil
    }

    private var list: some View {
        List {
            Section {
                ForEach(model.schemaItems) { item in
                    row(item)
                }
                .onMove { model.schemaItems.move(fromOffsets: $0, toOffset: $1) }
                .moveDisabled(!editable)
                Menu("添加方案") {
                    ForEach(model.catalog.filter { schema in !model.schemaItems.contains { $0.schemaID == schema.id } }) { schema in
                        Button("\(schema.name)（\(schema.id)）") { model.addSchema(schema.id) }
                    }
                }
                .fixedSize()
                .disabled(!editable)
            } header: {
                Text("已选的方案")
            } footer: {
                Text("拖动调整顺序，排在第一个的是默认方案。至少要留一个。")
                    .foregroundStyle(.secondary)
            }

            Section("候选") {
                Stepper(value: $model.pageSize, in: 1...10) {
                    Text(verbatim: "每页候选数：\(model.pageSize)")
                }
                .disabled(!editable)
                ForEach(pageSizeNotes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ item: DefaultsModel.SchemaItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: model.name(ofSchema: item.schemaID))
                Text(verbatim: item.schemaID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if item.id == model.schemaItems.first?.id {
                badge("默认")
            }
            if item.schemaID == model.activeSchema {
                badge("当前")
            }
            Spacer()
            Button {
                model.removeSchema(item)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("移除")
            .disabled(!editable || model.schemaItems.count <= 1)
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }

    private var pageSizeNotes: [String] {
        model.overrides.compactMap { override in
            guard let size = override.pageSize, model.schemaItems.contains(where: { $0.schemaID == override.schemaID })
            else { return nil }
            return "\(model.name(ofSchema: override.schemaID)) 自己设了每页 \(size) 个"
        }
    }
}
