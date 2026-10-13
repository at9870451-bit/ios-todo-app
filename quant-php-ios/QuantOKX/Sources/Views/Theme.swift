import SwiftUI

/// 全局主题常量（卡片/内嵌底色）
enum Theme {
    /// 主色：橙
    static let accent = Color(red: 1.0, green: 0.49, blue: 0.10)
    /// 品牌蓝（渐变点缀用）
    static let brandBlue = Color(red: 0.04, green: 0.52, blue: 1.0)
    /// 页面底（冷灰分组底，衬托白色卡片）
    static let bg = Color(red: 0.955, green: 0.966, blue: 0.977)
    /// 卡片：纯白
    static let card = Color.white
    /// 内嵌块
    static let inset = Color(red: 0.933, green: 0.938, blue: 0.946)
}

/// 空状态提示
struct DEmpty: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent)
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

/// 主按钮
struct DButton: View {
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
            .padding(.vertical, 13)
            .background(disabled ? color.opacity(0.3) : color, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .foregroundStyle(.white)
        }
        .disabled(disabled)
    }
}
