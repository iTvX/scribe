import AppKit
import ScribeConfig
import SwiftUI

struct SchemasView: View {
    @Bindable var model: DefaultsModel
    @State private var recipe = ""
    @State private var adding = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: "输入方案", subtitle: "选择常用的输入方式，按习惯排列。")
            if model.loaded == nil, let error = model.loadError {
                LoadErrorView(message: error)
            } else {
                SettingsScroll {
                    SettingsCard(title: "常用方案", subtitle: "第一项为默认方案。拖动手柄调整顺序。", icon: "character.book.closed") {
                        VStack(spacing: 0) {
                            ForEach(Array(model.schemaItems.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().padding(.leading, 32) }
                                row(item, index: index)
                                    .draggable(item.id.uuidString)
                                    .dropDestination(for: String.self) { ids, _ in
                                        guard editable, let id = ids.first,
                                            let from = model.schemaItems.firstIndex(where: { $0.id.uuidString == id }),
                                            let to = model.schemaItems.firstIndex(where: { $0.id == item.id }), from != to
                                        else { return false }
                                        model.schemaItems.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                                        return true
                                    }
                            }
                        }
                        Button {
                            adding = true
                        } label: {
                            Label("添加方案", systemImage: "plus")
                        }
                        .disabled(!editable)
                    }
                    SettingsCard(title: "候选数量", icon: "list.number") {
                        HStack {
                            Text("每页显示")
                            Spacer()
                            Picker("每页候选数量", selection: $model.pageSize) {
                                ForEach(1...10, id: \.self) { Text("\($0) 个").tag($0) }
                            }.labelsHidden().frame(width: 100).disabled(!editable)
                        }
                        if !pageSizeNotes.isEmpty {
                            DisclosureGroup("部分方案有自己的候选数量") {
                                ForEach(pageSizeNotes, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                            }.font(.callout)
                        }
                    }
                    if let plum = model.plum {
                        SettingsDisclosure(title: "安装更多方案", subtitle: "使用东风破（plum）安装社区方案") {
                            Text("输入配方，拷贝命令到终端运行。完成后重新部署中书，再添加新方案。")
                                .font(.callout).foregroundStyle(.secondary)
                            TextField("安装配方", text: $recipe, prompt: Text("例如 iDvel/rime-ice:others/recipes/full"))
                                .textFieldStyle(.roundedBorder)
                            HStack(alignment: .top) {
                                Text(plum.command(recipe: recipe)).font(.caption.monospaced()).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button(copied ? "已拷贝" : "拷贝命令") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(plum.command(recipe: recipe), forType: .string)
                                    copied = true
                                }.disabled(recipe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }.padding(12).background(SettingsStyle.canvas, in: RoundedRectangle(cornerRadius: 8))
                            DisclosureGroup("工具位置") { Text(plum.tool.path).font(.caption).textSelection(.enabled) }
                        }
                    }
                }
            }
            Divider()
            SaveBar(model: model, page: .schemas)
        }
        .onChange(of: recipe) { copied = false }
        .sheet(isPresented: $adding) { AddSchemaSheet(model: model) }
    }

    private var editable: Bool { model.readOnlyReason == nil }

    private func row(_ item: DefaultsModel.SchemaItem, index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal").font(.system(size: 11)).foregroundStyle(.tertiary)
                .frame(width: 18).accessibilityLabel("拖动调整方案顺序")
            Text(model.name(ofSchema: item.schemaID)).font(.system(size: 13, weight: .medium))
                .help(item.schemaID)
            if index == 0 { SettingsBadge(title: "默认", accent: true) }
            if item.schemaID == model.activeSchema { SettingsBadge(title: "当前使用") }
            Spacer(minLength: 4)
            Menu {
                Button("设为默认") { move(index, to: 0) }.disabled(index == 0)
                Button("上移") { move(index, to: index - 1) }.disabled(index == 0)
                Button("下移") { move(index, to: index + 1) }.disabled(index == model.schemaItems.count - 1)
                Divider()
                Text(item.schemaID)
                Button("从常用方案中移除", role: .destructive) { model.removeSchema(item) }
                    .disabled(model.schemaItems.count <= 1)
            } label: {
                Image(systemName: "ellipsis").frame(width: 20, height: 20)
            }
            .menuIndicator(.hidden).menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("\(model.name(ofSchema: item.schemaID))的操作")
            .disabled(!editable)
        }
        .padding(.vertical, 13).contentShape(Rectangle())
    }

    private func move(_ from: Int, to: Int) {
        guard editable, model.schemaItems.indices.contains(to) else { return }
        model.schemaItems.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    private var pageSizeNotes: [String] {
        model.overrides.compactMap { override in
            guard let size = override.pageSize, model.schemaItems.contains(where: { $0.schemaID == override.schemaID }) else { return nil }
            return "\(model.name(ofSchema: override.schemaID))：每页 \(size) 个"
        }
    }
}

private struct AddSchemaSheet: View {
    var model: DefaultsModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var available: [SchemaInfo] {
        model.catalog.filter { schema in
            !model.schemaItems.contains { $0.schemaID == schema.id }
                && (query.isEmpty || schema.name.localizedCaseInsensitiveContains(query)
                    || schema.id.localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("添加输入方案").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("搜索已安装的方案", text: $query).textFieldStyle(.roundedBorder)
            if available.isEmpty {
                ContentUnavailableView("没有可添加的方案", systemImage: "magnifyingglass", description: Text("试试其他名称，或在“安装更多方案”中安装。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(available) { schema in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(schema.name)
                            Text(schema.id).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("添加") { model.addSchema(schema.id) }
                    }.padding(.vertical, 6).accessibilityElement(children: .contain)
                }.listStyle(.plain)
            }
        }.padding(24).frame(width: 470, height: 430).tint(SettingsStyle.accent)
    }
}
