import SwiftUI

/// 页面容器：原生导航标题下的白色内容区（保留给旧页面使用）
struct PageScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(Theme.largeTitle)
                            .foregroundStyle(.primary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                    content()
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, Theme.spaceXXL)
            }
        }
    }
}

/// 卡片容器：白色主体 + 玻璃高光 + 统一圆角
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.cardPadding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.72), lineWidth: 0.8)
            }
            .shadow(color: Theme.shadowCard.0, radius: Theme.shadowCard.1, x: 0, y: Theme.shadowCard.2)
    }
}

/// 数值统计块
struct StatTile: View {
    let title: String
    let value: String
    var color: Color = .primary
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let sub {
                Text(sub).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: Theme.radiusS, style: .continuous))
    }
}

/// 状态徽章
struct StatusBadge: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// 行项目：左标题 + 右值
struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(mono ? .system(.footnote, design: .monospaced) : .footnote)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// 主按钮：蓝橙渐变、玻璃高光、统一按压反馈
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = Theme.accent
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background {
                Capsule()
                    .fill(disabled ? AnyShapeStyle(Theme.fillGray) : AnyShapeStyle(Theme.heroGradient))
                    .overlay {
                        if !disabled {
                            Theme.glossGradient
                                .clipShape(Capsule())
                        }
                    }
                    .shadow(color: disabled ? .clear : Theme.shadowGlow, radius: 9, x: 0, y: 4)
            }
            .foregroundStyle(disabled ? Color.secondary : Color.white)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(disabled)
    }
}

/// 空状态
struct EmptyHint: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.heroGradient.opacity(0.11)).frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.heroBlue)
            }
            Text(text).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

/// 橙色渐变圆角方块图标（快捷入口 / 列表行图标；参考稿核心组件）
struct SquircleIcon: View {
    let system: String
    var size: CGFloat = 40
    var tinted: Bool = false   // true = 浅橙底橙 glyph（辅助样式）

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(tinted ? AnyShapeStyle(Theme.accent.opacity(0.13)) : AnyShapeStyle(Theme.brandGradient))
            Image(systemName: system)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(tinted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white))
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(tinted ? 0 : 0.22), radius: 5, x: 0, y: 3)
    }
}

/// 蓝橙渐变欢迎卡：标题 + 副标题 + 右侧圆形箭头钮（参考稿首页 hero）
struct HeroBanner: View {
    let title: String
    var subtitle: String = ""
    var icon: String = "chevron.right"
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let action {
                Button {
                    Haptics.light()
                    action()
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.26), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.8))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(17)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous))
        .overlay(
            // 顶部高光
            LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous))
                .allowsHitTesting(false)
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous)
            .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8))
        .shadow(color: Theme.accent.opacity(0.26), radius: 12, x: 0, y: 6)
    }
}

/// 列表行（squircle 图标 + 标题/副标题 + chevron；外层配 solidCard / List 使用）
struct ListRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var size: CGFloat = 38
    var tinted: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            SquircleIcon(system: icon, size: size, tinted: tinted)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .contentShape(Rectangle())
    }
}

/// 辅助按钮（浅橙底橙字；参考稿「辅助按钮」）
struct AuxButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// 加载中
struct LoadingHint: View {
    var body: some View {
        HStack { Spacer(); ProgressView().tint(.secondary); Spacer() }
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
        guard let s, let d = Double(s) else { return .secondary }
        return d >= 0 ? Theme.ok : Theme.danger
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
