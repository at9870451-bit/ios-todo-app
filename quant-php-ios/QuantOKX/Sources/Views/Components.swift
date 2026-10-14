import SwiftUI

/// 页面容器：分组浅灰背景 + 标题 + 下拉刷新（Apple 风格）
struct PageScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            ZStack { Color(uiColor: .systemGroupedBackground).ignoresSafeArea(); LinearGradient(colors: [Color.white.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                        if let subtitle {
                            Text(subtitle).font(.footnote).foregroundStyle(.secondary)
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

/// 卡片容器：纯白圆角卡片、无描边
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

/// 主按钮：系统蓝、白字、圆角
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = Theme.accent
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
            .background(disabled ? AnyShapeStyle(color.opacity(0.3)) : AnyShapeStyle(Theme.heroGradient), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: disabled ? .clear : Theme.accent.opacity(0.28), radius: 7, x: 0, y: 3)
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
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(.quaternary)
            Text(text).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

// MARK: - Design Tokens（参考稿：苹果白 × 橙 × 蓝橙渐变 × Liquid Glass）

extension Theme {
    /// 统一圆角体系：视口/大卡 26 · 面板 18 · 卡片 14 · 小件 10
    static let radiusXL: CGFloat = 26
    static let radiusL: CGFloat = 18
    static let radiusM: CGFloat = 14
    static let radiusS: CGFloat = 10
    /// 统一页面边距
    static let pagePadding: CGFloat = 16
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

/// 底栏 / 输入栏统一玻璃（材质 + 顶部高光线）
extension View {
    @ViewBuilder
    func glassBar() -> some View {
        self
            .background(.regularMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(height: 0.8)
                    .blur(radius: 0.5)
                    .allowsHitTesting(false)
            }
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
        return d >= 0 ? Color.green : Color.red
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
