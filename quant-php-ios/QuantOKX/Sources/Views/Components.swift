import SwiftUI

/// 页面容器：统一背景、标题、下拉刷新
struct PageScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.055, blue: 0.09).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        if let subtitle {
                            Text(subtitle).font(.footnote).foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .padding(.top, 6)
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }
}

/// 卡片容器
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

/// 数值统计块
struct StatTile: View {
    let title: String
    let value: String
    var color: Color = .white
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let sub {
                Text(sub).font(.caption2).foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
    }
}

/// 状态徽章
struct StatusBadge: View {
    let text: String
    var color: Color = .gray

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// 行项目：左标题 + 右值
struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .white
    var mono: Bool = false

    var body: some View {
        HStack {
            Text(label).font(.footnote).foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(mono ? .system(.footnote, design: .monospaced) : .footnote)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// 主按钮样式
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = Color(red: 0.29, green: 0.56, blue: 1.0)
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(disabled ? color.opacity(0.3) : color, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
        .disabled(disabled)
    }
}

/// 空状态
struct EmptyHint: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(.white.opacity(0.2))
            Text(text).font(.footnote).foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

/// 加载中
struct LoadingHint: View {
    var body: some View {
        HStack { Spacer(); ProgressView().tint(.white.opacity(0.6)); Spacer() }
            .padding(.vertical, 30)
    }
}

/// 格式化工具
enum Fmt {
    static func price(_ s: String?, digits: Int = 2) -> String {
        guard let s, let d = Double(s) else { return "--" }
        if d >= 1000 {
            let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = digits
            return f.string(from: NSNumber(value: d)) ?? String(d)
        }
        if d >= 1 { return String(format: "%.\(digits)f", d) }
        return String(format: "%.6f", d)
    }

    static func money(_ s: String?) -> String {
        guard let s, let d = Double(s) else { return "--" }
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: d)) ?? s
    }

    static func pct(_ s: String?) -> String {
        guard let s, let d = Double(s) else { return "--" }
        return String(format: "%+.2f%%", d)
    }

    static func pnl(_ s: String?) -> String {
        guard let s, let d = Double(s) else { return "--" }
        return String(format: "%+.4f", d)
    }

    static func pnlColor(_ s: String?) -> Color {
        guard let s, let d = Double(s) else { return .white.opacity(0.6) }
        return d >= 0 ? Color(red: 0.25, green: 0.85, blue: 0.5) : Color(red: 1.0, green: 0.36, blue: 0.36)
    }

    static func time(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "--" }
        // "2026-10-11 22:33:00" → "10-11 22:33"
        if s.count >= 16 {
            let idx = s.index(s.startIndex, offsetBy: 5)
            let idx2 = s.index(s.startIndex, offsetBy: 16)
            return String(s[idx..<idx2]).replacingOccurrences(of: "-", with: "-")
        }
        return s
    }
}
