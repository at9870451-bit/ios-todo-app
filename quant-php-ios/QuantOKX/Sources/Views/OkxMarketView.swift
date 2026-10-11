import SwiftUI

/// 实时行情：单币行情 + 行情列表
struct OkxMarketView: View {
    @EnvironmentObject var store: BackendStore

    @State private var market: String = "spot"
    @State private var symbol: String = "BTC-USDT"
    @State private var keyword: String = ""
    @State private var ticker: TickerRow?

    var body: some View {
        PageScaffold(title: "实时行情", subtitle: "OKX 公共行情（无需配置账户）") {
            Picker("市场", selection: $market) {
                Text("现货").tag("spot")
                Text("永续").tag("swap")
            }
            .pickerStyle(.segmented)
            .onChange(of: market) { _, m in
                symbol = m == "spot" ? "BTC-USDT" : "BTC-USDT-SWAP"
                ticker = nil
                Task { await loadTicker(); await store.loadTickers(market: m) }
            }

            // 单个产品行情
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("", text: $symbol, prompt: Text("BTC-USDT").foregroundStyle(.tertiary))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.primary)
                        Button {
                            Task { await loadTicker() }
                        } label: {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.blue)
                        }
                    }
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))

                    if let t = ticker {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Fmt.price(t.lastPrice))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text(Fmt.pct(t.priceChangePercent))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Fmt.pnlColor(t.priceChangePercent))
                        }
                        HStack(spacing: 10) {
                            StatTile(title: "24h 最高", value: Fmt.price(t.highPrice))
                            StatTile(title: "24h 最低", value: Fmt.price(t.lowPrice))
                            StatTile(title: "24h 量", value: Fmt.money(t.volume))
                        }
                    } else {
                        EmptyHint(icon: "chart.line.uptrend.xyaxis", text: "输入交易对后查询")
                    }
                }
            }

            // K 线走势
            if ticker != nil {
                KlineSection(symbol: symbol.uppercased(), market: market)
            }

            // 行情列表
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("行情列表").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Spacer()
                    Text("\(store.tickers.count) 个").font(.caption).foregroundStyle(.secondary)
                }
                TextField("", text: $keyword, prompt: Text("搜索币种，如 BTC").foregroundStyle(.tertiary))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    .onSubmit { Task { await store.loadTickers(market: market, keyword: keyword) } }

                ForEach(store.tickers, id: \.symbol) { t in
                    Card(padding: 12) {
                        HStack {
                            Text(t.symbol)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.primary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Fmt.price(t.lastPrice))
                                    .font(.subheadline.monospaced()).foregroundStyle(.primary)
                                Text(Fmt.pct(t.priceChangePercent))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Fmt.pnlColor(t.priceChangePercent))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("实时行情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTicker()
            await store.loadTickers(market: market)
        }
    }

    private func loadTicker() async {
        do {
            ticker = try await BackendClient.shared.get("/api/okx/ticker",
                query: ["symbol": symbol, "market_type": market], as: TickerRow.self)
        } catch {
            store.handle(error)
        }
    }
}
