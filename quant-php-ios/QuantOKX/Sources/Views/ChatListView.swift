import SwiftUI
import PhotosUI

/// 聊天 Tab：好友列表（微信风格），点好友进入独立聊天
enum ChatRoute: Hashable {
    case friend(String)
    case group(String)
}

struct ChatListView: View {
    @ObservedObject private var fs = FriendStore.shared
    @ObservedObject private var gs = GroupStore.shared
    @State private var path: [ChatRoute] = []
    @State private var editingID: String?
    @State private var newFriend: ChatFriend?
    @State private var creatingGroup = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(gs.groups) { g in
                            Button {
                                Haptics.tap()
                                path.append(.group(g.id))
                            } label: {
                                groupRow(g)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { gs.remove(g.id) } label: { Label("解散群聊", systemImage: "trash") }
                            }
                            Rectangle().fill(Theme.hairline.opacity(0.5)).frame(height: 0.6).padding(.leading, 74)
                        }
                        ForEach(fs.friends) { f in
                            Button {
                                Haptics.tap()
                                path.append(.friend(f.id))
                            } label: {
                                friendRow(f)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { editingID = f.id } label: { Label("编辑人设与语音", systemImage: "slider.horizontal.3") }
                                Button(role: .destructive) { fs.remove(f.id) } label: { Label("删除好友", systemImage: "trash") }
                            }
                            if f.id != fs.friends.last?.id {
                                Rectangle().fill(Theme.hairline.opacity(0.5)).frame(height: 0.6).padding(.leading, 74)
                            }
                        }
                    }
                    .glassPanel(Theme.radiusL)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("聊天")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            var f = ChatFriend()
                            f.name = "好友 \(fs.friends.count + 1)"
                            newFriend = f
                        } label: { Label("新建好友", systemImage: "person.badge.plus") }
                        Button {
                            creatingGroup = true
                        } label: { Label("新建群聊", systemImage: "person.3.fill") }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: ChatRoute.self) { r in
                switch r {
                case .friend(let id): ChatRoomView(friendId: id)
                case .group(let id):  GroupChatView(groupId: id)
                }
            }
            .sheet(isPresented: $creatingGroup) { GroupCreateSheet() }
            .sheet(item: Binding(get: { newFriend }, set: { newFriend = $0 })) { f in
                FriendEditSheet(friendId: nil, draft: f)
            }
            .sheet(item: Binding(get: { editingID.map { Ident(friendId: $0) } }, set: { editingID = $0?.friendId })) { wrap in
                FriendEditSheet(friendId: wrap.friendId, draft: nil)
            }
        }
    }

    private struct Ident: Identifiable { let friendId: String; var id: String { friendId } }

    private func groupRow(_ g: ChatGroup) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accent.opacity(0.16))
                Image(systemName: "person.3.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(g.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text("\(g.memberIds.count) 位 AI")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.ok)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.ok.opacity(0.14), in: Capsule())
                }
                Text(g.lastMessage.isEmpty ? "群聊已创建" : g.lastMessage)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if g.lastAt > 0 {
                    Text(ChatListView.timeText(g.lastAt)).font(.caption2).foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func friendRow(_ f: ChatFriend) -> some View {
        HStack(spacing: 12) {
            ChatAvatar(image: f.avatarImage(), name: f.name, isAI: true, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(f.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if f.gender == "male" || f.gender == "female" {
                        Text(f.gender == "male" ? "男" : "女")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                    }
                }
                Text(f.lastMessage.isEmpty ? "开始聊天吧" : f.lastMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if f.lastAt > 0 {
                    Text(Self.timeText(f.lastAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    static func timeText(_ t: Double) -> String {
        let d = Date(timeIntervalSince1970: t)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(d) {
            f.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(d) {
            return "昨天"
        } else {
            f.dateFormat = "MM/dd"
        }
        return f.string(from: d)
    }
}

/// 好友设置：人设（名称/性别/年龄/提示词）+ 语音 API
struct FriendEditSheet: View {
    let friendId: String?
    let draft: ChatFriend?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var fs = FriendStore.shared

    @State private var name = ""
    @State private var persona = ""
    @State private var gender = ""
    @State private var age = ""
    @State private var voiceEngine = ""
    @State private var voiceId = ""
    @State private var ttsKey = ""
    @State private var aiProviderId = ""
    @State private var item: PhotosPickerItem?
    @State private var loaded = false

    private var isNew: Bool { friendId == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    HStack(spacing: 12) {
                        ChatAvatar(image: currentAvatar, name: name, isAI: true, size: 54)
                        PhotosPicker(selection: $item, matching: .images) {
                            Text("更换头像").font(.subheadline).foregroundStyle(Theme.accent)
                        }
                    }
                    TextField("名字", text: $name)
                    Picker("性别", selection: $gender) {
                        Text("不指定").tag("")
                        Text("男").tag("male")
                        Text("女").tag("female")
                    }
                    TextField("年龄（如 24）", text: $age).keyboardType(.numberPad)
                }

                Section {
                    TextEditor(text: $persona)
                        .frame(minHeight: 120)
                        .font(.subheadline)
                } header: {
                    Text("人设提示词")
                } footer: {
                    Text("这个好友的身份、性格、说话方式。仅对当前好友生效。")
                }

                Section {
                    Picker("AI 模型", selection: $aiProviderId) {
                        Text("跟随全局").tag("")
                        ForEach(ProviderStore.shared.providers.filter { $0.kind == .main }) { p in
                            Text(p.model.isEmpty ? p.label : "\(p.label) · \(p.model)").tag(p.id.uuidString)
                        }
                    }
                } header: {
                    Text("AI 模型")
                } footer: {
                    Text("进入这个好友的聊天时自动切换到所选模型；留空跟随全局设置。")
                }

                Section {
                    Picker("语音引擎", selection: $voiceEngine) {
                        Text("跟随全局").tag("")
                        Text("本地语音").tag("local")
                        Text("开源语音库").tag("server")
                        Text("硅基流动").tag("cloud_sf")
                        Text("豆包").tag("cloud_doubao")
                    }
                    TextField("音色 ID（如 huayan_fast / anna / BV700_V2_streaming）", text: $voiceId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("专属 API Key（可留空）", text: $ttsKey)
                } header: {
                    Text("语音 API")
                } footer: {
                    Text("给这个好友单独指定音色和密钥；留空则使用「我的 → 朗读」里的全局设置。")
                }
            }
            .navigationTitle(isNew ? "新建好友" : "好友设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: hydrate)
            .onChange(of: item) { _, it in
                guard let it else { return }
                Task {
                    if let data = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        saveAvatar(img)
                    }
                }
            }
        }
    }

    private var currentAvatar: UIImage? {
        if let id = friendId, let f = fs.friend(id) { return f.avatarImage() }
        return nil
    }

    private func hydrate() {
        guard !loaded else { return }
        loaded = true
        if let id = friendId, let f = fs.friend(id) {
            name = f.name; persona = f.persona; gender = f.gender; age = f.age
            voiceEngine = f.voiceEngine; voiceId = f.voiceId; ttsKey = f.ttsKey; aiProviderId = f.aiProviderId
        } else if let d = draft {
            name = d.name
        }
    }

    private func saveAvatar(_ img: UIImage) {
        guard let id = friendId ?? draft?.id else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = "friend-\(id).jpg"
        if let data = img.jpegData(compressionQuality: 0.85) {
            try? data.write(to: dir.appendingPathComponent(file))
        }
    }

    private func save() {
        if let id = friendId {
            fs.update(id) { f in
                f.name = name; f.persona = persona; f.gender = gender; f.age = age
                f.voiceEngine = voiceEngine; f.voiceId = voiceId; f.ttsKey = ttsKey; f.aiProviderId = aiProviderId
                if FileManager.default.fileExists(atPath: avatarPath(id)) { f.avatarFile = "friend-\(id).jpg" }
            }
        } else {
            var f = draft ?? ChatFriend()
            f.name = name; f.persona = persona; f.gender = gender; f.age = age
            f.voiceEngine = voiceEngine; f.voiceId = voiceId; f.ttsKey = ttsKey; f.aiProviderId = aiProviderId
            fs.add(f)
            let id = f.id
            if FileManager.default.fileExists(atPath: avatarPath(id)) {
                fs.update(id) { $0.avatarFile = "friend-\(id).jpg" }
            }
        }
        Haptics.success()
        dismiss()
    }

    private func avatarPath(_ id: String) -> String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("friend-\(id).jpg").path
    }
}
