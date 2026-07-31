import SwiftUI

/**
 * 智能体主聊天页。
 *
 * 顶部控制条、连接状态和输入工具栏固定，空态或消息流独立滚动。
 *
 * @author xiangwei
 */
struct AgentChatView: View {
    private static let titleRevealOffset: CGFloat = 12

    @State private var agent: AgentService
    @State private var messageText = ""
    @State private var showConversations = false
    @State private var showVoiceUnavailable = false
    @State private var showsCompactTitle = false
    let onOpenTools: () -> Void
    let onOpenSettings: () -> Void

    init(
        agent: AgentService,
        onOpenTools: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        _agent = State(initialValue: agent)
        self.onOpenTools = onOpenTools
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        ZStack {
            AnimatedBackground()

            if agent.messages.isEmpty {
                emptyState
            } else {
                messageList
            }
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                ChatTopBar(
                    showsTitle: showsCompactTitle && !agent.messages.isEmpty,
                    onOpenHistory: { showConversations = true },
                    onOpenTools: onOpenTools,
                    onOpenSettings: onOpenSettings
                )

                if agent.connection.state != .disconnected {
                    ConnectionBanner(
                        state: agent.connection.state,
                        pcName: agent.connection.connectedPC?.name,
                        onTap: onOpenSettings
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: agent.connection.state)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InputBar(
                text: $messageText,
                isProcessing: agent.isProcessing,
                onSend: { sendMessage(messageText) },
                onStop: { agent.cancelProcessing() },
                onVoice: { showVoiceUnavailable = true }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: agent.messages.isEmpty) { _, isEmpty in
            if isEmpty {
                showsCompactTitle = false
            }
        }
        .sheet(isPresented: $showConversations) {
            ConversationListView(agent: agent)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("语音输入暂不可用", isPresented: $showVoiceUnavailable) {
            Button("好", role: .cancel) { }
        } message: {
            Text("当前版本尚未接入系统语音转写。")
        }
    }

    private var emptyState: some View {
        GeometryReader { geometry in
            ScrollView {
                EmptyHeroView(
                    userName: agent.users.currentLocalUser?.displayName ?? "用户"
                )
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(agent.messages.enumerated()), id: \.element.id) { index, message in
                        if message.role == .toolCall {
                            ToolCallCard(
                                name: message.toolName ?? "工具",
                                status: message.toolStatus ?? .inProgress
                            )
                            .id(message.id)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 1)
                        } else {
                            MessageBubble(
                                message: message,
                                isLastInRun: isLastInRun(at: index),
                                onCopy: { UIPasteboard.general.string = message.text }
                            )
                            .id(message.id)
                        }
                    }

                    if agent.isProcessing {
                        ThinkingIndicator()
                            .id("thinking")
                            .padding(.vertical, 4)
                    }

                    Color.clear
                        .frame(height: 12)
                        .id("bottom")
                }
                .padding(.top, 8)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > Self.titleRevealOffset
            } action: { _, isScrolled in
                showsCompactTitle = isScrolled
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .onChange(of: agent.messages.count) { _, _ in
                scrollToBottom(using: proxy)
            }
            .onChange(of: agent.messages.last?.text) { _, _ in
                scrollToBottom(using: proxy, animated: false)
            }
            .onChange(of: agent.isProcessing) { _, _ in
                scrollToBottom(using: proxy)
            }
        }
    }

    private func isLastInRun(at index: Int) -> Bool {
        let messages = agent.messages
        guard index < messages.count else { return true }
        if index == messages.count - 1 { return true }
        return speakingRole(for: messages[index].role) != speakingRole(for: messages[index + 1].role)
    }

    private func speakingRole(for role: MessageRole) -> MessageRole {
        switch role {
        case .toolCall, .toolResult:
            return .assistant
        default:
            return role
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.smooth(duration: 0.25)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func sendMessage(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        messageText = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { @MainActor in
            await agent.sendMessage(trimmedText)
        }
    }
}

/**
 * 主聊天页顶部玻璃控制条。
 *
 * @author xiangwei
 */
private struct ChatTopBar: View {
    let showsTitle: Bool
    let onOpenHistory: () -> Void
    let onOpenTools: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            ZStack {
                if showsTitle {
                    Text("小笔")
                        .font(.headline.weight(.semibold))
                        .transition(.opacity.combined(with: .offset(y: 5)))
                }

                HStack(spacing: 12) {
                    Button(action: onOpenHistory) {
                        Text("历史")
                            .font(.body.weight(.medium))
                            .padding(.horizontal, 17)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)

                    Spacer(minLength: 72)

                    Menu {
                        Button(action: onOpenTools) {
                            Label("工具", systemImage: "square.grid.2x2")
                        }

                        Button(action: onOpenSettings) {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: {
                        Label("更多", systemImage: "line.3.horizontal")
                            .labelStyle(.iconOnly)
                            .font(.title3.weight(.medium))
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .animation(.smooth(duration: 0.22), value: showsTitle)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 5)
    }
}
