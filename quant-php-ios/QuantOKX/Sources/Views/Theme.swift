import SwiftUI
import UIKit

/// 全局设计系统：Apple 极简白 + Liquid Glass 液态玻璃
/// 主色 #FFFFFF / #F5F5F7 · 强调 #FF9500 · 主渐变 #3478F6 → #67C7FF → #FF9500
enum Theme {
    // MARK: 品牌强调色

    /// 强调橙 #FF9500
    static let accent = Color(red: 1.0, green: 0.584, blue: 0.0)
    /// 深橙（渐变深端）
    static let accentDeep = Color(red: 1.0, green: 0.463, blue: 0.0)
    /// 渐变蓝 #3478F6
    static let heroBlue = Color(red: 0.204, green: 0.471, blue: 0.965)
    /// 渐变天空蓝 #67C7FF
    static let heroSky = Color(red: 0.404, green: 0.780, blue: 1.0)
    /// 品牌蓝（旧引用兼容）
    static let brandBlue = heroBlue
    /// 浅灰 #F5F5F7
    static let bgLight = Color(red: 0.961, green: 0.961, blue: 0.969)

    // MARK: 蓝橙主渐变（主要按钮 / 视觉焦点）

    static let heroGradient = LinearGradient(
        colors: [heroBlue, heroSky, accent],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let brandGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // MARK: 自适应底色（浅色纯白系 / 深色系统暗色组）

    /// 页面底：浅色 #F5F5F7 系
    static var bg: Color { Color(uiColor: .systemGroupedBackground) }
    /// 卡片：浅色纯白
    static var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    /// 内嵌块
    static var inset: Color { Color(uiColor: .tertiarySystemGroupedBackground) }
}

// MARK: - Liquid Glass 液态玻璃

extension View {
    /// 液态玻璃面板：iOS 26 用原生 glassEffect，旧系统用磨砂材质 + 高光描边 + 柔影
    @ViewBuilder
    func glassPanel(_ radius: CGFloat = 18) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        }
    }

    /// 白玉卡片：自适应纯白/暗色卡片 + 柔影（比玻璃更实的容器）
    func solidCard(_ radius: CGFloat = 18) -> some View {
        self
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 9, x: 0, y: 3)
            .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
    }
}

/// 按压缩放样式
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
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

// MARK: - 悬浮玻璃圆形按钮

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

/// 空状态提示
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
                if disabled {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Theme.accent.opacity(0.3))
                } else {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Theme.heroGradient)
                        .overlay(
                            // 顶部高光：玻璃质感
                            LinearGradient(colors: [.white.opacity(0.28), .clear],
                                           startPoint: .top, endPoint: .center)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        )
                        .shadow(color: Theme.accent.opacity(0.32), radius: 9, x: 0, y: 4)
                }
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(disabled)
    }
}
