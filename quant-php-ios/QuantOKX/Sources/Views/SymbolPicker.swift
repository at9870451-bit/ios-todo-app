import SwiftUI

/// 多币种选择编辑器：已选列表 + 手动输入 + 热门快选 + 行情全列表
struct MultiSymbolEditor: View {
    var title: String = "自动交易币种（多选）"
    @Binding var symbols: [String]
    var market: String = "swap"
    @EnvironmentObject var store: BackendStore
    @State private var newSymbol = ""
    @State private var showAll = false

    private let popular = ["BTC-USDT-SWAP", "ETH-USDT-SWAP", "SOL-USDT-SWAP", "XRP-USDT-SWAP",
                           "DOGE-USDT-SWAP", "BNB-USDT-SWAP", "LTC-USDT-SWAP", "ADA-USDT-SWAP"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption).foregroundStyle(.secondary)

            if symbols.isEmpty {
                Text("至少保留 1 个币种").font(.caption2).foregroundStyle(.orange)
            }
            ForEach(symbols, id: \.self) { s in
                HStack {
                    Image(systemName: "link.circle.fill").foregroundStyle(.blue.opacity(0.7))
                    Text(s).font(.footnote.monospaced()).foregroundStyle(.primary)
                    Spacer()
                    Button {
                        if symbols.count > 1 { symbols.removeAll { $0 == s } }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red.opacity(0.8))
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            HStack(spacing: 8) {
                TextField("输入币种，如 BTC-USDT-SWAP", text: $newSymbol)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                    .foregroundStyle(.primary)
                Button {
                    add(newSymbol)
                } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(.blue)
                }
                .disabled(newSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(popular, id: \.self) { chip($0) }
                }
            }

            Button {
                showAll.toggle()
                if showAll && store.tickers.isEmpty {
                    Task { await store.loadTickers(market: market) }
                }
            } label: {
                Label(showAll ? "收起行情列表" : "从行情列表选择更多", systemImage: showAll ? "chevron.up" : "chevron.down")
                    .font(.caption2).foregroundStyle(.blue)
            }

            if showAll {
                if store.tickers.isEmpty {
                    LoadingHint()
                } else {
                    let majors = ["BTC", "ETH", "SOL", "XRP", "BNB", "DOGE", "LTC", "ADA", "AVAX", "LINK", "DOT", "TON"]
                    let base: (String) -> String = { $0.replacingOccurrences(of: "-USDT-SWAP", with: "").replacingOccurrences(of: "-USDT", with: "") }
                    let majorRows = store.tickers.filter { majors.contains(base($0.symbol)) }
                    let restRows = store.tickers.filter { !majors.contains(base($0.symbol)) }

                    if !majorRows.isEmpty {
                        Text("主流币").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                            ForEach(majorRows, id: \.symbol) { t in chip(t.symbol, compact: true) }
                        }
                    }
                    Text("全部币种（\(restRows.count) 个）").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                        ForEach(restRows, id: \.symbol) { t in chip(t.symbol, compact: true) }
                    }
                }
            }

            Text("AI / 策略会逐个币种分析并按信号交易；会员等级决定单配置币种数上限")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func add(_ raw: String) {
        let s = raw.uppercased().trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !symbols.contains(s) else { return }
        symbols.append(s)
        newSymbol = ""
    }

    private func chip(_ s: String, compact: Bool = false) -> some View {
        let selected = symbols.contains(s)
        return Button {
            if selected {
                if symbols.count > 1 { symbols.removeAll { $0 == s } }
            } else {
                symbols.append(s)
            }
        } label: {
            Text(compact ? s.replacingOccurrences(of: "-USDT-SWAP", with: "") : s)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, compact ? 8 : 10)
                .padding(.vertical, 5)
                .frame(maxWidth: compact ? .infinity : nil)
                .background(selected ? Color.blue : Color(uiColor: .systemGray5), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
