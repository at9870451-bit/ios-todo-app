// DollStudio3D — 主页：顶部栏 / 3D 玩偶区 / 视角与姿势 / 底部衣橱面板
import SwiftUI
import SceneKit

struct RootView: View {
    @EnvironmentObject var store: OutfitStore
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var scene: DollSceneController

    @State private var showSettings = false
    @State private var showGenderPicker = false
    @State private var showSaveSheet = false
    @State private var showAISheet = false
    @State private var screenshot: UIImage?
    @State private var showShare = false

    private let sceneViewID = "main3d"

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景柔和渐变
                LinearGradient(colors: [Color(0xFFF7F9FD), Color(0xFFFDF6EE)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    sceneArea
                    WardrobePanel(onSnapshot: takeScreenshot)
                        .background(.ultraThinMaterial)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showGenderPicker) { GenderPickerView() }
            .sheet(isPresented: $showAISheet) { AIAssistantView() }
            .sheet(isPresented: $showSaveSheet) { SaveOutfitView(onSaved: { name in
                // 保存后自动截图占位（作品列表可再截图）
            }) }
            .sheet(isPresented: $showShare) {
                if let img = screenshot {
                    ShareSheet(items: [img])
                }
            }
        }
    }

    // MARK: 顶部栏

    private var topBar: some View {
        HStack(spacing: 14) {
            Text("Doll Studio 3D")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color(0xFF1D1D1F))

            Spacer()

            NavigationLink { FavoritesView() } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(0xFFFF3B30))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white).shadow(color: .black.opacity(0.06), radius: 5, y: 2))
            }
            Button {
                showGenderPicker = true
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 19))
                    .foregroundStyle(Color(0xFF3478F6))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white).shadow(color: .black.opacity(0.06), radius: 5, y: 2))
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(0xFF86868B))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white).shadow(color: .black.opacity(0.06), radius: 5, y: 2))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: 3D 区域

    private var sceneArea: some View {
        ZStack {
            DollSceneView(controller: scene,
                          gender: store.gender,
                          skin: store.skin,
                          heightScale: store.heightScale,
                          slots: store.slots,
                          catalog: store.catalog)
                .ignoresSafeArea(edges: .bottom)

            // 左：视角
            VStack(spacing: 10) {
                viewButton("正面")
                viewButton("侧面")
                viewButton("背面")
                Button {
                    scene.resetView()
                    audio.play(.tap)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(0xFF1D1D1F))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white).shadow(color: .black.opacity(0.08), radius: 6, y: 2))
                }
                Spacer()
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右：姿势
            VStack(spacing: 10) {
                ForEach(DollPose.allCases) { pose in
                    Button {
                        scene.applyPose(pose)
                        audio.play(.tap)
                    } label: {
                        Text(pose.title)
                            .font(.system(size: 12, weight: scene.pose == pose ? .bold : .regular))
                            .foregroundStyle(scene.pose == pose ? Color.white : Color(0xFF1D1D1F))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(scene.pose == pose
                                        ? AnyShapeStyle(Color(0xFFFF9500))
                                        : AnyShapeStyle(Color.white))
                                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2))
                    }
                }
                Spacer()
            }
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .trailing)

            // 底部信息条
            VStack {
                Spacer()
                HStack {
                    Text("\(store.gender.title) · \(store.dollName)")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color(0xFF86868B))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.9)))
                    Spacer()
                    Text("单指旋转 · 双指缩放")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(0xFFAEAEB2))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.9)))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }

    private func viewButton(_ label: String) -> some View {
        Button {
            scene.face(label)
            audio.play(.tap)
        } label: {
            Text(label)
                .font(.system(size: 12, weight: scene.viewLabel == label ? .bold : .regular))
                .foregroundStyle(scene.viewLabel == label ? Color.white : Color(0xFF1D1D1F))
                .frame(width: 40, height: 40)
                .background(Circle().fill(scene.viewLabel == label
                        ? AnyShapeStyle(Color(0xFF3478F6))
                        : AnyShapeStyle(Color.white))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2))
        }
    }

    // MARK: 截图分享

    private func takeScreenshot() {
        // 从 SceneKit view 快照：通过 controller snapshot
        // SCNView 在 representable 中，snapshot 需引用；这里通过 UIWindow 遍历找 SCNView
        if let scnView = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first?.allSubviews.compactMap({ $0 as? SCNView }).first {
            screenshot = scnView.snapshot()
            showShare = true
            audio.play(.success)
        }
    }
}

