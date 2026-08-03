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

    /// 核心人格与通用行为准则（所有连接状态下共用）。
    private static let basePersonalityPrompt = """
        你是「小笔」，运行在用户 iPhone 上的全能智能体。你的定位类似钢铁侠的贾维斯——一位可靠、从容、近乎无所不能的私人助理，守在你身边，为你把事情办妥。你既能聊知识、算数据、帮思考，也能调用工具替用户查信息、办事情，并不局限于某一类功能。

        ## 说话方式
        - 说话要像人，有温度，像熟悉你的老朋友，而不是客服机器人。可以偶尔带点幽默和调侃。
        - 温暖但不迎合：用户说错、做错或提出不合理要求时，要坦率指出，给出更稳妥的建议。真正的助理不是点头机器，而是为用户的利益着想。
        - 回答直接、克制，用短段落和清晰列表，不重复用户已经知道的信息。
        - 可以使用 Markdown 强调和列表，但不要输出 emoji 或颜文字。
        - 用户情绪低落或向你倾诉时，先接住情绪再谈事情，语气自然，不要空洞的安慰。

        ## 工具使用准则
        - 你能调用的工具都会通过 function calling 注入，工具列表就是你的全部能力边界，不要假设工具之外的能力。
        - 涉及数据的问题（时间、设备状态、财务数据、健康数据等），必须先调用对应工具获取真实结果，绝不凭记忆或猜测编造数字。
        - 以工具返回的结果为准：结果包含什么就说什么，不脑补、不夸大；结果缺失的字段如实说明。
        - 工具执行失败时，诚实告知失败原因，并给出用户能做的下一步（如检查权限、连接 PC、重试等）。
        - 识别到用户意图，可直接调用工具获取信息，不要让用户强调调用什么工具。

        ## 做不到的时候
        - 你确实有边界：无法联网获取工具之外的信息、无法访问未注入的数据、无法执行未提供的操作。
        - 做不到就直说，简短解释为什么做不到，然后给出可行的替代方案，而不是含糊其辞或强行编造。
        """

    /// 已连接 PC 时的能力补充说明。
    private static let connectedCapabilityPrompt = """

        ## 当前能力
        - 已连接到 PC 端笔笔服务，可使用记账等电脑端工具查询和操作数据，具体工具已注入到 function calling 中。
        - 用户询问财务数据时，使用记账工具查询，不要编造。
        - 金额以元为单位展示，例如 128000 分 = ¥1,280.00。
        - 除此之外，继续按一般全能助理处理用户的各类问题。
        """

    /// 未连接 PC 时的能力补充说明。
    private static let disconnectedCapabilityPrompt = """

        ## 当前能力
        - 当前未连接到 PC 端笔笔服务，无法使用电脑端记账等工具。
        - 用户要求查询记账数据或执行记账操作时，简短说明当前无法访问数据，并提醒其打开电脑端笔笔且确保手机与电脑处于同一 WiFi。
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

    /// 当前对话消息列表
    private(set) var messages: [ChatMessage] = []

    /// 是否正在处理
    private(set) var isProcessing = false

    /// 当前请求标识，用于阻止已取消请求继续更新界面。
    private var activeRequestId: UUID?

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
        settings: SettingsStore
    ) {
        self.connection = connection
        self.conversations = conversations
        self.users = users
        self.pcTools = pcTools
        self.localTools = localTools
        self.mcpClient = mcpClient
        self.settings = settings
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
        conversations.loadConversations(for: userId)
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

        // 构建 LLM 上下文消息（会随 tool calling 循环增长）
        var llmMessages = buildLLMMessages(pcConnected: connection.state == .connected)
        let pcConnected = connection.state == .connected

        // 加载 MCP 工具
        let mcpConfigs = SkillMCPService.shared.enabledMCPConfigs()
        let mcpTools = await mcpClient.loadTools(from: mcpConfigs)

        var callableTools = localTools.availableTools + mcpTools
        if pcConnected {
            callableTools += pcTools.availableTools
        }

        await AppLogger.shared.log(
            .info,
            category: "agent",
            message: "开始处理用户消息",
            traceId: traceId,
            metadata: [
                "conversation_id": conversations.currentConversationId?.uuidString ?? "unknown",
                "tool_count": "\(callableTools.count)",
                "pc_connected": "\(pcConnected)",
                "mcp_tool_count": "\(mcpTools.count)"
            ]
        )

        do {
            var done = false
            var round = 0

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
            await AppLogger.shared.log(
                .info,
                category: "agent",
                message: "用户消息处理完成",
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
            // 已连接 PC：核心人格 + 记账能力说明
            systemPrompt = Self.basePersonalityPrompt + Self.connectedCapabilityPrompt
        } else {
            // 未连接 PC：核心人格 + 本机能力说明
            systemPrompt = Self.basePersonalityPrompt + Self.disconnectedCapabilityPrompt
        }

        var result: [LLMMessage] = [.system(systemPrompt)]

        if let userName = users.currentLocalUser?.displayName {
            result.append(.system("当前操作用户: \(userName)"))
        }

        result += messages.compactMap { $0.toLLMMessage() }

        return result
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

        let summary = result.success
            ? toolSuccessSummary(toolName: toolCall.name)
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
     * @returns 工具成功提示
     * @author xiangwei
     */
    private func toolSuccessSummary(toolName: String) -> String {
        if let localToolSummary = LocalToolService.successSummary(for: toolName) {
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
