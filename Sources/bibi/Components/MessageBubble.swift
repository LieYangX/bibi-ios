import SwiftUI

/**
 * 对话消息视图。
 *
 * 用户与助手消息共享统一的圆角与间距系统，通过背景色、对齐方向与聊天气泡的
 * "尾端"锐角来区分身份：用户位于右侧、暖灰底；助手位于左侧、冷灰底。
 *
 * @author xiangwei
 */
struct MessageBubble: View {
    let message: ChatMessage
    let isLastInRun: Bool
    let onCopy: () -> Void

    @State private var isAppeared = false
    @State private var isThinkingAnimating = false
    @State private var isReasoningExpanded = false

    init(message: ChatMessage, isLastInRun: Bool = true, onCopy: @escaping () -> Void) {
        self.message = message
        self.isLastInRun = isLastInRun
        self.onCopy = onCopy
        // 思考过程默认折叠，用户可点击标题栏手动展开
        _isReasoningExpanded = State(initialValue: false)
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
                // 空正文且非流式（历史残留的空消息）不渲染气泡
                if message.text.isEmpty, (message.reasoningContent?.isEmpty ?? true), !message.isStreaming {
                    EmptyView()
                } else {
                    assistantMessage
                }
            }
        }
        .opacity(isAppeared ? 1 : 0)
        .offset(y: isAppeared ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                isAppeared = true
            }
            if isEmptyAssistant {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    isThinkingAnimating = true
                }
            }
        }
        .onChange(of: message.text) { _, _ in
            isThinkingAnimating = false
        }
        .onChange(of: message.reasoningContent) { _, _ in
            isThinkingAnimating = false
        }
        .onChange(of: message.isStreaming) { _, isStreaming in
            // 输出完成后自动折叠思考过程
            if !isStreaming {
                withAnimation(.smooth(duration: 0.25)) {
                    isReasoningExpanded = false
                }
            }
        }
        .onDisappear {
            isThinkingAnimating = false
        }
    }

    /// 是否为空正文且无推理内容的助手消息（用于展示"思考中"状态）。
    private var isEmptyAssistant: Bool {
        message.role == .assistant
            && message.isStreaming
            && message.text.isEmpty
            && (message.reasoningContent?.isEmpty ?? true)
    }

    /// 用户消息气泡形状（右侧尾端收尖）。
    private var userBubbleShape: some Shape {
        UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 16, bottomLeading: 16, bottomTrailing: 6, topTrailing: 16),
            style: .continuous
        )
    }

    /// 助手消息气泡形状（左侧尾端收尖）。
    private var assistantBubbleShape: some Shape {
        UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 16, bottomLeading: 6, bottomTrailing: 16, topTrailing: 16),
            style: .continuous
        )
    }

    private var userMessage: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 72)

                let shape = userBubbleShape

                Text(renderedText)
                    .font(.bibiBody)
                    .foregroundStyle(Color.userBubbleText)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 330, alignment: .leading)
                    .background(Color.userBubbleBackground, in: shape)
                    .overlay(shape.stroke(Color.hairline.opacity(0.65), lineWidth: 0.5))
                    .contextMenu {
                        copyButton
                    }
            }

            Text(timeText)
                .font(.bibiCaption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 16)
        .padding(.vertical, isLastInRun ? 6 : 3)
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 0) {
                let shape = assistantBubbleShape

                VStack(alignment: .leading, spacing: 8) {
                    if let reasoning = trimmedReasoning, !reasoning.isEmpty {
                        if isReasoningExpanded {
                            reasoningSection(reasoning)
                        } else {
                            reasoningCollapsedBar(reasoning)
                        }
                    }

                    if !message.text.isEmpty {
                        Text(renderedText)
                            .font(.bibiBody)
                            .foregroundStyle(.primary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    } else if isEmptyAssistant {
                        thinkingIndicator
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: 560, alignment: .leading)
                .background(Color.assistantBubbleBackground, in: shape)
                .overlay(shape.stroke(Color.hairline.opacity(0.65), lineWidth: 0.5))
                .contextMenu {
                    copyButton
                }

                Spacer(minLength: 24)
            }

            Text(timeText)
                .font(.bibiCaption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, isLastInRun ? 6 : 3)
    }

    /**
     * "思考中"等待状态指示器。
     *
     * 三个圆点依次上下跳动，表示智能体正在生成回复。
     *
     * @author xiangwei
     */
    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.65))
                    .frame(width: 6, height: 6)
                    .offset(y: isThinkingAnimating ? -2.5 : 2.5)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: isThinkingAnimating
                    )
            }
        }
        .frame(height: 14)
    }

    /**
     * 思考信息弱化展示区。
     *
     * 推理内容以更小字号、更低对比度呈现，弱于正文，起到过程可追溯但不喧宾夺主的作用。
     * 输出完成后由 onChange(of: message.isStreaming) 自动折叠，点击标题栏可手动收起。
     *
     * @param reasoning 推理内容
     * @returns 思考信息视图
     * @author xiangwei
     */
    private func reasoningSection(_ reasoning: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            reasoningHeader

            Text(reasoning)
                .font(.bibiCaption)
                .foregroundStyle(.secondary.opacity(0.75))
                .lineSpacing(2)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /**
     * 思考过程标题栏。
     *
     * 流式输出期间展示"思考中"状态，不可折叠；输出完成后可点击切换展开/收起。
     *
     * @returns 思考过程标题栏视图
     * @author xiangwei
     */
    private var reasoningHeader: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) {
                isReasoningExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Label("思考过程", systemImage: "brain")
                    .font(.bibiCaption2Medium)
                    .foregroundStyle(.tertiary)

                if message.isStreaming {
                    Text("思考中…")
                        .font(.bibiCaption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                if !message.isStreaming {
                    Image(systemName: "chevron.up")
                        .font(.bibiCaption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /**
     * 思考过程折叠态摘要栏。
     *
     * 输出完成后展示思考字数摘要，点击可重新展开完整推理内容。
     *
     * @param reasoning 推理内容
     * @returns 折叠态摘要栏视图
     * @author xiangwei
     */
    private func reasoningCollapsedBar(_ reasoning: String) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) {
                isReasoningExpanded = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.bibiCaption2Medium)

                Text("思考过程 · \(reasoning.count) 字")
                    .font(.bibiCaption2)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.bibiCaption2)
            }
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /**
     * 去除首尾空白后的推理内容。
     *
     * @returns 修剪后的推理内容，无内容时为 nil
     * @author xiangwei
     */
    private var trimmedReasoning: String? {
        message.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var toolResult: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: toolResultSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.bibiCaption2Medium)
                .foregroundStyle(toolResultSucceeded ? Color.secondary : Color.errorRed)

            Text(message.toolSummary ?? message.text)
                .font(.bibiCaption2)
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

    private var renderedText: AttributedString {
        (try? AttributedString(markdown: message.text)) ?? AttributedString(message.text)
    }

    /// 消息时间（当天显示 HH:mm，非当天显示 yyyy年M月d日）。
    private var timeText: String {
        AppFormatters.messageTime(message.timestamp)
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
