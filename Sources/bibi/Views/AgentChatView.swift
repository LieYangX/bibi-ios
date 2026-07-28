import SwiftUI

/**
 * 主聊天页
 *
 * 包含连接横幅、消息列表（或空英雄区）、输入工具栏。
 *
 * @author xiangwei
 */
struct AgentChatView: View {
    @State private var agent: AgentService
    @State private var messageText = ""
    @State private var showConversations = false

    init(agent: AgentService) {
        self._agent = State(initialValue: agent)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 连接状态横幅
            ConnectionBanner(
                state: agent.connection.state,
                pcName: agent.connection.connectedPC?.name,
                onTap: { showConversations = true }
            )

            // 消息区域
            if agent.messages.isEmpty {
                EmptyHeroView(
                    userName: agent.users.currentLocalUser?.displayName ?? "用户",
                    pcUserName: agent.connection.connectedPC?.currentUser,
                    onQuickMode: { sendMessage("快速模式") },
                    onExpertMode: { sendMessage("专家模式") }
                )
            } else {
                messageList
            }

            // 思考指示器
            if agent.isProcessing && !agent.messages.isEmpty {
                ThinkingIndicator()
                    .padding(.bottom, 4)
            }

            // 输入工具栏
            InputBar(
                text: $messageText,
                isProcessing: agent.isProcessing,
                onSend: { sendMessage(messageText) },
                onStop: { /* 取消请求 */ },
                onVoice: { /* 语音输入 */ }
            )
        }
        .sheet(isPresented: $showConversations) {
            ConversationListView(agent: agent)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(agent.messages) { message in
                        if message.role == .toolCall {
                            ToolCallCard(
                                name: message.toolName ?? "",
                                status: message.toolStatus ?? .inProgress
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        } else {
                            MessageBubble(message: message) {
                                UIPasteboard.general.string = message.text
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: agent.messages.count) { _, _ in
                if let lastId = agent.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        messageText = ""
        Task { @MainActor in
            await agent.sendMessage(text)
        }
    }
}
