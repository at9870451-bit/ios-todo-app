import SwiftUI

/// OKX 首页：功能入口导航
struct OkxHomeView: View {
    @EnvironmentObject var store: BackendStore

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.045, green: 0.055, blue: 0.09).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("OKX")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("账户 · 行情 · 交易")
                                .font(.footnote).foregroundStyle(.white.opacity(0.45))
                        }
                        .padding(.top, 6)

                        // 资产速览
                        HStack(spacing: 10) {
                            StatTile(title: "现货总资产", value: Fmt.money(store.dashboard?.okx["spot"]?.totalAssets),
                                     sub: store.dashboard?.okx["spot"]?.configured == true ? "已配置" : "未配置")
                            StatTile(title: "合约总资产", value: Fmt.money(store.dashboard?.okx["swap"]?.totalAssets),
                                     sub: store.dashboard?.okx["swap"]?.configured == true ? "已配置" : "未配置")
                        }

                        VStack(spacing: 10) {
                            NavCard(icon: "key.fill", title: "API 配置", desc: "配置 OKX API Key / Secret / Passphrase", color: Color(red: 0.29, green: 0.56, blue: 1.0)) {
                                OkxConfigView()
                            }
                            NavCard(icon: "wallet.pass.fill", title: "账户资产", desc: "余额明细与持仓汇总", color: Color(red: 0.25, green: 0.85, blue: 0.5)) {
                                OkxAccountView()
                            }
                            NavCard(icon: "chart.xyaxis.line", title: "实时行情", desc: "现货 / 永续行情列表", color: Color(red: 1.0, green: 0.68, blue: 0.3)) {
                                OkxMarketView()
                            }
                            NavCard(icon: "list.bullet.rectangle", title: "订单管理", desc: "下单 · 撤单 · 订单列表", color: Color(red: 0.75, green: 0.65, blue: 1.0)) {
                                OkxOrdersView()
                            }
                            NavCard(icon: "square.stack.3d.up.fill", title: "持仓管理", desc: "查看持仓与一键平仓", color: Color(red: 1.0, green: 0.45, blue: 0.55)) {
                                OkxPositionsView()
                            }
                            NavCard(icon: "flask.fill", title: "模拟盘交易台", desc: "OKX Demo Trading 模拟交易", color: Color(red: 0.4, green: 0.8, blue: 0.8)) {
                                PaperTradingView()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .refreshable { await store.refreshDashboard() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task { await store.refreshDashboard() }
        }
    }
}

/// 导航卡片
struct NavCard<Destination: View>: View {
    let icon: String
    let title: String
    let desc: String
    var color: Color = .blue
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text(desc).font(.caption).foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.25))
            }
            .padding(14)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
