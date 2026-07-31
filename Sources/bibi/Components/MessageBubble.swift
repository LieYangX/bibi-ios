import SwiftUI

/**
 * 对话消息视图。
 *
 * 用户消息使用紧凑气泡，助手消息使用无头像内容卡片，工具结果作为辅助状态展示。
 *
 * @author xiangwei
 */
struct MessageBubble: View {
    let message: ChatMessage
    let isLastInRun: Bool
    let onCopy: () -> Void

    @State private var isAppeared = false

    init(message: ChatMessage, isLastInRun: Bool = true, onCopy: @escaping () -> Void) {
        self.message = message
        self.isLastInRun = isLastInRun
        self.onCopy = onCopy
    }

    var body: some View {
        Group {
            switch message.role {
            case .toolResult:
                toolResult
            case .system:
                systemMessage
            case .user:
                userMessage
            default:
                assistantMessage
            }
        }
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                isAppeared = true
            }
        }
    }

    private var userMessage: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 72)

            Text(renderedText)
                .font(.bibiBody)
                .foregroundStyle(Color.userBubbleText)
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: 330, alignment: .leading)
                .background {
                    userBubbleShape.fill(Color.userBubbleBackground)
                }
                .contextMenu {
                    copyButton
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, isLastInRun ? 5 : 2)
    }

    private var assistantMessage: some View {
        HStack(alignment: .top) {
            Text(renderedText)
                .font(.bibiAssistant)
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: 560, alignment: .leading)
                .background(
                    Color.assistantBubbleBackground,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.hairline.opacity(0.65), lineWidth: 0.5)
                }
                .contextMenu {
                    copyButton
                }

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, isLastInRun ? 6 : 3)
    }

    private var toolResult: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: toolResultSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(toolResultSucceeded ? Color.secondary : Color.errorRed)

            Text(message.toolSummary ?? message.text)
                .font(.caption2)
                .foregroundStyle(toolResultSucceeded ? .tertiary : .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 2)
    }

    private var systemMessage: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.errorRed)

            Text(renderedText)
                .font(.bibiCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.errorRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
    }

    private var userBubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 19,
            bottomLeadingRadius: 19,
            bottomTrailingRadius: isLastInRun ? 6 : 19,
            topTrailingRadius: 19,
            style: .continuous
        )
    }

    private var renderedText: AttributedString {
        (try? AttributedString(markdown: message.text)) ?? AttributedString(message.text)
    }

    private var copyButton: some View {
        Button(action: onCopy) {
            Label("复制", systemImage: "doc.on.doc")
        }
    }

    private var toolResultSucceeded: Bool {
        !(message.toolSummary ?? "").contains("失败")
    }

}
