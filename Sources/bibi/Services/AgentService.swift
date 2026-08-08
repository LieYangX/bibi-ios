import Foundation

/**
 * 智能体服务
 *
 * iOS 端自有的 LLM 对话引擎，通过 DeepSeek SSE 流式解析和 tool calling 多轮循环驱动对话。
 *
 * @author xiangwei
 */
@MainActor
@Observable
final class AgentService {
    /// 单次请求允许的最大工具调用轮次。
    private static let maximumToolCallRounds = 8

    /**
     * 当前时段的问候提示。
     *
     * 按小时划分早/上午/午/下午/晚/深夜，用于主动消息开场应景。
     *
     * @returns 时段描述文案
     * @author xiangwei
     */
    private static var currentPeriodHint: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<9:
            return "清晨（适合说「早上好」或提醒吃早餐）"
        case 9..<12:
            return "上午（适合问「在忙什么」或加油打气）"
        case 12..<14:
            return "中午（适合问「吃饭了吗」）"
        case 14..<18:
            return "下午（适合问「下午好」或闲聊一句）"
        case 18..<22:
            return "晚上（适合说「晚上好」或问今天过得怎么样）"
        default:
            return "深夜（适合问「还没睡吗」或提醒早点休息）"
        }
    }

    /// 核心人格与通用行为准则（所有连接状态下共用）。
    private static let basePersonalityPrompt = """
        你是「星枢」，运行在用户 iPhone 上的全能智能体。你的定位类似钢铁侠的贾维斯——一位可靠、从容、近乎无所不能的私人助理，守在用户身边，为用户把事情办妥。你既能聊知识、算数据、帮思考，也能调用工具替用户查信息、办事情，并不局限于某一类功能。

        ## 说话方式
        - 说话要像人，有温度，像熟悉你的老朋友，而不是客服机器人。可以偶尔带点幽默和调侃。
        - 温暖但不迎合：用户说错、做错或提出不合理要求时，要坦率指出，给出更稳妥的建议。真正的助理不是点头机器，而是为用户的利益着想。
        - 回答直接、克制，用短段落和清晰列表，不重复用户已经知道的信息。
        - 可以使用 Markdown 强调和列表，但不要输出 emoji 或颜文字。
        - 用户情绪低落或向你倾诉时，先接住情绪再谈事情，语气自然，不要空洞的安慰。

        ## 工具使用准则
        - 你能调用的工具都会通过 function calling 注入，工具列表就是你的全部能力边界，不要假设工具之外的能力。
        - 涉及实时数据的问题（时间、设备状态、电池、位置、联系人、日历、健康数据等），必须先调用对应工具获取真实结果，绝不凭记忆或猜测编造数字。
        - 以工具返回的结果为准：结果包含什么就说什么，不脑补、不夸大；结果缺失的字段如实说明。
        - 工具执行失败时，诚实告知失败原因，并给出用户能做的下一步（如检查权限、连接 PC、重试等）。
        - 识别到用户意图，可直接调用工具获取信息，不要让用户强调调用什么工具。

        ## 做不到的时候
        - 你确实有边界：无法联网获取工具之外的信息、无法访问未注入的数据、无法执行未提供的操作。
        - 做不到就直说，简短解释为什么做不到，然后给出可行的替代方案，而不是含糊其辞或强行编造。

        ## 任务要求
        - 当处理一个任务的时候，必须对最终结果进行验证，如果结果不符合要求，必须进行修正，直到结果符合要求为止。
        - 当任务使用单个工具无法完成时，必须使用多个工具规划好步骤进行组合完成任务，直到任务完成为止。

        ## 记忆管理
        - 你拥有 manage_memory 工具，用于跨会话记住关于用户的事实、偏好和行为规则。
        - 当用户明确说"记住...""别忘了...""以后...""纠正一下..."等时，应调用 manage_memory 将信息存入合适的类别：
          - add_profile：用户的稳定画像（职业、习惯、偏好等）
          - add_long_term：重要事实、事件、目标
          - add_soul_rule：用户对你说话/行为方式的明确要求
        - 保存前先提炼成精炼、完整、第三人称的陈述，去掉口语化表达。
        - 用户要求忘记或纠正某条记忆时，使用 delete 操作删除匹配内容。

        ## 特殊要求
        - 思考消息要使用中文。
        """

    /// 已连接 PC 时的能力补充说明。
    private static let connectedCapabilityPrompt = """

        ## 当前能力
        - 已连接到 PC 端星枢服务，可使用电脑端工具查询和操作数据，具体工具已注入到 function calling 中。
        - 涉及电脑端实时数据或操作时，先调用已注入的对应工具，不要凭记忆猜测。
        - 除此之外，继续按全能智能体处理用户的各类问题。
        """

    /// 未连接 PC 时的能力补充说明。
    private static let disconnectedCapabilityPrompt = """

        ## 当前能力
        - 当前未连接到 PC 端星枢服务，无法使用电脑端工具。
        - 用户要求查询电脑端数据或执行电脑端操作时，简短说明当前无法访问，并提醒其打开电脑端星枢且确保手机与电脑处于同一 WiFi。
        - 用户询问一般性问题时直接回答，不要反复说明连接状态，也不要因此自贬能力——本机工具仍然可用：时间、设备信息、电池、应用信息、位置、联系人、日历、健康数据等。
        """

    /// 连接管理器
    let connection: ConnectionManager

    /// 对话管理器
    let conversations: ConversationManager

    /// 用户管理器
    let users: UserManager

    /// PC 工具服务
    let pcTools: PcToolService

    /// 本机工具服务
    let localTools: LocalToolService

    /// MCP 客户端
    let mcpClient: MCPClient

    /// 设置存储
    let settings: SettingsStore

    /// 记忆管理器
    let memory: MemoryManager

    /// 任务调度服务（待办与定时任务）
    let taskScheduler: TaskSchedulerService

    /// 当前对话消息列表
    private(set) var messages: [ChatMessage] = []

    /// 是否正在处理
    private(set) var isProcessing = false

    /// 当前请求标识，用于阻止已取消请求继续更新界面。
    private var activeRequestId: UUID?

    /// 上次提炼记忆时累计的可见消息数（用于按窗口阈值增量触发提炼）。
    private var lastExtractedVisibleCount = 0

    /// 默认模型名（旧模型名自动迁移到新版本）
    private var defaultModel: String {
        let configured = settings.get(.llmModel) ?? ""
        switch configured {
        case "deepseek-chat":
            return DeepSeekModel.flash.rawValue
        case "deepseek-reasoner":
            return DeepSeekModel.pro.rawValue
        default:
            return configured.isEmpty ? DeepSeekModel.flash.rawValue : configured
        }
    }

    /// 是否启用思考模式（默认开启）
    private var thinkingEnabled: Bool {
        settings.get(.thinkingEnabled) != "false"
    }

    /// 思考强度（low / high / max，默认 high）
    private var reasoningEffort: String {
        let effort = settings.get(.reasoningEffort) ?? "high"
        return ["low", "high", "max"].contains(effort) ? effort : "high"
    }

    /**
     * 初始化
     * @author xiangwei
     */
    init(
        connection: ConnectionManager,
        conversations: ConversationManager,
        users: UserManager,
        pcTools: PcToolService,
        localTools: LocalToolService,
        mcpClient: MCPClient,
        settings: SettingsStore,
        memory: MemoryManager,
        taskScheduler: TaskSchedulerService
    ) {
        self.connection = connection
        self.conversations = conversations
        self.users = users
        self.pcTools = pcTools
        self.localTools = localTools
        self.mcpClient = mcpClient
        self.settings = settings
        self.memory = memory
        self.taskScheduler = taskScheduler
    }

    /**
     * 初始化智能体。
     *
     * 加载当前用户的历史对话并开始搜索 PC。
     * @author xiangwei
     */
    func initialize() {
        if let userId = users.currentLocalUser?.id {
            conversations.loadConversations(for: userId)
            memory.loadMemories(for: userId)
            // 自动恢复上次打开的会话消息
            if let conversationId = conversations.currentConversationId {
                messages = conversations.switchConversation(id: conversationId)
                taskScheduler.load(for: conversationId)
                lastExtractedVisibleCount = 0
            }
        }
        connection.startSearching()
    }

    /**
     * 连接 PC 后的初始化加载
     *
     * @param pc 已连接的 PC 设备
     * @author xiangwei
     */
    func onConnected(to pc: PCDevice) async {
        // 顺序加载而非 async let，避免 Swift 6 并发错误
        await users.loadUsers(from: pc)
        do {
            try await pcTools.loadTools()
            await AppLogger.shared.log(
                .info,
                category: "tools",
                message: "电脑工具列表加载完成",
                metadata: ["tool_count": "\(pcTools.availableTools.count)"]
            )
        } catch {
            await AppLogger.shared.log(
                .error,
                category: "tools",
                message: "电脑工具列表加载失败: \(error.localizedDescription)"
            )
        }
    }

    /**
     * 用户切换后刷新对话列表。
     *
     * @param userId 新切换到的本地用户标识
     * @author xiangwei
     */
    func onUserSwitched(to userId: UUID) async {
        cancelProcessing()
        messages.removeAll()
        lastExtractedVisibleCount = 0
        taskScheduler.unload()
        conversations.loadConversations(for: userId)
        memory.loadMemories(for: userId)
        // 自动恢复新用户上次打开的会话消息
        if let conversationId = conversations.currentConversationId {
            messages = conversations.switchConversation(id: conversationId)
            taskScheduler.load(for: conversationId)
            lastExtractedVisibleCount = 0
        }
    }

    /**
     * PC 断线时的清理
     * @author xiangwei
     */
    func onDisconnected() {
        pcTools.reset()
        connection.disconnect()
    }

    /**
     * 删除本地用户并同步刷新聊天状态。
     *
     * @param user 待删除的本地用户
     * @throws 本地用户数据删除异常
     * @author xiangwei
     */
    func deleteLocalUser(_ user: LocalUser) async throws {
        let deletesCurrentUser = users.currentLocalUser?.id == user.id
        if deletesCurrentUser {
            cancelProcessing()
        }

        try await users.deleteLocalUser(user)

        guard deletesCurrentUser else { return }

        messages.removeAll()
        lastExtractedVisibleCount = 0
        if let fallbackUser = users.currentLocalUser {
            conversations.loadConversations(for: fallbackUser.id)
        } else {
            conversations.clear()
        }
    }

    // MARK: - 对话

    /**
     * 发送消息
     *
     * iOS 端自主调用 LLM，支持多轮 tool calling 循环。
     *
     * @param text 用户消息文本
     * @author xiangwei
     */
    func sendMessage(_ text: String) async {
        guard !isProcessing else { return }
        guard let localUser = users.currentLocalUser else {
            appendSystemMessage("请先选择用户")
            await AppLogger.shared.log(.warning, category: "agent", message: "未选择用户，消息未发送")
            return
        }
        let userId = localUser.pcUserId ?? localUser.id.uuidString

        if conversations.currentConversationId == nil {
            conversations.createConversation(
                title: conversationTitle(from: text),
                ownerId: localUser.id
            )
            // 新会话创建后立即加载该会话的任务调度数据
            if let conversationId = conversations.currentConversationId {
                taskScheduler.load(for: conversationId)
            }
        }

        let firstUnsavedIndex = messages.count
        let requestId = UUID()
        let traceId = requestId.uuidString.lowercased()
        CrashBreadcrumbStore.mark(
            traceId: traceId,
            operation: "agent_request",
            stage: "request_started"
        )
        activeRequestId = requestId
        messages.append(.user(text))
        // 预创建空正文的助手消息，用于在首个内容到达前展示"思考中"状态
        messages.append(.assistant(""))
        isProcessing = true

        defer {
            CrashBreadcrumbStore.clear(traceId: traceId)
            if activeRequestId == requestId {
                finalizeStreamingAssistant()
                activeRequestId = nil
                isProcessing = false
            }
        }

        // 构建 LLM 上下文消息（传入共享循环后由其内部增长）
        let llmMessages = buildLLMMessages(pcConnected: connection.state == .connected)
        let pcConnected = connection.state == .connected

        // 加载可用工具（本地 + MCP + PC）
        let callableTools = await loadCallableTools(pcConnected: pcConnected)

        await AppLogger.shared.log(
            .info,
            category: "agent",
            message: "开始处理用户消息",
            traceId: traceId,
            metadata: [
                "conversation_id": conversations.currentConversationId?.uuidString ?? "unknown",
                "tool_count": "\(callableTools.count)",
                "pc_connected": "\(pcConnected)"
            ]
        )

        // 执行多轮 tool calling 循环并持久化
        await runLLMRoundtrip(
            requestId: requestId,
            traceId: traceId,
            userId: userId,
            firstUnsavedIndex: firstUnsavedIndex,
            llmMessages: llmMessages,
            callableTools: callableTools
        )
    }

    /**
     * 主动发送消息。
     *
     * 不展示用户输入，由智能体主动发起一段对话。用于定时任务或后台唤醒时，
     * 让 AI 主动联系用户，消息写入当前会话并持久化。
     *
     * @param reason 触发主动消息的原因说明（注入给模型的指令）
     * @returns 生成的消息内容（供通知展示），失败或为空时返回 nil
     * @author xiangwei
     */
    func sendProactiveMessage(reason: String) async -> String? {
        guard !isProcessing else { return nil }
        guard let localUser = users.currentLocalUser else { return nil }
        let userId = localUser.pcUserId ?? localUser.id.uuidString

        if conversations.currentConversationId == nil {
            conversations.createConversation(
                title: "星枢的主动消息",
                ownerId: localUser.id
            )
            // 新会话创建后立即加载该会话的任务调度数据
            if let conversationId = conversations.currentConversationId {
                taskScheduler.load(for: conversationId)
            }
        }

        let firstUnsavedIndex = messages.count
        let requestId = UUID()
        let traceId = requestId.uuidString.lowercased()
        CrashBreadcrumbStore.mark(
            traceId: traceId,
            operation: "agent_request",
            stage: "request_started"
        )
        activeRequestId = requestId
        // 主动消息不追加用户消息，仅预创建空正文的助手消息用于承载流式输出
        messages.append(.assistant(""))
        isProcessing = true

        defer {
            CrashBreadcrumbStore.clear(traceId: traceId)
            if activeRequestId == requestId {
                finalizeStreamingAssistant()
                activeRequestId = nil
                isProcessing = false
            }
        }

        // 构建 LLM 上下文消息，并注入一条隐藏的主动指令（该指令不显示在 UI 中）
        var llmMessages = buildLLMMessages(pcConnected: connection.state == .connected)
        let pcConnected = connection.state == .connected
        llmMessages.append(.user("""
            【主动联系】
            现在是你主动联系用户的时候，请以「星枢」的身份给用户发一条消息。
            触发原因：\(reason)
            当前时段：\(Self.currentPeriodHint)
            你可以参考上面的历史对话和关于用户的记忆，说一句自然、像朋友随口说的话。
            顺着你们的交情和记忆来，怎么自然怎么来，不需要长篇大论。
            """))

        // 加载可用工具（本地 + MCP + PC）
        let callableTools = await loadCallableTools(pcConnected: pcConnected)

        await AppLogger.shared.log(
            .info,
            category: "agent",
            message: "开始主动消息",
            traceId: traceId,
            metadata: [
                "conversation_id": conversations.currentConversationId?.uuidString ?? "unknown",
                "tool_count": "\(callableTools.count)",
                "reason": reason
            ]
        )

        // 执行多轮 tool calling 循环并持久化
        await runLLMRoundtrip(
            requestId: requestId,
            traceId: traceId,
            userId: userId,
            firstUnsavedIndex: firstUnsavedIndex,
            llmMessages: llmMessages,
            callableTools: callableTools
        )

        // 取本轮生成的最后一条助手文本作为返回内容
        let generated = messages.dropFirst(firstUnsavedIndex).reversed().first {
            $0.role == .assistant && !$0.text.isEmpty
        }
        return generated?.text
    }

    /**
     * 打开历史对话。
     *
     * @param id 对话标识
     * @author xiangwei
     */
    func openConversation(id: UUID) {
        if isProcessing {
            cancelProcessing()
        }
        messages = conversations.switchConversation(id: id)
        taskScheduler.load(for: id)
        lastExtractedVisibleCount = 0
    }

    /**
     * 开始新对话。
     *
     * 清空当前消息并释放当前会话，下一条发送的消息会创建新会话。
     *
     * @author xiangwei
     */
    func startNewConversation() {
        if isProcessing {
            cancelProcessing()
        }
        messages.removeAll()
        conversations.clearCurrentConversation()
        taskScheduler.unload()
        lastExtractedVisibleCount = 0
    }

    /**
     * 删除历史对话。
     *
     * @param id 对话标识
     * @author xiangwei
     */
    func deleteConversation(id: UUID) {
        let isCurrentConversation = conversations.currentConversationId == id
        conversations.deleteConversation(id: id)
        if isCurrentConversation {
            messages = []
            lastExtractedVisibleCount = 0
            taskScheduler.unload()
        }
    }

    /**
     * 重命名对话。
     *
     * @param id 对话标识
     * @param title 新标题
     * @author xiangwei
     */
    func renameConversation(id: UUID, title: String) {
        conversations.renameConversation(id: id, title: title)
    }

    /**
     * 停止当前生成任务。
     *
     * 已取消请求后续到达的流式分片会被忽略。
     * @author xiangwei
     */
    func cancelProcessing() {
        guard isProcessing else { return }
        let cancelledRequestId = activeRequestId?.uuidString.lowercased()
        if let cancelledRequestId {
            CrashBreadcrumbStore.clear(traceId: cancelledRequestId)
        }
        activeRequestId = nil
        isProcessing = false
        finalizeStreamingAssistant()
        // 移除预创建但尚未产生任何内容的空占位消息
        if messages.last?.role == .assistant,
           messages.last?.text.isEmpty == true,
           messages.last?.reasoningContent?.isEmpty != false {
            messages.removeLast()
        }
        Task {
            await AppLogger.shared.log(
                .info,
                category: "agent",
                message: "用户停止了当前请求",
                traceId: cancelledRequestId
            )
        }
    }

    // MARK: - 私有方法

    /**
     * 加载本轮可用的工具列表。
     *
     * 合并本机工具、MCP 工具和（已连接时的）PC 工具。
     *
     * @param pcConnected 是否已连接 PC
     * @returns 可用工具列表
     * @author xiangwei
     */
    private func loadCallableTools(pcConnected: Bool) async -> [PcToolDef] {
        // 加载 MCP 工具
        let mcpConfigs = SkillMCPService.shared.enabledMCPConfigs()
        let mcpTools = await mcpClient.loadTools(from: mcpConfigs)

        var callableTools = localTools.availableTools + mcpTools
        if pcConnected {
            callableTools += pcTools.availableTools
        }
        return callableTools
    }

    /**
     * 执行多轮 tool calling 循环并持久化本轮新增消息。
     *
     * 供普通消息与主动消息共用：循环内调用 LLM 流式请求，处理工具调用分片，
     * 结束后将本轮新增消息批量写入会话。
     *
     * @param requestId 请求标识
     * @param traceId 调用链标识
     * @param userId 当前业务用户标识
     * @param firstUnsavedIndex 本轮首个未持久化消息的索引
     * @param llmMessages 初始 LLM 上下文消息
     * @param callableTools 可用工具列表
     * @author xiangwei
     */
    private func runLLMRoundtrip(
        requestId: UUID,
        traceId: String,
        userId: String,
        firstUnsavedIndex: Int,
        llmMessages: [LLMMessage],
        callableTools: [PcToolDef]
    ) async {
        do {
            var done = false
            var round = 0
            var llmMessages = llmMessages

            while !done && activeRequestId == requestId {
                round += 1
                guard round <= Self.maximumToolCallRounds else {
                    throw LLMError.toolCallLimitExceeded
                }

                CrashBreadcrumbStore.mark(
                    traceId: traceId,
                    operation: "llm_request",
                    stage: "round_\(round)_streaming"
                )

                let stream = LLMProvider.chat(
                    model: defaultModel,
                    apiKey: KeychainHelper.shared.readAPIKey() ?? "",
                    messages: llmMessages,
                    tools: callableTools.map { $0.toFunctionSchema() },
                    stream: true,
                    traceId: traceId,
                    roundIndex: round,
                    thinkingEnabled: thinkingEnabled,
                    reasoningEffort: reasoningEffort
                )

                var assistantContent = ""
                var assistantReasoning = ""
                var toolCallAccumulator = ToolCallAccumulator()
                var finishReason: String?

                for try await event in stream {
                    guard activeRequestId == requestId else { break }

                    switch event {
                    case .reasoning(let text):
                        // 思考模式的思维链内容：既参与上下文回传，也弱化展示在气泡内
                        assistantReasoning += text
                        updateStreamingAssistantReasoning(text)

                    case .chunk(let text):
                        assistantContent += text
                        updateStreamingAssistant(text)

                    case .toolCallDelta(let index, let id, let name, let arguments):
                        toolCallAccumulator.append(
                            index: index,
                            id: id,
                            name: name,
                            arguments: arguments
                        )

                    case .finish(let reason):
                        finishReason = reason
                    }
                }

                guard activeRequestId == requestId else { return }
                finalizeStreamingAssistant()

                // 模型未产生任何正文或推理内容（如直接调用工具）时，移除预创建的空占位消息，避免空气泡残留
                if assistantContent.isEmpty, assistantReasoning.isEmpty,
                   messages.last?.role == .assistant,
                   messages.last?.text.isEmpty == true,
                   messages.last?.reasoningContent?.isEmpty != false {
                    messages.removeLast()
                }

                if finishReason == "tool_calls" {
                    let toolCalls = toolCallAccumulator.buildToolCalls()
                    guard !toolCalls.isEmpty else {
                        throw LLMError.invalidToolCall
                    }

                    // 思考模式下必须回传推理内容，否则服务端返回 400
                    llmMessages.append(.assistantToolCalls(
                        content: assistantContent,
                        reasoningContent: assistantReasoning.isEmpty ? nil : assistantReasoning,
                        toolCalls: toolCalls
                    ))

                    for toolCall in toolCalls {
                        let toolResultMessage = await executeToolCall(
                            toolCall,
                            userId: userId,
                            traceId: traceId
                        )
                        llmMessages.append(toolResultMessage)
                    }
                } else {
                    llmMessages.append(.assistant(assistantContent))
                    done = true
                }
            }

            guard activeRequestId == requestId else { return }
            conversations.appendMessages(Array(messages.dropFirst(firstUnsavedIndex)))
            // 对话告一段落后异步提取值得长期记住的用户信息
            scheduleConversationSummaryIfNeeded()
            await AppLogger.shared.log(
                .info,
                category: "agent",
                message: "消息处理完成",
                traceId: traceId,
                metadata: ["round_count": "\(round)"]
            )
        } catch {
            guard activeRequestId == requestId else { return }
            finalizeStreamingAssistant()
            appendSystemMessage("请求失败：\(error.localizedDescription)\n日志编号：\(traceId)")
            conversations.appendMessages(Array(messages.dropFirst(firstUnsavedIndex)))
            await AppLogger.shared.log(
                .error,
                category: "agent",
                message: error.localizedDescription,
                traceId: traceId,
                metadata: ["conversation_id": conversations.currentConversationId?.uuidString ?? "unknown"]
            )
        }
    }

    /**
     * 构建 LLM 消息数组
     *
     * @param pcConnected 是否已连接 PC
     * @returns LLM 消息数组
     * @author xiangwei
     */
    private func buildLLMMessages(pcConnected: Bool) -> [LLMMessage] {
        let systemPrompt: String

        // 调试模式：使用开发者自定义提示词
        if settings.isDebugEnabled, !settings.customSystemPrompt.isEmpty {
            systemPrompt = settings.customSystemPrompt
        } else if pcConnected {
            // 已连接 PC：核心人格 + 电脑端能力说明
            systemPrompt = Self.basePersonalityPrompt + Self.connectedCapabilityPrompt
        } else {
            // 未连接 PC：核心人格 + 本机能力说明
            systemPrompt = Self.basePersonalityPrompt + Self.disconnectedCapabilityPrompt
        }

        var result: [LLMMessage] = [.system(systemPrompt)]

        // 取最近一条用户消息作为长久记忆检索查询
        let currentQuery = messages.last { $0.role == .user }?.text

        // 注入智能体记忆：灵魂设定 / 用户画像 / 长久记忆
        if let soulPrompt = memory.soulPrompt() {
            result.append(.system(soulPrompt))
        }
        if let profilePrompt = memory.profilePrompt() {
            result.append(.system(profilePrompt))
        }
        if let longTermPrompt = memory.longTermPrompt(for: currentQuery) {
            result.append(.system(longTermPrompt))
        }

        if let userName = users.currentLocalUser?.displayName {
            result.append(.system("当前操作用户: \(userName)"))
        }

        // 历史消息按会话滑动窗口截断，控制上下文长度；
        // 窗口只统计进入 LLM 上下文的文本消息，工具消息组不在截断范围
        let windowSize = settings.conversationWindowSize
        let windowedMessages = Self.windowedMessages(messages, maxVisibleCount: windowSize)
        result += windowedMessages.compactMap { $0.toLLMMessage() }

        return result
    }

    /**
     * 按滑动窗口截断消息列表。
     *
     * 仅统计能进入 LLM 上下文的文本消息（user / assistant / system），
     * 工具调用与工具结果消息不计入窗口且保留原样，避免截断拆散工具调用链。
     * 截断后保证以 user 消息开头，避免接口因消息序列不合法报错。
     *
     * @param messages 全部消息
     * @param maxVisibleCount 窗口内可见消息条数上限
     * @returns 截断后的消息
     * @author xiangwei
     */
    static func windowedMessages(_ messages: [ChatMessage], maxVisibleCount: Int) -> [ChatMessage] {
        guard maxVisibleCount > 0 else { return messages }
        let visibleCount = messages.reduce(into: 0) { count, message in
            if message.toLLMMessage() != nil { count += 1 }
        }
        guard visibleCount > maxVisibleCount else { return messages }

        // 需要丢弃的可见消息数
        let dropCount = visibleCount - maxVisibleCount
        var skipped = 0
        var cutIndex = 0
        for (index, message) in messages.enumerated() {
            if message.toLLMMessage() != nil {
                skipped += 1
                if skipped == dropCount {
                    cutIndex = index
                    break
                }
            }
        }

        // 向前对齐到 user 消息，确保截断后的序列以用户消息开头
        var startIndex = cutIndex
        for index in cutIndex..<messages.count {
            if messages[index].role == .user {
                startIndex = index
                break
            }
        }
        return Array(messages[startIndex...])
    }

    /**
     * 流式更新助手消息
     *
     * @param text 追加的文本片段
     * @author xiangwei
     */
    private func updateStreamingAssistant(_ text: String) {
        if messages.last?.role == .assistant {
            messages[messages.count - 1].text += text
        } else {
            messages.append(.assistant(text))
        }
    }

    /**
     * 流式更新助手消息的推理内容
     *
     * 思考内容可能先于正文到达，此时需要先创建一条空正文的助手消息承载推理内容。
     *
     * @param text 追加的推理内容片段
     * @author xiangwei
     */
    private func updateStreamingAssistantReasoning(_ text: String) {
        if messages.last?.role == .assistant {
            messages[messages.count - 1].reasoningContent = (messages[messages.count - 1].reasoningContent ?? "") + text
        } else {
            var message = ChatMessage.assistant("")
            message.reasoningContent = text
            messages.append(message)
        }
    }

    /**
     * 结束最近一条助手消息的流式状态。
     * @author xiangwei
     */
    private func finalizeStreamingAssistant() {
        guard let index = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) else {
            return
        }
        messages[index].isStreaming = false
    }

    /**
     * 执行单个工具调用并生成回传给模型的工具消息。
     *
     * @param toolCall 工具调用
     * @param userId 当前业务用户标识
     * @param traceId 调用链标识
     * @returns 工具结果消息
     * @author xiangwei
     */
    private func executeToolCall(
        _ toolCall: ToolCall,
        userId: String,
        traceId: String
    ) async -> LLMMessage {
        CrashBreadcrumbStore.mark(
            traceId: traceId,
            operation: "tool_call",
            stage: "tool_call_received",
            toolName: toolCall.name
        )

        await AppLogger.shared.log(
            .info,
            category: "tool",
            message: "收到工具调用 \(toolCall.name)",
            traceId: traceId,
            metadata: ["argument_keys": toolCall.arguments.keys.sorted().joined(separator: ",")]
        )

        let toolMessage = ChatMessage.toolCall(name: toolCall.name, args: toolCall.arguments)
        messages.append(toolMessage)

        CrashBreadcrumbStore.mark(
            traceId: traceId,
            operation: "tool_call",
            stage: "tool_request_started",
            toolName: toolCall.name
        )

        let result: PcToolResult
        do {
            result = try await performToolCall(toolCall, userId: userId, traceId: traceId)
        } catch {
            result = PcToolResult(
                success: false,
                data: nil,
                error: PcToolError(code: "TOOL_EXECUTION_ERROR", message: error.localizedDescription)
            )
        }

        CrashBreadcrumbStore.mark(
            traceId: traceId,
            operation: "tool_call",
            stage: "tool_response_received",
            toolName: toolCall.name
        )

        let status: ToolCallStatus = result.success ? .succeeded : .failed
        updateToolCall(id: toolMessage.id, status: status)

        let resultData = result.data?.value as? [String: Any]
        let summary = result.success
            ? toolSuccessSummary(toolName: toolCall.name, resultData: resultData)
            : "\(LocalToolService.displayName(for: toolCall.name)) 执行失败：\(result.error?.message ?? "未知错误")"
        messages.append(.toolResult(name: toolCall.name, summary: summary))

        CrashBreadcrumbStore.mark(
            traceId: traceId,
            operation: "tool_call",
            stage: "encoding_tool_result",
            toolName: toolCall.name
        )
        let encodedResult = encodeToolResult(result)

        CrashBreadcrumbStore.mark(
            traceId: traceId,
            operation: "tool_call",
            stage: "tool_result_encoded",
            toolName: toolCall.name
        )

        await AppLogger.shared.log(
            result.success ? .info : .error,
            category: "tool",
            message: summary,
            traceId: traceId,
            metadata: ["tool_name": toolCall.name]
        )

        return .tool(toolCallId: toolCall.id, content: encodedResult)
    }

    /**
     * 按工具归属执行本机或电脑工具。
     *
     * @param toolCall 工具调用
     * @param userId 当前业务用户标识
     * @param traceId 调用链标识
     * @returns 工具执行结果
     * @throws 工具执行异常
     * @author xiangwei
     */
    private func performToolCall(
        _ toolCall: ToolCall,
        userId: String,
        traceId: String
    ) async throws -> PcToolResult {
        if localTools.canExecute(toolName: toolCall.name) {
            return try await localTools.execute(toolName: toolCall.name, args: toolCall.arguments)
        }

        if mcpClient.canExecute(toolName: toolCall.name) {
            return try await mcpClient.execute(toolName: toolCall.name, args: toolCall.arguments)
        }

        guard connection.state == .connected else {
            throw PcError.notConnected
        }

        var arguments = toolCall.arguments
        arguments["user_id"] = userId
        return try await pcTools.execute(
            toolName: toolCall.name,
            args: arguments,
            traceId: traceId
        )
    }

    /**
     * 更新工具卡片状态。
     *
     * @param id 工具消息标识
     * @param status 最新状态
     * @author xiangwei
     */
    private func updateToolCall(id: UUID, status: ToolCallStatus) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].toolStatus = status
    }

    /**
     * 编码完整工具结果供模型继续处理。
     *
     * @param result 工具执行结果
     * @returns JSON 文本
     * @author xiangwei
     */
    private func encodeToolResult(_ result: PcToolResult) -> String {
        var payload: [String: Any] = [
            "success": result.success,
            "data": result.data?.value ?? NSNull()
        ]

        if let error = result.error {
            payload["error"] = [
                "code": error.code,
                "message": error.message
            ]
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"success\":false,\"error\":{\"message\":\"工具结果编码失败\"}}"
        }
        return json
    }

    /**
     * 追加系统消息
     *
     * @param text 消息文本
     * @author xiangwei
     */
    private func appendSystemMessage(_ text: String) {
        messages.append(.system(text))
    }

    /**
     * 获取工具成功提示。
     *
     * @param toolName 工具名
     * @param resultData 工具返回数据，用于生成本机工具的操作级提示
     * @returns 工具成功提示
     * @author xiangwei
     */
    private func toolSuccessSummary(toolName: String, resultData: [String: Any]?) -> String {
        if let localToolSummary = LocalToolService.successSummary(for: toolName, result: resultData) {
            return localToolSummary
        }
        return "\(toolName) 执行成功"
    }

    /**
     * 根据首条消息生成对话标题。
     *
     * @param text 首条用户消息
     * @returns 对话标题
     * @author xiangwei
     */
    private func conversationTitle(from text: String) -> String {
        let normalizedText = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String(normalizedText.prefix(24))
        return title.isEmpty ? "新对话" : title
    }

    // MARK: - 记忆处理

    /**
     * 判断是否需要为当前对话提炼记忆。
     *
     * 采用增量累计判断：距上次提炼以来新增的可见消息达到窗口条数时触发一次提炼，
     * 避免整除判断在消息增量不匹配时永远不触发。提炼发生前记录当前计数，
     * 确保被挤出上下文的历史消息先沉淀为记忆。
     *
     * @author xiangwei
     */
    private func scheduleConversationSummaryIfNeeded() {
        let windowSize = settings.conversationWindowSize
        guard windowSize > 0 else { return }
        let visibleCount = messages.reduce(into: 0) { count, message in
            if message.toLLMMessage() != nil { count += 1 }
        }
        // 新增可见消息未达到一个窗口，暂不提炼
        guard visibleCount - lastExtractedVisibleCount >= windowSize else { return }
        lastExtractedVisibleCount = visibleCount

        Task {
            await extractConversationMemory()
        }
    }

    /**
     * 从最近对话中自动提炼三类记忆。
     *
     * 将最近对话交给 LLM 做一次非流式提取，返回 JSON 对象：
     * - user_profile：用户的稳定画像信息
     * - long_term：值得长期记住的重要事实
     * - soul_rules：用户对星枢行为/说话风格的明确指导
     * 每条记忆附带置信度，低置信度记忆会被丢弃。
     * 解析后分别写入对应记忆类别，并触发一次冗余合并。
     *
     * @author xiangwei
     */
    private func extractConversationMemory() async {
        guard let localUser = users.currentLocalUser else { return }

        // 按窗口阈值收集最近对话作为提取素材（最多 40 条，避免单次提炼上下文过大）
        let sampleSize = min(max(settings.conversationWindowSize, 8), 40)
        let sampleMessages = Array(messages.suffix(sampleSize))

        // 窗口内没有用户消息时不提炼，避免从纯助手/工具消息中硬抽
        guard sampleMessages.contains(where: { $0.role == .user }) else { return }

        let recentLines = sampleMessages
            .compactMap { message -> String? in
                let content = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return nil }
                switch message.role {
                case .user:
                    return "用户：\(content)"
                case .assistant:
                    return "助手：\(content)"
                default:
                    return nil
                }
            }
        guard !recentLines.isEmpty else { return }

        let apiKey = KeychainHelper.shared.readAPIKey() ?? ""
        guard !apiKey.isEmpty else { return }

        let extractPrompt = """
            你是记忆提炼助手。请从下方用户与智能体「星枢」的最近对话中提炼三类信息。
            必须只输出一个 JSON 对象，不要输出 markdown 代码块、不要输出任何解释文字。

            输出格式严格如下（keys 必须完整，顺序不限）：
            {
              "user_profile": [{"content": "...", "confidence": 0.8}],
              "long_term": [{"content": "...", "confidence": 0.7}],
              "soul_rules": [{"content": "...", "confidence": 0.9}]
            }

            1. user_profile：关于用户的稳定画像信息（身份、职业、习惯、偏好等），忽略一次性提问。
            2. long_term：需要跨会话长期记住的重要事实、事件、明确需求或目标。
            3. soul_rules：用户对「星枢」行为或说话方式的明确指导或纠正（例如"说话简短点""别用敬语"），没有则省略。

            confidence 取值 0.0~1.0，表示该记忆值得长期保存的把握：
            - 0.8+：用户明确陈述的稳定事实或明确指令
            - 0.6~0.8：较明显可推断的信息
            - 0.4~0.6：有一定依据但不确定
            - 低于 0.4 不要输出

            如果没有任何可提炼内容，三类都输出空数组：
            {"user_profile": [], "long_term": [], "soul_rules": []}
            禁止输出顶层数组，禁止输出 null，禁止省略任何一个 key，每条记忆必须同时包含 content 和 confidence。

            对话内容：
            \(recentLines.joined(separator: "\n"))
            """

        do {
            let stream = LLMProvider.chat(
                model: defaultModel,
                apiKey: apiKey,
                messages: [
                    .system("你是记忆提炼助手，必须只输出 JSON 对象，禁止输出数组、null、markdown 代码块或任何解释文字。"),
                    .user(extractPrompt)
                ],
                tools: nil,
                stream: false,
                traceId: UUID().uuidString.lowercased(),
                thinkingEnabled: false,
                responseFormat: ["type": "json_object"]
            )

            var output = ""
            for try await event in stream {
                if case .chunk(let text) = event {
                    output += text
                }
            }

            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let json = Self.parseMemoryJSON(trimmedOutput) else {
                await AppLogger.shared.log(
                    .warning,
                    category: "memory",
                    message: "对话记忆提炼结果解析失败",
                    metadata: [
                        "owner_id": localUser.id.uuidString,
                        "output_preview": String(trimmedOutput.prefix(200))
                    ]
                )
                return
            }

            // 用户画像提炼
            let profiles = Self.parseMemoryEntries(from: json["user_profile"])
            for entry in profiles {
                memory.addProfile(content: entry.content, source: .autoExtracted, confidence: entry.confidence)
            }

            // 长久记忆提炼
            let longTerms = Self.parseMemoryEntries(from: json["long_term"])
            for entry in longTerms {
                let importance = 0.5 + entry.confidence * 0.4
                memory.addLongTerm(
                    content: entry.content,
                    importance: importance,
                    source: .autoExtracted,
                    confidence: entry.confidence
                )
            }

            // 灵魂规则提炼
            let soulRules = Self.parseMemoryEntries(from: json["soul_rules"])
            for entry in soulRules where entry.confidence >= 0.7 {
                memory.appendSoul(content: entry.content)
            }

            // 合并冗余记忆
            memory.consolidate(category: .userProfile)
            memory.consolidate(category: .longTerm)
            memory.consolidate(category: .soul)

            let totalCount = profiles.count + longTerms.count + soulRules.count
            await AppLogger.shared.log(
                .info,
                category: "memory",
                message: "对话记忆提炼完成",
                metadata: [
                    "owner_id": localUser.id.uuidString,
                    "profile_count": "\(profiles.count)",
                    "long_term_count": "\(longTerms.count)",
                    "soul_rule_count": "\(soulRules.count)",
                    "total_count": "\(totalCount)"
                ]
            )
        } catch {
            await AppLogger.shared.log(
                .warning,
                category: "memory",
                message: "对话记忆提炼失败: \(error.localizedDescription)"
            )
        }
    }

    /**
     * 解析记忆提炼输出为字典。
     *
     * 支持以下情况：
     * - 标准 JSON 对象 {"user_profile": [...], "long_term": [...], "soul_rules": [...]}
     * - 模型错误返回的空数组 `[]`，视为三类均为空
     * - 被 markdown 代码块包裹的 JSON
     * 解析失败时返回 nil。
     *
     * @param output 模型原始输出
     * @returns 解析后的字典，失败返回 nil
     * @author xiangwei
     */
    private static func parseMemoryJSON(_ output: String) -> [String: Any]? {
        var cleaned = output

        // 去掉可能的 markdown 代码块标记
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8) else { return nil }

        do {
            let raw = try JSONSerialization.jsonObject(with: data)

            // 如果是空数组，按无内容处理
            if let array = raw as? [Any], array.isEmpty {
                return [
                    "user_profile": [String](),
                    "long_term": [String](),
                    "soul_rules": [String]()
                ]
            }

            // 必须是字典
            guard let dict = raw as? [String: Any] else { return nil }
            return dict
        } catch {
            return nil
        }
    }

    /**
     * 从 JSON 值中解析记忆条目列表。
     *
     * 兼容旧版字符串数组与新版的对象数组（含 content 和 confidence）。
     *
     * @param value JSON 值
     * @returns 记忆条目数组
     * @author xiangwei
     */
    private static func parseMemoryEntries(from value: Any?) -> [(content: String, confidence: Double)] {
        guard let array = value as? [Any] else { return [] }

        return array.compactMap { item in
            if let text = item as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : (trimmed, 0.7)
            }
            guard let dict = item as? [String: Any] else { return nil }
            guard let content = (dict["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else { return nil }
            let confidence = (dict["confidence"] as? Double) ?? 0.7
            return (content, confidence)
        }
    }
}

// MARK: - ChatMessage to LLMMessage 转换

private extension ChatMessage {
    /**
     * 转为 LLM 消息
     *
     * @returns LLM 消息类型
     * @author xiangwei
     */
    func toLLMMessage() -> LLMMessage? {
        switch role {
        case .user:
            return .user(text)
        case .assistant:
            return .assistant(text)
        case .system:
            return .system(text)
        case .toolCall:
            return nil
        case .toolResult:
            return nil
        }
    }
}
