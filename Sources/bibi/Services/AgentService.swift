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

    /// 设置存储
    let settings: SettingsStore

    /// 当前对话消息列表
    private(set) var messages: [ChatMessage] = []

    /// 是否正在处理
    private(set) var isProcessing = false

    /// 当前请求标识，用于阻止已取消请求继续更新界面。
    private var activeRequestId: UUID?

    /// 默认模型名
    private var defaultModel: String {
        settings.get(.llmModel) ?? "deepseek-chat"
    }

    /**
     * 初始化
     */
    init(
        connection: ConnectionManager,
        conversations: ConversationManager,
        users: UserManager,
        pcTools: PcToolService,
        localTools: LocalToolService,
        settings: SettingsStore
    ) {
        self.connection = connection
        self.conversations = conversations
        self.users = users
        self.pcTools = pcTools
        self.localTools = localTools
        self.settings = settings
    }

    /**
     * 初始化智能体。
     *
     * 加载当前用户的历史对话并开始搜索 PC。
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
     * PC 断线时的清理
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
        let callableTools = localTools.availableTools + (pcConnected ? pcTools.availableTools : [])

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
                    traceId: traceId
                )

                var assistantContent = ""
                var toolCallAccumulator = ToolCallAccumulator()
                var finishReason: String?

                for try await event in stream {
                    guard activeRequestId == requestId else { break }

                    switch event {
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

                if finishReason == "tool_calls" {
                    let toolCalls = toolCallAccumulator.buildToolCalls()
                    guard !toolCalls.isEmpty else {
                        throw LLMError.invalidToolCall
                    }

                    llmMessages.append(.assistantToolCalls(
                        content: assistantContent,
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
     */
    func deleteConversation(id: UUID) {
        let isCurrentConversation = conversations.currentConversationId == id
        conversations.deleteConversation(id: id)
        if isCurrentConversation {
            messages = []
        }
    }

    /**
     * 停止当前生成任务。
     *
     * 已取消请求后续到达的流式分片会被忽略。
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
     */
    private func buildLLMMessages(pcConnected: Bool) -> [LLMMessage] {
        let systemPrompt: String

        if pcConnected {
            systemPrompt = """
                你是「小笔」-- 笔笔记账的 AI 助手，运行在 iOS 端。
                当前已连接到 PC 记账服务，你可以查询和操作记账数据。

                当用户询问财务数据时，使用 PC 记账工具查询。
                工具执行结果会返回 JSON 数据，用中文总结给用户。
                金额以元为单位展示，例如 128000 分 = ¥1,280.00。
                不要编造数据，只基于工具返回的结果回答。
                回答要直接、克制，幽默，优先使用短段落和清晰列表，不重复用户已经知道的信息。
                可以使用 Markdown 强调和列表，但不要输出 emoji 或颜文字。
                用户询问当前时间或日期时，必须调用 get_current_time 获取设备系统时间。
                用户询问设备、电池或应用版本时，分别调用 get_device_info、get_battery_status、get_app_info。
                只有用户明确询问当前位置、联系人或日程时，才能调用 get_current_location、search_contacts、
                get_calendar_events。以上工具可能触发 iOS 系统授权，不得为补充无关信息主动调用。

                可用的记账工具已注入到你的 function calling 中。
                """
        } else {
            systemPrompt = """
                你是「小笔」-- 笔笔记账的 AI 助手，运行在 iOS 端。
                当前未连接到 PC 记账服务。

                用户要求查询记账数据或执行记账操作时，简短说明当前无法访问数据，
                并提醒其打开电脑端笔笔且确保手机与电脑处于同一 WiFi。
                用户询问一般性问题时直接回答，不要反复说明连接状态。
                回答要直接、克制，幽默，优先使用短段落和清晰列表，不使用 emoji 或颜文字。
                用户询问当前时间或日期时，仍可调用本机工具 get_current_time 获取准确时间。
                用户询问设备、电池或应用版本时，分别调用 get_device_info、get_battery_status、get_app_info。
                只有用户明确询问当前位置、联系人或日程时，才能调用 get_current_location、search_contacts、
                get_calendar_events。以上工具可能触发 iOS 系统授权，不得为补充无关信息主动调用。
                """
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
     */
    private func updateStreamingAssistant(_ text: String) {
        if messages.last?.role == .assistant {
            messages[messages.count - 1].text += text
        } else {
            messages.append(.assistant(text))
        }
    }

    /**
     * 结束最近一条助手消息的流式状态。
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
     */
    private func performToolCall(
        _ toolCall: ToolCall,
        userId: String,
        traceId: String
    ) async throws -> PcToolResult {
        if localTools.canExecute(toolName: toolCall.name) {
            return try await localTools.execute(toolName: toolCall.name, args: toolCall.arguments)
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
     */
    private func appendSystemMessage(_ text: String) {
        messages.append(.system(text))
    }

    /**
     * 获取工具成功提示。
     *
     * @param toolName 工具名
     * @returns 工具成功提示
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
