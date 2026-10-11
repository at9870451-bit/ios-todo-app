import SwiftUI

/// AI 交易：自动交易状态 + 配置列表 + 信号记录
struct AiTradeView: View {
    @EnvironmentObject var store: BackendStore

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(uiColor: .systemGroupedBackground)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("AI 交易")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                            Text("自动分析 · 自动下单 · 风控护航")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)

                        if let state = store.aiAutoState {
                            // 状态卡
                            Card {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: state.running ? "cpu.fill" : "cpu")
                                            .foregroundStyle(state.running ? Color.green : .gray)
                                        Text(state.running ? "自动交易运行中" : "自动交易未运行")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        StatusBadge(text: "\(state.runningCount)/\(state.autoConfigCount) 运行",
                                                    color: state.running ? .green : .gray)
                                    }
                                    HStack(spacing: 10) {
                                        StatTile(title: "本地交易", value: state.localTradingEnabled ? "开启" : "关闭",
                                                 color: state.localTradingEnabled ? Color.green : .gray)
                                        StatTile(title: "实盘开关", value: state.liveTradingEnabled ? "开启" : "关闭",
                                                 color: state.liveTradingEnabled ? .orange : .gray)
                                        StatTile(title: "杠杆上限", value: "\(state.maxLeverage)x")
                                    }
                                    if state.emergencyStop {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                                            Text("全局紧急停止已开启，所有开仓被禁止")
                                                .font(.caption).foregroundStyle(.red.opacity(0.9))
                                        }
                                    }
                                }
                            }

                            // 一键执行
                            HStack(spacing: 10) {
                                PrimaryButton(title: "执行一轮", icon: "play.circle.fill") {
                                    Task { await store.runAiOnce(0) }
                                }
                                PrimaryButton(title: "刷新状态", icon: "arrow.clockwise", color: Color(uiColor: .systemGray5)) {
                                    Task { await store.loadAiAutoState() }
                                }
                            }

                            NavCard(icon: "checklist.bounce", title: "AI 交易复盘", desc: "每笔 AI 交易的出入场与盈亏回顾", color: .purple) {
                                AiReviewsView()
                            }

                            // 配置列表
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("AI 配置").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(state.configs.count) 个").font(.caption).foregroundStyle(.secondary)
                                    NavigationLink {
                                        AiConfigEditView(existingId: nil)
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(Color.blue)
                                    }
                                }
                                if state.configs.isEmpty {
                                    EmptyHint(icon: "cpu", text: "暂无 AI 自动交易配置\n点右上角 + 创建，或使用平台免费 AI")
                                } else {
                                    ForEach(state.configs) { c in
                                        aiConfigCard(c)
                                    }
                                }
                            }

                            // 最近信号
                            VStack(alignment: .leading, spacing: 8) {
                                Text("最近信号").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                if state.recentSignals.isEmpty {
                                    EmptyHint(icon: "waveform.path.ecg", text: "暂无 AI 信号")
                                } else {
                                    ForEach(state.recentSignals) { s in
                                        signalCard(s)
                                    }
                                }
                            }
                        } else {
                            LoadingHint()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .refreshable { await store.loadAiAutoState() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task { await store.loadAiAutoState() }
        }
    }

    private func aiConfigCard(_ c: AiConfigRow) -> some View {
        Card(padding: 13) {
            VStack(spacing: 9) {
                HStack {
                    Text(c.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    StatusBadge(text: c.mode, color: c.mode == "auto" ? .purple : .gray)
                    if c.running == true {
                        StatusBadge(text: "运行中", color: Color.green)
                    }
                    Spacer()
                    if let last = c.lastSignal, !last.isEmpty {
                        StatusBadge(text: last, color: last == "BUY" ? .green : (last == "SELL" ? .red : .gray))
                    }
                }
                HStack {
                    InfoRow(label: "模型", value: c.model ?? "--")
                    InfoRow(label: "交易对", value: c.autoSymbol ?? "--", mono: true)
                }
                HStack {
                    InfoRow(label: "周期", value: c.autoInterval ?? "--")
                    InfoRow(label: "杠杆", value: "\(c.leverage ?? 1)x")
                    InfoRow(label: "资金", value: "\(Int(c.capitalUsdt ?? 0)) U")
                }
                HStack {
                    Text("运行 \(c.runCount ?? 0) · 交易 \(c.tradeCount ?? 0)")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if let err = c.errorMessage, !err.isEmpty {
                        Text(err).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                    }
                }
                HStack(spacing: 10) {
                    if c.running == true {
                        Button {
                            Task { await store.stopAi(c.id) }
                        } label: {
                            Text("停止")
                                .font(.caption.weight(.semibold)).foregroundStyle(.red)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(Color.red.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                        }
                    } else {
                        Button {
                            Task { await store.startAi(c.id) }
                        } label: {
                            Text("启动")
                                .font(.caption.weight(.semibold)).foregroundStyle(Color.green)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(Color.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                    Button {
                        Task { await store.runAiOnce(c.id) }
                    } label: {
                        Text("执行一轮")
                            .font(.caption.weight(.semibold)).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 9))
                    }
                    NavigationLink {
                        AiConfigEditView(existingId: c.id)
                    } label: {
                        Text("编辑")
                            .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                HStack(spacing: 10) {
                    NavigationLink {
                        AiDiagnoseView(configId: c.id)
                    } label: {
                        Text("连接诊断")
                            .font(.caption.weight(.semibold)).foregroundStyle(.cyan)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
        }
    }

    private func signalCard(_ s: AiSignalRow) -> some View {
        Card(padding: 12) {
            VStack(spacing: 6) {
                HStack {
                    Text(s.symbol).font(.subheadline.monospaced()).foregroundStyle(.primary)
                    StatusBadge(text: s.signal, color: s.signal == "BUY" ? .green : (s.signal == "SELL" ? .red : .gray))
                    Spacer()
                    Text("置信 \(String(format: "%.0f%%", s.confidence.doubleValue * 100))")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    if s.executed == 1 {
                        StatusBadge(text: "已执行", color: .blue)
                    }
                }
                if let reason = s.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).lineLimit(3)
                }
                HStack {
                    Text(Fmt.time(s.createdAt)).font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    if let e = s.entry?.value, !e.isEmpty {
                        Text("入场 \(Fmt.price(e))").font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
