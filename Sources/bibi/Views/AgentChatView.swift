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
    private static let voiceCancelThreshold: CGFloat = 80

    @State private var agent: AgentService
    @State private var voice: VoiceInputManager
    @State private var messageText = ""
    @State private var showConversations = false
    @State private var showVoiceError = false
    @State private var showsCompactTitle = false
    @State private var isAppeared = false
    @State private var isVoiceMode = false
    @State private var liveVoiceText = ""
    @State private var voiceTranslation = CGSize.zero
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SettingsStore.self) private var settingsStore
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
        .overlay(alignment: .bottom) {
            if voice.isRecording {
                VoiceRecordingOverlay(
                    text: liveVoiceText,
                    isCancelled: voiceTranslation.height < -Self.voiceCancelThreshold
                )
                .padding(.bottom, 110)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.smooth(duration: 0.2), value: voice.isRecording)
        .safeAreaBar(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                ChatTopBar(
                    showsTitle: showsCompactTitle && !agent.messages.isEmpty,
                    onOpenHistory: { showConversations = true },
                    onNewConversation: { agent.startNewConversation() },
                    onOpenTools: onOpenTools,
                    onOpenSettings: onOpenSettings
                )

                if agent.connection.state != .disconnected {
                    ConnectionBanner(
                        state: agent.connection.state,
                        pcName: agent.connection.connectedPC?.name,
                        discoveredCount: agent.connection.discoveredPCs.count,
                        onTap: onOpenSettings
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: agent.connection.state)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if voice.isCorrecting {
                    voiceStatusBar(text: "正在矫正识别文字…")
                }

                InputBar(
                    text: $messageText,
                    isVoiceMode: $isVoiceMode,
                    isProcessing: agent.isProcessing,
                    isRecording: voice.isRecording,
                    onSend: { sendMessage(messageText) },
                    onStop: { agent.cancelProcessing() },
                    onVoicePressBegan: beginVoiceRecording,
                    onVoiceDragChanged: { voiceTranslation = $0 },
                    onVoicePressEnded: endVoiceRecording
                )
            }
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
        .onChange(of: isVoiceMode) { _, voiceMode in
            // 从语音模式切回文本模式时，若还在录音则停止
            if !voiceMode, voice.isRecording {
                voice.stopRecognition()
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
            .scrollIndicators(.visible)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    scrollToBottom(using: proxy, animated: false)
                }
            }
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
     * 开始按住说话录音。
     *
     * 按下时启动语音识别流，松开后流结束并进入 finalizeVoiceRecording 处理。
     *
     * @author xiangwei
     */
    private func beginVoiceRecording() {
        guard !voice.isRecording else { return }
        liveVoiceText = ""
        voiceTranslation = .zero
        Task { @MainActor in
            do {
                let stream = try await voice.startRecognition()
                var finalText = ""
                for await text in stream {
                    finalText = text
                    liveVoiceText = text
                }
                await finalizeVoiceRecording(finalText)
            } catch {
                showVoiceError = true
            }
        }
    }

    /**
     * 结束按住说话录音。
     *
     * 松开按钮时调用，触发识别任务结束并产生最终结果。
     *
     * @author xiangwei
     */
    private func endVoiceRecording() {
        voice.stopRecognition()
    }

    /**
     * 语音识别结束后处理发送。
     *
     * 若开启自动纠正则先调用 AI 纠正，纠正完成后自动发送；
     * 未开启纠正则直接发送识别原文。
     *
     * @param finalText 识别最终文本
     * @author xiangwei
     */
    private func finalizeVoiceRecording(_ finalText: String) async {
        let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cancelled = voiceTranslation.height < -Self.voiceCancelThreshold
        voiceTranslation = .zero
        liveVoiceText = ""
        guard !trimmed.isEmpty, !cancelled else { return }

        if settingsStore.speechCorrectionEnabled {
            do {
                let corrected = try await voice.correctSpeechText(trimmed)
                let textToSend = corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? trimmed
                    : corrected
                await sendVoiceResult(textToSend)
            } catch {
                await sendVoiceResult(trimmed)
            }
        } else {
            await sendVoiceResult(trimmed)
        }
    }

    /**
     * 发送语音识别的最终结果。
     *
     * @param text 要发送的文本
     * @author xiangwei
     */
    private func sendVoiceResult(_ text: String) async {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        await agent.sendMessage(text)
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
 * 语音录制浮层气泡。
 *
 * 按住说话时显示在输入栏上方，实时展示识别文字；
 * 上滑超过阈值后提示松开取消发送。
 *
 * @author xiangwei
 */
private struct VoiceRecordingOverlay: View {
    let text: String
    let isCancelled: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isCancelled ? "xmark.circle.fill" : "waveform")
                .font(.bibiLargeTitle)
                .foregroundStyle(isCancelled ? .red : .brandGold)

            Text(isCancelled ? "松开取消发送" : (text.isEmpty ? "正在聆听…" : text))
                .font(.bibiBody)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
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
    let onNewConversation: () -> Void
    let onOpenTools: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            ZStack {
                if showsTitle {
                    Text("星枢")
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

                    Button(action: onNewConversation) {
                        Label("新建对话", systemImage: "square.and.pencil")
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
