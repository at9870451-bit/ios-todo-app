import SwiftUI

/// 智能体管理（本地）：模板列表 + 编辑，供「新建好友」导入
struct AgentListView: View {
    @ObservedObject private var store = AgentStore.shared
    @State private var editing: AgentTemplate?
    @State private var showEditor = false

    var body: some View {
        ZStack {
            AppBackground()
            List {
                Section {
                    ForEach(store.templates) { t in
                        Button {
                            editing = t
                            showEditor = true
                        } label: {
                            HStack(spacing: 12) {
                                SquircleIcon(system: t.builtin ? "sparkles" : "person.crop.circle.badge.plus", size: 40, tinted: true)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(t.name).font(.subheadline.weight(.semibold))
                                        if t.builtin {
                                            Text("内置").font(.caption2).foregroundStyle(.secondary)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(.quaternary, in: Capsule())
                                        }
                                    }
                                    Text(t.desc.isEmpty ? t.persona.prefix(40).description : t.desc)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { t.enabled },
                                    set: { v in var m = t; m.enabled = v; store.upsert(m) }
                                )).labelsHidden()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("本地智能体模板 · 新建好友时可导入")
                } footer: {
                    Text("模板只保存在本机。开启后可在「新建好友 → 从智能体导入」一键创建带人设的好友。")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("智能体")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = AgentTemplate(sort: (store.templates.map(\.sort).max() ?? 0) + 1)
                    showEditor = true
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                AgentEditorView(template: editing ?? AgentTemplate()) { t in
                    store.upsert(t)
                }
            }
            .presentationDetents([.large])
        }
    }
}

/// 模板编辑器
struct AgentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let template: AgentTemplate
    let onSave: (AgentTemplate) -> Void

    @State private var name = ""
    @State private var desc = ""
    @State private var persona = ""
    @State private var gender = ""
    @State private var age = ""
    @State private var voiceEngine = ""
    @State private var voiceId = ""
    @State private var modelHint = ""
    @State private var sort = 0
    @State private var enabled = true

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("名称（如：温柔姐姐）", text: $name)
                TextField("一句话描述", text: $desc)
                TextField("推荐模型（可选，如 deepseek-chat）", text: $modelHint)
            }
            Section("人设提示词") {
                TextEditor(text: $persona)
                    .frame(minHeight: 110)
                    .font(.subheadline)
            }
            Section("属性") {
                Picker("性别", selection: $gender) {
                    Text("不指定").tag("")
                    Text("男性").tag("male")
                    Text("女性").tag("female")
                }
                TextField("年龄", text: $age)
                    .keyboardType(.numberPad)
                Picker("语音引擎", selection: $voiceEngine) {
                    Text("跟随全局").tag("")
                    Text("本地系统语音").tag("local")
                    Text("开源语音库").tag("server")
                    Text("硅基流动").tag("cloud_sf")
                    Text("豆包").tag("cloud_doubao")
                }
                TextField("音色 ID（可选）", text: $voiceId)
                Stepper("排序：\(sort)", value: $sort, in: 0...99)
                Toggle("启用", isOn: $enabled)
            }
        }
        .navigationTitle(template.builtin ? "查看模板" : (template.name.isEmpty ? "新建智能体" : "编辑模板"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    var t = template
                    t.name = name.trimmingCharacters(in: .whitespaces)
                    guard !t.name.isEmpty else { return }
                    t.desc = desc; t.persona = persona; t.gender = gender; t.age = age
                    t.voiceEngine = voiceEngine; t.voiceId = voiceId
                    t.modelHint = modelHint; t.sort = sort; t.enabled = enabled
                    t.builtin = false
                    onSave(t)
                    dismiss()
                }
            }
        }
        .onAppear {
            name = template.name; desc = template.desc; persona = template.persona
            gender = template.gender; age = template.age
            voiceEngine = template.voiceEngine; voiceId = template.voiceId
            modelHint = template.modelHint; sort = template.sort; enabled = template.enabled
        }
    }
}
