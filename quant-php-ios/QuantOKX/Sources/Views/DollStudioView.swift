import SwiftUI
import UIKit

// MARK: - 玩偶 Tab：Doll Studio 3D（Q 版盲盒换装工作室）
// 中央 3D 玩偶（RealityKit）+ 底部服装分类横向选择栏 + 颜色调整 + 随机/撤销重做 +
// 保存穿搭/收藏/导出图片/分享 + AI 穿搭推荐（密钥在服务端）。

struct DollStudioView: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var router: Router
    @StateObject private var scene = DollSceneController()

    @State private var outfit: DollOutfitState = .preset
    @State private var history: [DollOutfitState] = [DollOutfitState.preset]
    @State private var pointer = 0
    @State private var activeCategory = "top"

    @State private var showSaveAlert = false
    @State private var saveName = ""
    @State private var showOutfits = false
    @State private var showAI = false
    @State private var showExportDialog = false
    @State private var shareItem: ShareImageItem?
    @State private var exporting = false
    @State private var aiPrompt = ""
    @State private var aiBusy = false
    @State private var aiReason = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 0) {
                    viewport
                    wardrobe
                }
            }
            .navigationTitle("Doll Studio 3D")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        showExportDialog = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                    }
                }
            }
        }
        .onAppear(perform: bootstrap)
        .onChange(of: outfit) { _, newValue in
            scene.baseURL = store.config.serverURL
            scene.apply(state: newValue, lookup: lookup)
        }
        .onChange(of: router.tab) { _, tab in
            // 切回玩偶页时重建的 3D 视口需要重新应用当前穿搭
            guard tab == 2 else { return }
            scene.baseURL = store.config.serverURL
            scene.apply(state: outfit, lookup: lookup)
        }
        .alert("保存穿搭", isPresented: $showSaveAlert) {
            TextField("搭配名称", text: $saveName)
            Button("保存") { Task { await saveOutfit() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("给这套穿搭起个名字，保存后可在「我的穿搭」中找回")
        }
        .sheet(isPresented: $showOutfits) { outfitsSheet }
        .sheet(isPresented: $showAI) { aiSheet }
        .sheet(item: $shareItem) { it in
            ShareSheet(items: [it.image])
        }
        .confirmationDialog("导出玩偶照片", isPresented: $showExportDialog, titleVisibility: .visible) {
            Button("保存到相册") { exportImage(toAlbum: true) }
            Button("分享图片") { exportImage(toAlbum: false) }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 3D 视口

    private var viewport: some View {
        Group {
            if router.tab == 2 {
                // 仅在玩偶页签激活时创建 RealityKit 视图：
                // TabView 常驻所有子页，ARView 若一直存活会持续渲染拖慢全局帧率（卡顿主因之二）
                DollSceneView(controller: scene)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusXL, style: .continuous)
                        .fill(Theme.inset)
                    Image(systemName: "teddybear")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.accent.opacity(0.45))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusXL, style: .continuous))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    genderControl
                    baseControl
                }
                .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                GlassIconButton(icon: "arrow.counterclockwise", size: 38) { scene.resetView() }
                    .padding(12)
            }
            .overlay(alignment: .bottomLeading) { skinControl.padding(12) }
            .overlay(alignment: .bottomTrailing) {
                Text("拖动旋转 · 双指缩放 · 双击复位")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }

    private var genderControl: some View {
        HStack(spacing: 6) {
            ForEach(["male", "female", "neutral"], id: \.self) { g in
                Button {
                    guard outfit.gender != g else { return }
                    // 切换角色 = 载入该款预设（穿搭 + 底座配色一次到位）
                    let pre = DollOutfitState.presetOf(g)
                    commit { st in
                        st.gender = g
                        st.skin = pre.skin
                        st.baseColor = pre.baseColor
                        st.items = pre.items
                    }
                    Haptics.tap()
                } label: {
                    Text(DollCatalog.genderName(g))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(outfit.gender == g ? Color.white : Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if outfit.gender == g {
                                Capsule().fill(Theme.heroGradient)
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                            }
                        }
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    private var baseControl: some View {
        HStack(spacing: 7) {
            Text("底座").font(.caption2).foregroundStyle(.secondary)
            ForEach([("blue", "#8E9CB2"), ("pink", "#E8B6C8"), ("grey", "#C4C8CF")], id: \.0) { key, hex in
                Button {
                    guard outfit.baseColor != key else { return }
                    commit { $0.baseColor = key }
                    Haptics.tap()
                } label: {
                    Circle()
                        .fill(Color(uiColor: DollColor.ui(hex)))
                        .frame(width: 22, height: 22)
                        .overlay {
                            if outfit.baseColor == key {
                                Circle().strokeBorder(Color.white, lineWidth: 2)
                                    .shadow(color: .black.opacity(0.25), radius: 2)
                            }
                        }
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(PressableButtonStyle())
            }
            Divider().frame(height: 14)
            Button {
                commit { $0.showBadge.toggle() }
                Haptics.tap()
            } label: {
                Text(outfit.showBadge ? "标注开" : "标注关")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(outfit.showBadge ? Theme.accent.opacity(0.16) : Color.gray.opacity(0.14), in: Capsule())
                    .foregroundStyle(outfit.showBadge ? Theme.accent : Color.secondary)
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    private var skinControl: some View {
        HStack(spacing: 7) {
            Text("肤色").font(.caption2).foregroundStyle(.secondary)
                .padding(5)
                .background(.ultraThinMaterial, in: Capsule())
            ForEach(DollCatalog.skinTones, id: \.self) { hex in
                Button {
                    guard outfit.skin != hex else { return }
                    commit { $0.skin = hex }
                    Haptics.tap()
                } label: {
                    Circle()
                        .fill(c(hex))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.8))
                        .overlay(alignment: .center) {
                            if outfit.skin == hex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - 衣橱面板

    private var wardrobe: some View {
        VStack(spacing: 10) {
            categoryBar
            itemStrip
            paletteRow
            actionBar
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .glassBar()
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.dollCategories) { cat in
                    let active = activeCategory == cat.code
                    Button {
                        activeCategory = cat.code
                        Haptics.tap()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: DollCatalog.icon(for: cat.code))
                                .font(.system(size: 12, weight: .semibold))
                            Text(cat.name).font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(active ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            if active {
                                Capsule().fill(Theme.heroGradient)
                            } else {
                                Capsule().fill(Color.white.opacity(0.72))
                            }
                        }
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - 条目 / 调色 / 操作

extension DollStudioView {

    private var categoryName: String {
        store.dollCategories.first(where: { $0.code == activeCategory })?.name ?? "分类"
    }

    private func items(for cat: String) -> [DollItem] {
        store.dollItems.filter { $0.category == cat }
    }

    private var lookup: [String: DollItem] {
        var m: [String: DollItem] = [:]
        for it in store.dollItems { m["\(it.category)|\(it.style)"] = it }
        return m
    }

    private func c(_ hex: String) -> Color { Color(uiColor: DollColor.ui(hex)) }

    private var itemStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                noneChip
                ForEach(items(for: activeCategory)) { item in
                    itemChip(item)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private var noneChip: some View {
        Button {
            commit { $0.items[activeCategory] = nil }
            Haptics.tap()
        } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "slash.circle").font(.system(size: 15)).foregroundStyle(.secondary))
                Text("无").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 62)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func itemChip(_ item: DollItem) -> some View {
        let selected = outfit.items[item.category]?.style == item.style
        return Button {
            commit { s in
                if let cur = s.items[item.category], cur.style == item.style {
                    s.items[item.category] = nil
                } else {
                    s.items[item.category] = DollSelection(style: item.style, color: item.color)
                }
            }
            Haptics.tap()
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(c(item.color)).frame(width: 40, height: 40)
                    if item.premium {
                        Image(systemName: "crown.fill").font(.system(size: 10)).foregroundStyle(.white)
                    }
                }
                .overlay(Circle().strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 2))
                .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1)
                Text(item.name)
                    .font(.caption2)
                    .foregroundStyle(selected ? Theme.accent : Color.primary)
                    .lineLimit(1)
            }
            .frame(width: 62)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var paletteRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("颜色").font(.caption).foregroundStyle(.secondary)
                ForEach(DollCatalog.palette, id: \.self) { hex in
                    Button {
                        applyColor(hex)
                    } label: {
                        Circle()
                            .fill(c(hex))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.8))
                            .overlay(alignment: .center) {
                                if outfit.items[activeCategory]?.color == hex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(isLight(hex) ? Color.black : Color.white)
                                }
                            }
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func isLight(_ hex: String) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        DollColor.ui(hex).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r * 0.299 + g * 0.587 + b * 0.114) > 0.7
    }

    private func applyColor(_ hex: String) {
        guard outfit.items[activeCategory] != nil else {
            store.toast = "先选择一个「\(categoryName)」款式再调色"
            return
        }
        commit { s in s.items[activeCategory]?.color = hex }
        Haptics.tap()
    }

    private var actionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                actionChip(icon: "dice.fill", title: "随机") { randomize() }
                actionChip(icon: "arrow.uturn.backward", title: "撤销", disabled: pointer <= 0) { undo() }
                actionChip(icon: "arrow.uturn.forward", title: "重做", disabled: pointer >= history.count - 1) { redo() }
                actionChip(icon: "square.and.arrow.down", title: "保存") { showSaveAlert = true }
                actionChip(icon: "heart.text.square", title: "我的穿搭") {
                    showOutfits = true
                    Task { await store.loadDollOutfits() }
                }
                actionChip(icon: "wand.and.stars", title: "AI 搭配") { showAI = true }
            }
            .padding(.horizontal, 2)
        }
    }

    private func actionChip(icon: String, title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            guard !disabled else { return }
            Haptics.light()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium))
                Text(title).font(.caption2.weight(.medium))
            }
            .foregroundStyle(disabled ? Color.secondary.opacity(0.5) : Color.primary)
            .frame(width: 62, height: 46)
            .background(Color.white.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - 状态操作（历史 / 随机 / 保存 / 导出）

extension DollStudioView {

    private func commit(_ transform: (inout DollOutfitState) -> Void) {
        var s = outfit
        transform(&s)
        outfit = s
        history = Array(history.prefix(pointer + 1)) + [s]
        pointer += 1
    }

    private func undo() {
        guard pointer > 0 else { return }
        pointer -= 1
        outfit = history[pointer]
    }

    private func redo() {
        guard pointer < history.count - 1 else { return }
        pointer += 1
        outfit = history[pointer]
    }

    private func randomize() {
        commit { s in
            for cat in DollCatalog.categories.map(\.code) {
                let list = store.dollItems.filter { $0.category == cat }
                guard !list.isEmpty else { continue }
                guard let it = list.randomElement() else { continue }
                s.items[cat] = DollSelection(style: it.style, color: it.color)
            }
        }
        Haptics.success()
    }

    private func bootstrap() {
        scene.baseURL = store.config.serverURL
        scene.apply(state: outfit, lookup: lookup)
        Task {
            await store.loadDollCatalog()
            scene.baseURL = store.config.serverURL
            scene.apply(state: outfit, lookup: lookup)
        }
    }

    private func saveOutfit() async {
        let name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        saveName = ""
        await store.saveDollOutfit(name: name.isEmpty ? "未命名搭配" : name, state: outfit)
    }

    private func exportImage(toAlbum: Bool) {
        guard !exporting else { return }
        exporting = true
        scene.snapshot { img in
            exporting = false
            guard let img else {
                store.toast = "导出失败，请稍后重试"
                return
            }
            if toAlbum {
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                store.toast = "已保存到相册"
                Haptics.success()
            } else {
                shareItem = ShareImageItem(image: img)
            }
        }
    }
}

// MARK: - 我的穿搭列表

extension DollStudioView {

    private var outfitsSheet: some View {
        NavigationStack {
            Group {
                if store.dollOutfits.isEmpty {
                    DEmpty(icon: "tshirt", text: "还没有保存的穿搭\n换一套好看的，点「保存」留个纪念")
                } else {
                    List {
                        ForEach(store.dollOutfits) { row in
                            outfitRow(row)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("我的穿搭")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { showOutfits = false } }
            }
            .task { await store.loadDollOutfits() }
        }
        .presentationDetents([.medium, .large])
    }

    private func outfitRow(_ row: DollOutfitRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.name).font(.subheadline.weight(.semibold))
                    if row.favorite {
                        Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(Theme.accent)
                    }
                }
                Text("\(DollCatalog.genderName(row.gender)) · \(Fmt.time(row.updatedAt ?? row.createdAt))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                outfit = row.outfitState
                showOutfits = false
                Haptics.success()
                store.toast = "已应用「\(row.name)」"
            } label: {
                Text("应用").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await store.deleteDollOutfit(id: row.id) }
            } label: { Label("删除", systemImage: "trash") }
            Button {
                Task { await store.favoriteDollOutfit(id: row.id, fav: !row.favorite) }
            } label: {
                Label(row.favorite ? "取消收藏" : "收藏", systemImage: row.favorite ? "heart.slash" : "heart")
            }
            .tint(Theme.accent)
        }
    }
}

// MARK: - AI 穿搭推荐面板

extension DollStudioView {

    private var aiSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if !aiReason.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AI 搭配师", systemImage: "wand.and.stars")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                        Text(aiReason).font(.subheadline)
                        Text("已应用到玩偶，可继续微调颜色")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("描述你想要的风格").font(.footnote).foregroundStyle(.secondary)
                    TextField("例如：夏天海边度假，清爽一点的蓝色系", text: $aiPrompt, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(10)
                        .background(Color.white.opacity(0.72),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["夏日海边", "冬日毛绒", "校园清新", "街头潮流", "睡前可爱"], id: \.self) { s in
                            Button {
                                aiPrompt = s
                            } label: {
                                Text(s).font(.caption).foregroundStyle(.primary)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(Color.white.opacity(0.72), in: Capsule())
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                }
                DButton(title: aiBusy ? "搭配生成中…" : "生成推荐",
                        icon: "wand.and.stars",
                        disabled: aiBusy || aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty) {
                    Task { await recommend() }
                }
                Spacer()
            }
            .padding(16)
            .navigationTitle("AI 穿搭推荐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { showAI = false } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func recommend() async {
        let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !aiBusy else { return }
        aiBusy = true
        defer { aiBusy = false }
        if let rec = await store.dollRecommend(gender: outfit.gender, prompt: prompt) {
            commit { s in
                for (cat, it) in rec.outfit {
                    s.items[cat] = DollSelection(style: it.style, color: it.color)
                }
            }
            aiReason = rec.reason
            Haptics.success()
        }
    }
}

// MARK: - 分享

struct ShareImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
