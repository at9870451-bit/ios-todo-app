import SwiftUI

/// 策略运行监控：每个策略最近一轮执行状态（对齐网页端 strategy/runner）
struct StrategyMonitorView: View {
    @EnvironmentObject var store: BackendStore

    var body: some View {
        PageScaffold(title: "运行监控", subtitle: "策略引擎最近一轮执行状态") {
            if store.strategyMonitor.isEmpty {
                EmptyHint(icon: "antenna.radiowaves.left.and.right", text: "暂无策略\n先在策略列表创建并启动")
            } else {
                ForEach(store.strategyMonitor) { m in
                    Card(padding: 12) {
                        VStack(spacing: 8) {
                            HStack {
                                Text(m.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                StatusBadge(text: m.enabled ? "已启用" : "已停用", color: m.enabled ? .green : .gray)
                                Spacer()
                                StatusBadge(text: statusText(m.status), color: statusColor(m.status))
                            }
                            HStack {
                                InfoRow(label: "交易对", value: m.symbol.value, mono: true)
                                InfoRow(label: "市场", value: m.marketType == "swap" ? "永续" : "现货")
                                InfoRow(label: "周期", value: m.interval)
                            }
                            HStack {
                                InfoRow(label: "方向", value: directionText(m.directionMode))
                                InfoRow(label: "杠杆", value: "\(m.leverage)x")
                                InfoRow(label: "仓位", value: "\(m.positionPercent.value)%")
                            }
                            HStack {
                                InfoRow(label: "最近信号", value: m.lastSignal ?? "--")
                                InfoRow(label: "最近执行", value: m.lastRunAt.map { Fmt.time($0) } ?? "从未")
                            }
                            if let err = m.errorMessage, !err.isEmpty {
                                Text(err).font(.caption2).foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("运行监控")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadStrategyMonitor() }
        .refreshable { await store.loadStrategyMonitor() }
    }

    private func statusText(_ s: String) -> String {
        switch s {
        case "SUCCESS": return "执行成功"
        case "ERROR": return "执行出错"
        case "RUNNING": return "执行中"
        case "NEVER": return "从未执行"
        default: return s
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "SUCCESS": return Color(red: 0.25, green: 0.85, blue: 0.5)
        case "ERROR": return .red
        case "RUNNING": return .blue
        default: return .gray
        }
    }

    private func directionText(_ d: String) -> String {
        switch d {
        case "long_only": return "只做多"
        case "short_only": return "只做空"
        case "both", "long_short": return "多空双向"
        default: return d
        }
    }
}
