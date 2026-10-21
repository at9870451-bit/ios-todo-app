// DollStudio3D — 底部衣橱面板：分类行 / 服装缩略图横滑 / 颜色 / 撤销重做 / 保存分享
import SwiftUI

struct WardrobePanel: View {
    @EnvironmentObject var store: OutfitStore
    @EnvironmentObject var audio: AudioService
    var onSnapshot: () -> Void

    @State private var selectedCategory = "top"

    private var currentItems: [ClothItem] {
        store.catalog
            .filter { $0.category == selectedCategory }
            .sorted { a, b in
                let fa = store.favorites.contains(a.id) ? 0 : 1
                let fb = store.favorites.contains(b.id) ? 0 : 1
                if fa != fb { return fa < fb }
                let ra = store.recent.firstIndex(of: a.id) ?? 999
                let rb = store.recent.firstIndex(of: b.id) ?? 999
                return ra < rb
            }
    }

    var body: some View {
        VStack(spacing: 10) {
            // 第一行：分类
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.categories) { cat in
                        let selected = selectedCategory == cat.key
                        Button {
                            selectedCategory = cat.key
                            audio.play(.tap)
                        } label: {
                            Text(cat.title)
                                .font(.system(size: 13.5, weight: selected ? .bold : .regular))
                                .foregroundStyle(selected ? Color.white : Color(0xFF1D1D1F))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(selected
                                        ? AnyShapeStyle(Color(0xFFFF9500))
                                        : AnyShapeStyle(Color(0xFFF2F2F7))))
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            // 第二行：服装缩略图横滑
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if let worn = store.slots[selectedCategory],
                       let wornItem = store.itemById(worn.clothId) {
                        // 移除当前
                        Button {
                            store.removeSlot(category: selectedCategory)
                        } label: {
                            VStack(spacing: 5) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(0xFFFFF4E8))
                                    Image(systemName: "minus")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(Color(0xFFE87500))
                                }
                                .frame(width: 62, height: 62)
                                Text("脱下")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Color(0xFF86868B))
                            }
                        }
                        thumbnail(for: wornItem, worn: true, colorOverride: worn.color)
                    }
                    ForEach(currentItems) { item in
                        if store.slots[selectedCategory]?.clothId != item.id {
                            thumbnail(for: item, worn: false, colorOverride: nil)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 92)

            // 第三行：颜色 + 撤销/重做/重置
            HStack(spacing: 12) {
                if store.slots[selectedCategory] != nil {
                    colorRow
                }
                Spacer()
                panelIconButton("arrow.uturn.backward", disabled: !store.canUndo) { store.undo() }
                panelIconButton("arrow.uturn.forward", disabled: !store.canRedo) { store.redo() }
                panelIconButton("arrow.counterclockwise.circle") { store.resetOutfit() }
            }
            .padding(.horizontal, 20)

            // 第四行：主按钮
            HStack(spacing: 10) {
                Button {
                    onSnapshot()
                } label: {
                    Label("保存穿搭", systemImage: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(0xFF1D1D1F))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 16)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.07), radius: 8, y: 3))
                }
                NavigationLink { OutfitListView() } label: {
                    Label("我的作品", systemImage: "folder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(
                            LinearGradient(colors: [Color(0xFF3478F6), Color(0xFF6CA8FF), Color(0xFFFF9500)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                .clipShape(RoundedRectangle(cornerRadius: 16)))
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: 颜色选择行

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(paletteColors, id: \.self) { hex in
                    let isCurrent = store.slots[selectedCategory]?.color.lowercased() == hex.lowercased()
                    Button {
                        store.setColor(hex, for: selectedCategory)
                        audio.play(.tap)
                    } label: {
                        Circle()
                            .fill(Color(hexString: hex))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(
                                isCurrent ? Color(0xFF1D1D1F) : Color(0xFFD1D1D6),
                                lineWidth: isCurrent ? 2.2 : 1))
                    }
                }
            }
        }
        .frame(maxWidth: 210, alignment: .leading)
    }

    private let paletteColors = ["#2B2B2E", "#5A5A5E", "#8E8E93", "#F5F5F7",
                                 "#5B8DEF", "#3478F6", "#67C7FF", "#8C9EFF",
                                 "#FF9500", "#FF6A00", "#F4A6C0", "#C4453C",
                                 "#34C759", "#6B4A32", "#C8A882", "#7A5A8A"]

    // MARK: 缩略图（程序化：色块 + 图标；thumb URL 存在时用远程图）

    private func thumbnail(for item: ClothItem, worn: Bool, colorOverride: String?) -> some View {
        let locked = !store.canWear(item)
        let fav = store.favorites.contains(item.id)
        return Button {
            if locked {
                store.purchase(item)   // 本地模拟解锁；正式版接服务端订单
                audio.play(.success)
            } else {
                store.select(item)
            }
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(worn
                              ? LinearGradient(colors: [Color(0xFF3478F6), Color(0xFF6CA8FF), Color(0xFFFF9500)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                              : LinearGradient(colors: [Color(0xFFF7F7F9), Color(0xFFEFEFF3)],
                                               startPoint: .top, endPoint: .bottom))
                        .frame(width: 62, height: 62)
                    if let thumb = item.thumb, let url = URL(string: thumb) {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        Image(systemName: iconFor(item))
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(worn ? Color.white : Color(hexString: colorOverride ?? item.color))
                    }
                    if locked {
                        RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.35))
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    }
                    if fav {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(0xFFFF3B30))
                            .padding(4)
                    }
                }
                .frame(width: 62, height: 62)
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(worn ? Color.clear : Color(0xFFE3E3E8), lineWidth: 1))
                Text(item.name)
                    .font(.system(size: 10.5, weight: worn ? .semibold : .regular))
                    .foregroundStyle(worn ? Color(0xFFE87500) : Color(0xFF1D1D1F))
                    .lineLimit(1)
            }
            .contextMenu {
                Button {
                    store.toggleFavorite(item.id)
                } label: {
                    Label(fav ? "取消收藏" : "收藏",
                          systemImage: fav ? "heart.slash" : "heart")
                }
            }
        }
    }

    private func iconFor(_ item: ClothItem) -> String {
        switch item.kind {
        case "tee": return "tshirt"
        case "shirt": return "button.programmable"
        case "hoodie", "sweater": return "cloud.fill"
        case "jacket", "coat": return "shield.lefthalf.filled"
        case "pants", "shorts": return "figure.walk"
        case "skirt", "longskirt": return "triangle"
        case "scarf", "scarflong", "scarfneck": return "link"
        case "cap", "beanie", "beret", "bucket": return "figure.winter"
        case "sneakers", "leather", "boots": return "shoe"
        case "hairShort", "hairLong", "hairCurly", "hairPony": return "person.crop.square"
        case "glasses": return "eyeglasses"
        case "necklace": return "sparkles"
        case "bag": return "bag"
        case "earring": return "circle.circle"
        default: return "square.grid.2x2"
        }
    }

    private func panelIconButton(_ icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(disabled ? Color(0xFFC7C7CC) : Color(0xFF1D1D1F))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(0xFFF2F2F7)))
        }
        .disabled(disabled)
    }
}

// MARK: - Color(hexString:)

extension Color {
    init(hexString: String) {
        var h = hexString.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        var v: UInt64 = 0x888888
        Scanner(string: h).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
