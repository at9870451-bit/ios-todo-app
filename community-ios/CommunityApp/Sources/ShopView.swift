import SwiftUI

struct ShopItem: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let price: Double
    let desc: String
    let sold: Int
}

struct ShopView: View {
    @State private var buying: ShopItem?
    @State private var toast: String?

    private let items: [ShopItem] = [
        ShopItem(name: "量化入门训练营", icon: "🎓", price: 9.9,
                 desc: "从零到跑通第一个回测的 12 节视频课", sold: 1284),
        ShopItem(name: "自研指标模板包", icon: "📐", price: 19.9,
                 desc: "ATR 止损 / 网格参数 / RSI 分段，含使用说明", sold: 653),
        ShopItem(name: "社区限定 Tee", icon: "👕", price: 59.0,
                 desc: "纯棉，K 线印花，两色可选", sold: 217),
        ShopItem(name: "策略 1v1 咨询", icon: "🧑‍💻", price: 199.0,
                 desc: "一小时，帮你把策略思路捋成可执行清单", sold: 38),
        ShopItem(name: "服务器合租位", icon: "🖥", price: 15.0,
                 desc: "跑你的量化机器人，月付含 IPv4 独立出口", sold: 96),
        ShopItem(name: "本地宝典 PDF", icon: "📚", price: 0.0,
                 desc: "社区三年精华帖合集，免费领取", sold: 3021),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(items) { item in
                        card(item)
                    }
                }
                .padding(12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("商店")
            .overlay(alignment: .bottom) {
                if let t = toast {
                    Text(t)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.82), in: Capsule())
                        .padding(.bottom, 12)
                        .task {
                            try? await Task.sleep(nanoseconds: 2_200_000_000)
                            self.toast = nil
                        }
                }
            }
            .confirmationDialog(buying.map { "购买 \($0.name)？" } ?? "",
                                isPresented: Binding(get: { buying != nil },
                                                     set: { if !$0 { buying = nil } }),
                                titleVisibility: .visible) {
                Button("确认购买", role: .none) {
                    if let b = buying { toast = "✅ 已下单：\(b.name)（演示环境，不扣款）" }
                    buying = nil
                }
                Button("取消", role: .cancel) { buying = nil }
            }
        }
    }

    private func card(_ item: ShopItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.indigo.opacity(0.08))
                    .frame(height: 84)
                Text(item.icon)
                    .font(.system(size: 40))
            }

            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Text(item.desc)
                .font(.caption2)
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
                .frame(minHeight: 30, alignment: .top)

            HStack(alignment: .firstTextBaseline) {
                Text(item.price == 0 ? "免费" : "¥\(String(format: "%.1f", item.price))")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(item.price == 0 ? Color.green : Color.primary)
                Spacer()
                Text("\(item.sold) 人购买")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.tertiary)
            }

            Button {
                buying = item
            } label: {
                Text(item.price == 0 ? "领取" : "购买")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(item.price == 0 ? Color.green : Color.indigo)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }
}
