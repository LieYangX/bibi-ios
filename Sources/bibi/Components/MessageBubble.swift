import SwiftUI

/**
 * 消息气泡
 *
 * 三种角色三种样式：
 * - 用户消息：右对齐，暖金纯色背景
 * - 助手消息：左对齐，.thinMaterial 背景
 * - 工具消息：左对齐，.regularMaterial + 边框
 *
 * @author xiangwei
 */
struct MessageBubble: View {
    let message: ChatMessage
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // 消息内容
                Text(message.text)
                    .font(.bibiBody)
                    .foregroundColor(message.role == .user ? .userBubbleText : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(backgroundView)
                    .contextMenu {
                        Button(action: onCopy) {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                    }

                // 工具摘要
                if let summary = message.toolSummary {
                    Text(summary)
                        .font(.bibiCaption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                }
            }

            if message.role == .assistant || message.role == .toolCall || message.role == .toolResult {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch message.role {
        case .user:
            Color.userBubbleBackground
                .clipShape(RoundedRectangle(cornerRadius: 16))
        case .assistant:
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
        case .toolCall, .toolResult:
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                )
        case .system:
            Color.secondary.opacity(0.1)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}
