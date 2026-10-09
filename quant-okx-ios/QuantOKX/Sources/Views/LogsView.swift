import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var store: BackendStore
    @State private var filterFailed = false
    @State private var showClearConfirm = false

    private var items: [LogDTO] {
        filterFailed ? store.logs.filter { !$0.success } : store.logs
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("暂无日志",
                                           systemImage: "list.bullet.rectangle",
                                           description: Text(store.connected
                                                             ? "后台启动自动交易后，每一次决策和下单都会记录在这里"
                                                             : "连接后台后显示"))
                } else {
                    List {
                        ForEach(items) { row($0) }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("交易日志")
            .refreshable { await store.refreshAll() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Toggle(isOn: $filterFailed) {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .toggleStyle(.button)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("清空日志", role: .destructive) { showClearConfirm = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(!store.connected)
                }
            }
            .confirmationDialog("清空后台日志？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) { Task { await store.clearLogs() } }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func row(_ log: LogDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(log.success ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(log.action)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(actionColor(log.action).opacity(0.16), in: Capsule())
                        .foregroundStyle(actionColor(log.action))
                    Spacer()
                    Text(log.date, format: .dateTime.hour().minute().second())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Text(log.note)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)

                if log.price > 0 {
                    HStack(spacing: 12) {
                        Text("价 \(fmt(log.price))")
                        if log.size > 0 { Text("量 \(fmt(log.size))") }
                        if let i = log.instId { Text(i).lineLimit(1) }
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func actionColor(_ a: String) -> Color {
        switch a {
        case "开多", "平空": return .green
        case "开空", "平多": return .red
        case "ERROR": return .orange
        case "START", "STOP": return .blue
        default: return .gray
        }
    }

    private func fmt(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.1f", v) }
        if v >= 1 { return String(format: "%.3f", v) }
        return String(format: "%.6f", v)
    }
}
