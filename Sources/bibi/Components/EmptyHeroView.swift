import SwiftUI

/**
 * 空对话英雄区
 *
 * 首次启动或无消息时展示：品牌标志、问候语、模式选择按钮、推荐问题。
 *
 * @author xiangwei
 */
struct EmptyHeroView: View {
    let userName: String
    let pcUserName: String?
    let onQuickMode: () -> Void
    let onExpertMode: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 40)

                // Logo
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 48))
                    .foregroundColor(.brandGold)

                // 问候
                VStack(spacing: 8) {
                    Text("你好，\(userName)")
                        .font(.bibiLargeTitle)
                        .foregroundColor(.primary)

                    if let pcUser = pcUserName {
                        Text("我是小笔，已连接到 \(pcUser) 的 PC")
                            .font(.bibiBody)
                            .foregroundColor(.secondary)
                    } else {
                        Text("我是小笔，当前未连接到 PC 记账服务")
                            .font(.bibiBody)
                            .foregroundColor(.secondary)
                    }
                }

                // 模式按钮
                HStack(spacing: 16) {
                    Button("快速", action: onQuickMode)
                        .buttonStyle(.glassProminent)

                    Button("专家", action: onExpertMode)
                        .buttonStyle(.glass)
                }

                // 推荐问题
                VStack(alignment: .leading, spacing: 12) {
                    Text("试试这样问我：")
                        .font(.bibiCaption)
                        .foregroundColor(.secondary)

                    SuggestionChip(text: "我这个月花了多少钱？")
                    SuggestionChip(text: "我的总资产有多少？")
                    SuggestionChip(text: "上个月支出最多的是哪类？")
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

/**
 * 推荐问题标签
 */
private struct SuggestionChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.caption2)
                .foregroundColor(.brandGold)

            Text(text)
                .font(.bibiCaption)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.brandGoldLight)
        .clipShape(Capsule())
    }
}
