import SwiftUI

/// AI 连接诊断：逐步定位「AI 收不到」卡在哪一步
struct AiDiagnoseView: View {
    @EnvironmentObject var store: BackendStore
    let configId: Int
    @State private var message = ""
    @State private var finished = false

    var body: some View {
        PageScaffold(title: "AI 连接诊断", subtitle: "逐步定位：配置 → 密钥 → 地址 → 代理 → DNS → 请求 → 解析") {
            if !message.isEmpty {
                Card(padding: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(message).font(.caption).foregroundStyle(.primary)
                    }
                }
            }
            if let d = store.aiDiagnose {
                Card {
                    HStack(spacing: 9) {
                        Image(systemName: d.success ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(d.success ? Color.green : .orange)
                        Text(d.success ? "总体：连接正常" : "总体：存在问题")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Spacer()
                        Text("配置 #\(d.configId)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(d.steps.enumerated()), id: \.offset) { _, s in
                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: s.status == "passed" ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .foregroundStyle(s.status == "passed" ? Color.green : .red)
                                Text(s.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Spacer()
                                StatusBadge(text: s.status == "passed" ? "通过" : "失败",
                                            color: s.status == "passed" ? .green : .red)
                            }
                            Text(s.message).font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if let out = d.modelOutput, !out.isEmpty {
                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("模型输出").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(out).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else if !finished {
                LoadingHint()
            }
        }
        .navigationTitle("AI 连接诊断")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            message = await store.runAiDiagnose(id: configId)
            finished = true
        }
    }
}

/// AI 交易复盘：每笔 AI 自动交易的出入场与盈亏回顾
struct AiReviewsView: View {
    @EnvironmentObject var store: BackendStore

    var body: some View {
        PageScaffold(title: "AI 交易复盘", subtitle: "AI 自动交易平仓后自动生成复盘记录") {
            if store.aiReviews.isEmpty {
                EmptyHint(icon: "checklist", text: "暂无复盘记录\nAI 自动交易完成平仓后自动生成")
            } else {
                ForEach(store.aiReviews) { r in
                    Card(padding: 12) {
                        VStack(spacing: 8) {
                            HStack {
                                Text(r.symbol.value).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                StatusBadge(text: r.status, color: reviewColor(r.status))
                                Spacer()
                                Text(Fmt.pnl(r.pnl?.value))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(Fmt.pnlColor(r.pnl?.value))
                            }
                            HStack {
                                InfoRow(label: "方向", value: sideText(r.positionSide?.value))
                                InfoRow(label: "杠杆", value: "\(r.leverage ?? 1)x")
                                InfoRow(label: "收益率", value: Fmt.pct(r.pnlPercent?.value))
                            }
                            HStack {
                                InfoRow(label: "入场", value: Fmt.price(r.entryPrice?.value), mono: true)
                                InfoRow(label: "出场", value: Fmt.price(r.exitPrice?.value), mono: true)
                                InfoRow(label: "数量", value: r.quantity?.value ?? "--", mono: true)
                            }
                            if let txt = r.reviewText, !txt.isEmpty {
                                Text(txt).font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(4)
                            }
                            if let err = r.errorMessage, !err.isEmpty {
                                Text(err).font(.caption2).foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
                            }
                            HStack {
                                Text(Fmt.time(r.createdAt)).font(.caption2).foregroundStyle(.tertiary)
                                Spacer()
                                if let rv = r.reviewedAt, !rv.isEmpty {
                                    Text("复盘 \(Fmt.time(rv))").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("AI 交易复盘")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadAiReviews() }
        .refreshable { await store.loadAiReviews() }
    }

    private func reviewColor(_ s: String) -> Color {
        switch s {
        case "SUCCESS": return Color.green
        case "FAILED": return .red
        default: return .orange
        }
    }

    private func sideText(_ s: String?) -> String {
        let v = (s ?? "").uppercased()
        if v.contains("SHORT") { return "做空" }
        if v.contains("LONG") { return "做多" }
        return v.isEmpty ? "--" : v
    }
}
