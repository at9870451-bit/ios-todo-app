import SwiftUI
import UIKit

// MARK: ============================================================
// MARK: Design Tokens —— 苹果白 × 活力橙 × 蓝橙渐变 × Liquid Glass
// MARK: ============================================================

enum Theme {
    // MARK: 品牌色板（唯一色系：苹果白 / 中性灰 / 活力橙 / 蓝橙渐变）

    /// 活力橙 #FF9500 —— 唯一强调色
    static let accent = Color(red: 1.0, green: 0.584, blue: 0.0)
    /// 深橙（破坏性操作，仍在橙色系内）
    static let accentDeep = Color(red: 1.0, green: 0.463, blue: 0.0)
    /// 辅助蓝 #007AFF
    static let heroBlue = Color(red: 0.0, green: 0.478, blue: 1.0)
    /// 旧引用兼容（统一为辅助蓝）
    static let heroSky = heroBlue
    static let brandBlue = heroBlue
    /// 卡片白 #FFFFFF
    static let white = Color.white
    /// 苹果白背景 #F2F2F7
    static let bgLight = Color(red: 0.949, green: 0.949, blue: 0.969)
    /// 主文字 #1C1C1E / 次文字 #8E8E93
    static let textPrimary = Color(red: 0.110, green: 0.110, blue: 0.118)
    static let textSecondary = Color(red: 0.557, green: 0.557, blue: 0.576)
    /// 玻璃底色 rgba(255,255,255,0.65)
    static let glassFill = Color.white.opacity(0.65)

    // MARK: 语义色（全部落在 蓝-橙 系内，不引入第四种色系）

    /// 正向状态（已连接 / 已配置 / 已支付）→ 渐变蓝
    static let ok = heroBlue
    /// 待处理 / 提示 → 橙
    static let warn = accent
    /// 破坏性操作（删除 / 退出）→ 深橙（与品牌同色系，避免引入红色系）
    static let danger = accentDeep
    /// 破坏性操作浅底
    static var dangerFill: Color { accentDeep.opacity(0.10) }

    // MARK: 蓝橙主渐变（主按钮 / 核心功能卡 / 视觉焦点）

    /// 主渐变 #007AFF → #FF9500（135°），仅主按钮 / 选中态 / 焦点
    static let heroGradient = LinearGradient(
        colors: [heroBlue, accent],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// 与主渐变一致（旧引用兼容）
    static let brandGradient = heroGradient
    /// 渐变高光（叠在渐变卡上的顶部玻璃光泽）
    static let glossGradient = LinearGradient(
        colors: [Color.white.opacity(0.26), Color.clear],
        startPoint: .top, endPoint: .center
    )

    // MARK: 自适应底色（固定苹果白系，不受深色模式影响）

    static var bg: Color { bgLight }
    static var card: Color { Color.white }
    static var inset: Color { Color.white.opacity(0.72) }
    static var hairline: Color { textSecondary.opacity(0.16) }
    static var fillGray: Color { textSecondary.opacity(0.16) }

    // MARK: 统一圆角体系（卡片 24 连续圆角）

    static let radiusXS: CGFloat = 12
    static let radiusS: CGFloat = 14
    static let radiusM: CGFloat = 16
    static let radiusL: CGFloat = 20
    static let radiusXL: CGFloat = 24   // 卡片统一 24pt
    /// 旧引用兼容
    static let radiusXXXL: CGFloat = 34

    // MARK: 统一间距体系

    static let spaceXXS: CGFloat = 4
    static let spaceXS: CGFloat = 8
    static let spaceS: CGFloat = 10
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 20
    static let spaceXXL: CGFloat = 24
    /// 页面统一左右边距
    static let pagePadding: CGFloat = 16
    /// 卡片统一内边距
    static let cardPadding: CGFloat = 14
    /// 卡片间统一纵向间距
    static let cardSpacing: CGFloat = 12

    // MARK: 统一字号层级

    /// 页面大标题
    static let largeTitle: Font = .system(size: 28, weight: .bold, design: .rounded)
    /// 卡片主标题
    static let cardTitle: Font = .system(size: 17, weight: .bold, design: .rounded)
    /// 数字 / 金额强调
    static let numeric: Font = .system(size: 20, weight: .heavy, design: .rounded)

    // MARK: 统一阴影体系

    /// 卡片柔影
    static let shadowCard: (Color, CGFloat, CGFloat) = (Color.black.opacity(0.05), 9, 3)
    /// 悬浮件（Tab 栏 / 输入栏 / 玻璃按钮）
    static let shadowFloat: (Color, CGFloat, CGFloat) = (Color.black.opacity(0.07), 12, 5)
    /// 品牌光晕（渐变按钮）
    static let shadowGlow: Color = heroBlue.opacity(0.30)
    /// 渐变高光条（液态玻璃顶部细线）
    static var glossLine: Color { Color.white.opacity(0.55) }
}

// MARK: - Liquid Glass 液态玻璃

extension View {
    /// 液态玻璃面板：毛玻璃 rgba(255,255,255,0.65) + 模糊 + 1pt 白色内描边 + 轻微阴影
    @ViewBuilder
    func glassPanel(_ radius: CGFloat = Theme.radiusXL) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(Theme.glassFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 5)
    }

    /// 白卡：#FFFFFF + 1pt 玻璃内描边 + 柔影
    func solidCard(_ radius: CGFloat = Theme.radiusXL) -> some View {
        self
            .background(Color.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 4)
    }

    /// 主渐变按钮底（蓝橙 135°）+ 胶囊高光
    func heroCard(_ radius: CGFloat = Theme.radiusXL) -> some View {
        self
            .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                Theme.glossGradient
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .allowsHitTesting(false)
            )
            .shadow(color: Theme.heroBlue.opacity(0.30), radius: 12, x: 0, y: 6)
    }

    /// 底栏 / 输入栏：全宽毛玻璃 + 顶部 1pt 白高光
    @ViewBuilder
    func glassBar() -> some View {
        self
            .background(.ultraThinMaterial)
            .background(Theme.glassFill)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
    }
}

/// 按压缩放样式（全 App 统一触感动效）
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 触感反馈

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func tap() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: ============================================================
// MARK: 基础组件
// MARK: ============================================================

/// 悬浮玻璃圆形按钮（视口右上角复位等）
struct GlassIconButton: View {
    let icon: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
        }
        .glassPanel(size / 2)
    }
}

/// 空状态提示（渐变圆环 + 文案）
struct DEmpty: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.heroGradient.opacity(0.12))
                    .frame(width: 72, height: 72)
                Circle()
                    .strokeBorder(Theme.heroGradient.opacity(0.25), lineWidth: 1)
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.heroGradient)
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// 主按钮：蓝橙渐变 + 高光 + 柔影（视觉焦点）
struct DButton: View {
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
                    .overlay(
                        Theme.glossGradient
                            .clipShape(Capsule())
                            .opacity(disabled ? 0 : 1)
                    )
                    .shadow(color: disabled ? .clear : Theme.shadowGlow, radius: 9, x: 0, y: 4)
            }
            .foregroundStyle(disabled ? Color.secondary : Color.white)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(disabled)
    }
}
