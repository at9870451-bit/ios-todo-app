import SwiftUI
import UIKit

// MARK: ============================================================
// MARK: Design Tokens —— 苹果白 × 活力橙 × 蓝橙渐变 × Liquid Glass
// MARK: ============================================================

enum Theme {
    // MARK: 品牌色板（唯一色系：苹果白 / 中性灰 / 活力橙 / 蓝橙渐变）

    /// 活力橙 #FF9500 —— 全 App 强调色
    static let accent = Color(red: 1.0, green: 0.584, blue: 0.0)
    /// 深橙（渐变深端 / 警示强调）
    static let accentDeep = Color(red: 1.0, green: 0.463, blue: 0.0)
    /// 渐变蓝 #3478F6
    static let heroBlue = Color(red: 0.204, green: 0.471, blue: 0.965)
    /// 渐变天空蓝 #67C7FF
    static let heroSky = Color(red: 0.404, green: 0.780, blue: 1.0)
    /// 品牌蓝（旧引用兼容）
    static let brandBlue = heroBlue
    /// 苹果白 #FFFFFF
    static let white = Color.white
    /// 浅灰 #F5F5F7
    static let bgLight = Color(red: 0.961, green: 0.961, blue: 0.969)

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

    static let heroGradient = LinearGradient(
        colors: [heroBlue, heroSky, accent],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let brandGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// 渐变高光（叠在渐变卡上的顶部玻璃光泽）
    static let glossGradient = LinearGradient(
        colors: [Color.white.opacity(0.26), Color.clear],
        startPoint: .top, endPoint: .center
    )

    // MARK: 自适应底色（浅色纯白系 / 深色系统暗色组）

    static var bg: Color { Color(uiColor: .systemGroupedBackground) }
    static var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var inset: Color { Color(uiColor: .tertiarySystemGroupedBackground) }
    static var hairline: Color { Color(uiColor: .separator) }
    static var fillGray: Color { Color(uiColor: .systemGray5) }

    // MARK: 统一圆角体系

    static let radiusXS: CGFloat = 10   // 小件（胶囊 / 输入块 / 图标）
    static let radiusS: CGFloat = 12    // 卡片内块
    static let radiusM: CGFloat = 16    // 信息卡
    static let radiusL: CGFloat = 20    // 面板 / 底栏
    static let radiusXL: CGFloat = 26   // 大视口 / Hero 卡
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
    static let shadowGlow: Color = accent.opacity(0.30)
    /// 渐变高光条（液态玻璃顶部细线）
    static var glossLine: Color { Color.white.opacity(0.55) }
}

// MARK: - Liquid Glass 液态玻璃

extension View {
    /// 液态玻璃面板：iOS 26 用原生 glassEffect，旧系统磨砂材质 + 高光描边 + 柔影
    @ViewBuilder
    func glassPanel(_ radius: CGFloat = Theme.radiusL) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            glassLegacy(radius)
        }
    }

    /// iOS 26 之前的玻璃质感（材质 + 顶部高光 + 柔影），与原生 glassEffect 视觉一致
    func glassLegacy(_ radius: CGFloat = Theme.radiusL) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.glossLine.opacity(0.6), lineWidth: 0.8)
            )
            .shadow(color: Theme.shadowFloat.0, radius: Theme.shadowFloat.1, x: 0, y: Theme.shadowFloat.2)
    }

    /// 白玉卡片：自适应纯白/暗色卡片 + 双柔影
    func solidCard(_ radius: CGFloat = Theme.radiusM) -> some View {
        self
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Theme.shadowCard.0, radius: Theme.shadowCard.1, x: 0, y: Theme.shadowCard.2)
            .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
    }

    /// 核心功能卡：蓝橙渐变 + 顶部玻璃光泽 + 品牌光晕
    func heroCard(_ radius: CGFloat = Theme.radiusL) -> some View {
        self
            .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                Theme.glossGradient
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
            )
            .shadow(color: Theme.shadowGlow, radius: 12, x: 0, y: 6)
    }

    /// 底栏 / 输入栏统一玻璃（材质 + 顶部高光线）
    @ViewBuilder
    func glassBar() -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous))
        } else {
            self
                .background(.regularMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.glossLine)
                        .frame(height: 0.8)
                        .blur(radius: 0.5)
                        .allowsHitTesting(false)
                }
                .shadow(color: Theme.shadowFloat.0, radius: Theme.shadowFloat.1, x: 0, y: Theme.shadowFloat.2)
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
                RoundedRectangle(cornerRadius: Theme.radiusXS, style: .continuous)
                    .fill(disabled ? AnyShapeStyle(Theme.fillGray) : AnyShapeStyle(Theme.heroGradient))
                    .overlay(
                        Theme.glossGradient
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusXS, style: .continuous))
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
