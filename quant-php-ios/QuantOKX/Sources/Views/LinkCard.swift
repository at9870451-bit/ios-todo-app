import SwiftUI

/// 链接卡片（Orbit genui-guide 的 link_preview 移植）
/// 检测消息里的 URL，主体是链接时渲染成可点击的卡片
struct LinkPreviewCard: View {
    let url: URL

    private var host: String { url.host ?? url.absoluteString }

    var body: some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "safari.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.heroBlue)
                    .frame(width: 40, height: 40)
                    .background(Theme.heroBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(host)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(url.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("在 Safari 中打开")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.heroBlue)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 从文本中提取首个 URL
enum LinkDetect {
    static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, options: [], range: range)?.url
    }

    /// 文本主体是否就是一个链接（去掉链接后剩余文字很短）
    static func isMostlyLink(_ text: String) -> Bool {
        guard let u = firstURL(in: text) else { return false }
        let rest = text.replacingOccurrences(of: u.absoluteString, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.count <= 12
    }
}
