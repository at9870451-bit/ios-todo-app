import SwiftUI
import PhotosUI
import UIKit

// MARK: - 背景存储（外观分类：本地图片替换全局背景）

@MainActor
final class BackgroundStore: ObservableObject {
    static let shared = BackgroundStore()

    @Published var image: UIImage?
    @Published var overlay: Double

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chat_bg.jpg")
    }

    private init() {
        overlay = UserDefaults.standard.object(forKey: "ui.bgOverlay") as? Double ?? 0.32
        if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
            image = img
        }
    }

    func setImage(_ ui: UIImage) {
        image = ui
        if let data = ui.jpegData(compressionQuality: 0.85) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func setOverlay(_ d: Double) {
        overlay = d
        UserDefaults.standard.set(d, forKey: "ui.bgOverlay")
    }

    func clear() {
        image = nil
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// 全局背景：无图 = 蓝白渐变；有图 = 本地图片 + 可调遮罩
struct AppBackground: View {
    @EnvironmentObject var bg: BackgroundStore

    var body: some View {
        if let img = bg.image {
            ZStack {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                Color(uiColor: .systemGroupedBackground)
                    .opacity(bg.overlay)
                    .ignoresSafeArea()
            }
        } else {
            LinearGradient(
                colors: [Color.white, Color(red: 0.90, green: 0.94, blue: 1.0)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - 外观设置页

struct AppearanceView: View {
    @EnvironmentObject var bg: BackgroundStore
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("预览")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ZStack {
                    AppBackground()
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(height: 150)
                        .overlay(
                            VStack(spacing: 8) {
                                Text("对话气泡将显示在这里")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Capsule().fill(Theme.accent.opacity(0.85)).frame(width: 90, height: 22)
                                    Capsule().fill(Theme.card).frame(width: 120, height: 22)
                                }
                            }
                        )
                        .padding(.horizontal, 4)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text(bg.image == nil ? "选择背景图片" : "更换背景图片")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .foregroundStyle(.white)
                }

                if bg.image != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("背景遮罩深度（数值越大越清晰保留原背景）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("朦胧").font(.caption2).foregroundStyle(.tertiary)
                            Slider(value: Binding(
                                get: { 1 - bg.overlay },
                                set: { bg.setOverlay(1 - $0) }
                            ), in: 0...1)
                            Text("清晰").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                    Button {
                        bg.clear()
                    } label: {
                        Text("恢复默认渐变背景")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }

                Text("背景图片仅保存在本机沙盒，应用于对话、会话列表、设置等全部页面。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(AppBackground())
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = ChatScreen.downscaleJPEG(data, maxDim: 2048, quality: 0.85).flatMap(UIImage.init(data:)) {
                    bg.setImage(img)
                } else if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    bg.setImage(img)
                }
                pickerItem = nil
            }
        }
    }
}

// MARK: - 人设设置页

struct PersonaView: View {
    @AppStorage("persona.prompt") private var prompt = ""

    private let presets: [(String, String)] = [
        ("默认助手", ""),
        ("严谨翻译", "你是严谨的中英互译官。用户输入中文时翻译成英文，输入英文时翻译成中文。只输出译文，不要解释。"),
        ("编程专家", "你是资深软件工程师。回答技术问题时给出可运行的代码与简要原理，指出常见坑点，语言精炼。"),
        ("文案写手", "你是资深文案策划。文风简洁有力，善用比喻，提供 2-3 个备选方案并说明适用场景。"),
        ("儿童百科", "你面向 8 岁小朋友讲解世界。用简单词句和生动比喻，每次回答不超过 150 字。"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("人设会作为系统提示词随每次对话发送给 AI，决定它的身份、语气与回答方式。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("系统提示词")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $prompt)
                        .font(.subheadline)
                        .frame(minHeight: 150)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("快速预设")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        ForEach(presets, id: \.0) { name, text in
                            Button {
                                prompt = text
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                        Text(text.isEmpty ? "通用智能助手，无附加人设" : String(text.prefix(40)) + "…")
                                            .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                    Spacer()
                                    if prompt == text {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                    } else {
                                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(12)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("人设保存在本机，随消息即时生效，无需保存按钮。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(AppBackground())
        .navigationTitle("人设")
        .navigationBarTitleDisplayMode(.inline)
    }
}