extension UIView {
    var allSubviews: [UIView] {
        var out: [UIView] = [self]
        for sub in subviews { out += sub.allSubviews }
        return out
    }
}

// MARK: - 系统分享

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - 保存穿搭 Sheet

struct SaveOutfitView: View {
    @EnvironmentObject var store: OutfitStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    let onSaved: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(.gray.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 10)
            Text("保存穿搭").font(.system(size: 18, weight: .bold))
            TextField("给这套穿搭起个名字", text: $name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
            Button {
                let finalName = name.isEmpty ? "\(store.dollName) 的穿搭" : name
                _ = store.saveOutfit(named: finalName)
                onSaved(finalName)
                dismiss()
            } label: {
                Text("保存作品")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(colors: [Color(0xFF3478F6), Color(0xFF6CA8FF), Color(0xFFFF9500)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .clipShape(RoundedRectangle(cornerRadius: 16)))
            }
            .padding(.horizontal, 20)
            Spacer()
        }
        .presentationDetents([.height(220)])
    }
}

// MARK: - AI 穿搭助手 Sheet

struct AIAssistantView: View {
    @EnvironmentObject var store: OutfitStore
    @EnvironmentObject var audio: AudioService
    @Environment(\.dismiss) var dismiss
    @State private var prompt = "帮我搭配一套秋冬街头风格的衣服。"
    @State private var running = false
    @State private var resultText = ""
    @State private var source = ""

    private let quickPrompts = ["秋冬街头风格", "日系温柔穿搭", "韩系气质", "运动风", "商务正式", "可爱甜美"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(.gray.opacity(0.3)).frame(width: 40, height: 5)
                .frame(maxWidth: .infinity).padding(.top, 10)
            Text("AI 穿搭助手")
                .font(.system(size: 18, weight: .bold))
            Text("输入想要的风格，AI 根据玩偶性别与现有衣橱返回搭配方案")
                .font(.system(size: 12.5))
                .foregroundStyle(Color(0xFF86868B))

            TextField("例如：帮我搭配一套秋冬街头风格的衣服", text: $prompt, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickPrompts, id: \.self) { q in
                        Button(q) { prompt = "帮我搭配一套\(q)的衣服。" }
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Color(0xFFFFF4E8)))
                            .foregroundStyle(Color(0xFFE87500))
                    }
                }
            }

            Button {
                run()
            } label: {
                HStack {
                    if running {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(running ? "AI 搭配中…" : "生成搭配方案")
                }
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(LinearGradient(colors: [Color(0xFF3478F6), Color(0xFF6CA8FF), Color(0xFFFF9500)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: 16)))
            }
            .disabled(running)

            if !resultText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(resultText)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color(0xFF1D1D1F))
                    Text(source)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(0xFFAEAEB2))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(0xFFF2F2F7)))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .presentationDetents([.medium, .large])
    }

    private func run() {
        running = true
        resultText = ""
        Task {
            let r = await AIAssistant.plan(store: store, prompt: prompt)
            // 应用方案
            store.applySlotsDirect(r.slots)
            audio.play(.success)
            var lines: [String] = []
            for (cat, slot) in r.slots.sorted(by: { $0.key < $1.key }) {
                let title = store.categories.first { $0.key == cat }?.title ?? cat
                let name = store.itemById(slot.clothId)?.name ?? slot.clothId
                lines.append("• \(title)：\(name)")
            }
            lines.append("")
            lines.append(r.reason)
            resultText = lines.joined(separator: "\n")
            source = r.source == "server-ai" ? "来源：服务端 AI" : "来源：本地演示规则引擎（接入后端 AI API 后由大模型生成）"
            running = false
        }
    }
}
