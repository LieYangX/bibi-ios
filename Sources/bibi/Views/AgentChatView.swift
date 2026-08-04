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
    @State private var voice: VoiceInputManager
    @State private var messageText = ""
    @State private var showConversations = false
    @State private var showVoiceError = false
    @State private var showsCompactTitle = false
    @State private var isAppeared = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ProactiveMessageService.self) private var proactiveService
    let onOpenTools: () -> Void
    let onOpenSettings: () -> Void

    init(
        agent: AgentService,
        voice: VoiceInputManager,
        onOpenTools: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        _agent = State(initialValue: agent)
        _voice = State(initialValue: voice)
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
            VStack(spacing: 8) {
                if voice.isRecording {
                    voiceStatusBar(text: "正在聆听，点击波形按钮结束录音")
                } else if voice.isCorrecting {
                    voiceStatusBar(text: "正在矫正识别文字…")
                }

                InputBar(
                    text: $messageText,
                    isProcessing: agent.isProcessing,
                    isRecording: voice.isRecording,
                    onSend: { sendMessage(messageText) },
                    onStop: { agent.cancelProcessing() },
                    onVoice: toggleVoiceInput
                )
            }
            .animation(.smooth(duration: 0.25), value: voice.isRecording)
            .animation(.smooth(duration: 0.25), value: voice.isCorrecting)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            isAppeared = true
            // 进入聊天窗口：通知主动消息服务，此期间不弹系统通知
            updateChatVisibility()
        }
        .onDisappear {
            // 离开聊天窗口（切到设置页、工具页等）：后续主动消息改为弹系统通知
            isAppeared = false
            updateChatVisibility()
        }
        .onChange(of: scenePhase) { _, _ in
            // app 前后台切换时同步窗口可见状态（根视图不会触发 onAppear/onDisappear）
            updateChatVisibility()
        }
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
        .alert("语音输入不可用", isPresented: $showVoiceError) {
            Button("好", role: .cancel) { }
        } message: {
            Text(voice.lastError ?? "未知错误")
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
            .onChange(of: agent.messages.last?.reasoningContent) { _, _ in
                scrollToBottom(using: proxy, animated: false)
            }
            .onChange(of: agent.isProcessing) { _, _ in
                scrollToBottom(using: proxy)
            }
        }
    }

    /**
     * 根据"聊天页可见 + app 前台"两个条件同步窗口可见状态。
     * @author xiangwei
     */
    private func updateChatVisibility() {
        proactiveService.setChatVisible(isAppeared && scenePhase == .active)
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
        // 发送时停止进行中的录音识别
        voice.stopRecognition()
        messageText = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { @MainActor in
            await agent.sendMessage(trimmedText)
        }
    }

    /**
     * 切换语音输入：录音中则停止，未录音则开始识别。
     *
     * @author xiangwei
     */
    private func toggleVoiceInput() {
        if voice.isRecording {
            voice.stopRecognition()
        } else {
            startVoiceInput()
        }
    }

    /**
     * 启动语音识别，将识别文本实时写入输入框，
     * 识别结束后调用 AI 矫正错字。
     *
     * @author xiangwei
     */
    private func startVoiceInput() {
        Task {
            do {
                let stream = try await voice.startRecognition()
                var finalText = ""
                for await text in stream {
                    finalText = text
                    messageText = text
                }
                if !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await correctVoiceText(finalText)
                }
            } catch {
                showVoiceError = true
            }
        }
    }

    /**
     * 调用 AI 矫正语音识别文本中的错字。
     *
     * 仅在输入框内容仍为原始识别文本时替换，避免覆盖用户的后续编辑。
     *
     * @param original 原始识别文本
     * @author xiangwei
     */
    private func correctVoiceText(_ original: String) async {
        do {
            let corrected = try await voice.correctSpeechText(original)
            if messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                == original.trimmingCharacters(in: .whitespacesAndNewlines) {
                messageText = corrected
            }
        } catch {
            // 矫正失败时保留原始识别文本，不打断用户
        }
    }

    /**
     * 录音或矫正中的状态提示条。
     *
     * @param text 提示文案
     * @author xiangwei
     */
    private func voiceStatusBar(text: String) -> some View {
        Label(text, systemImage: "waveform")
            .font(.bibiCaption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: Capsule())
            .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                        .font(.bibiHeadline)
                        .transition(.opacity.combined(with: .offset(y: 5)))
                }

                HStack(spacing: 12) {
                    Button(action: onOpenHistory) {
                        Label("历史对话", systemImage: "bubble.left.and.bubble.right")
                            .labelStyle(.iconOnly)
                            .font(.bibiBodyMedium)
                            .frame(width: 44, height: 44)
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
                            .font(.bibiBodyMedium)
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .animation(.smooth(duration: 0.25), value: showsTitle)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 5)
    }
}
