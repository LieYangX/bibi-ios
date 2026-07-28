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
    /// 连接管理器
    let connection: ConnectionManager

    /// 对话管理器
    let conversations: ConversationManager

    /// 用户管理器
    let users: UserManager

    /// PC 工具服务
    let pcTools: PcToolService

    /// 设置存储
    let settings: SettingsStore

    /// 当前对话消息列表
    private(set) var messages: [ChatMessage] = []

    /// 是否正在处理
    private(set) var isProcessing = false

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
        settings: SettingsStore
    ) {
        self.connection = connection
        self.conversations = conversations
        self.users = users
        self.pcTools = pcTools
        self.settings = settings
    }

    /**
     * 初始化智能体（开始搜索 PC）
     */
    func initialize() {
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
        try? await pcTools.loadTools()
    }

    /**
     * PC 断线时的清理
     */
    func onDisconnected() {
        pcTools.reset()
        connection.disconnect()
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
        guard let userId = users.currentLocalUser?.pcUserId ?? users.currentLocalUser?.id.uuidString else {
            appendSystemMessage("请先选择用户")
            return
        }

        messages.append(.user(text))
        isProcessing = true

        // 构建 LLM 上下文消息（会随 tool calling 循环增长）
        var llmMessages = buildLLMMessages(pcConnected: connection.state == .connected)
        let pcConnected = connection.state == .connected
        let toolsAvailable = pcConnected && !pcTools.availableTools.isEmpty

        do {
            // 多轮对话循环
            var done = false

            while !done {
                let stream = LLMProvider.chat(
                    model: defaultModel,
                    apiKey: KeychainHelper.shared.readAPIKey() ?? "",
                    messages: llmMessages,
                    tools: toolsAvailable ? pcTools.availableTools.map { $0.toFunctionSchema() } : nil,
                    stream: true
                )

                var assistantContent = ""
                var toolCallAccumulator = ToolCallAccumulator()
                var finishReason: String?

                for try await event in stream {
                    switch event {
                    case .chunk(let text):
                        assistantContent += text
                        updateStreamingAssistant(text)

                    case .toolCallDelta(let index, let name, let arguments):
                        toolCallAccumulator.append(index: index, name: name, arguments: arguments)

                    case .finish(let reason):
                        finishReason = reason
                    }
                }

                // 将 assistant 消息加入 LLM 上下文
                llmMessages.append(.assistant(assistantContent))

                if finishReason == "tool_calls" {
                    // 处理 tool calls
                    let toolCalls = toolCallAccumulator.buildToolCalls()

                    // 将 tool_calls 加入 LLM 上下文
                    llmMessages.append(.assistantToolCalls(
                        content: assistantContent,
                        toolCalls: toolCalls
                    ))

                    for toolCall in toolCalls {
                        // UI 显示工具卡片
                        let toolCallMsg = ChatMessage.toolCall(
                            name: toolCall.name,
                            args: toolCall.arguments
                        )
                        messages.append(toolCallMsg)

                        // 再次确认连接状态
                        guard connection.state == .connected else {
                            let failMsg = ChatMessage.toolResult(
                                name: toolCall.name,
                                summary: "PC 已断开连接，无法执行工具"
                            )
                            messages.append(failMsg)
                            llmMessages.append(.tool(
                                toolCallId: toolCall.id,
                                content: "{\"error\": \"PC disconnected\"}"
                            ))
                            continue
                        }

                        // 执行 PC 工具
                        var args = toolCall.arguments
                        args["user_id"] = userId

                        let result = try await pcTools.execute(
                            toolName: toolCall.name,
                            args: args
                        )

                        let summary = result.success
                            ? "\(toolCall.name) 执行成功"
                            : "\(toolCall.name) 执行失败: \(result.error?.message ?? "")"

                        let resultMsg = ChatMessage.toolResult(name: toolCall.name, summary: summary)
                        messages.append(resultMsg)

                        // 工具结果加入 LLM 上下文
                        let resultJSON = String(
                            data: try JSONSerialization.data(
                                withJSONObject: result.data?.value ?? [:]
                            ),
                            encoding: .utf8
                        ) ?? "{}"
                        llmMessages.append(.tool(toolCallId: toolCall.id, content: resultJSON))
                    }
                    // 继续循环 -> 下一轮 LLM 请求
                } else {
                    // finish_reason == "stop" -> 对话完成
                    done = true
                }
            }

            isProcessing = false

            // 持久化消息
            conversations.saveMessages(messages, for: users.currentLocalUser?.id)

        } catch {
            appendSystemMessage(error.localizedDescription)
            isProcessing = false
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

                可用的记账工具已注入到你的 function calling 中。
                """
        } else {
            systemPrompt = """
                你是「小笔」-- 笔笔记账的 AI 助手，运行在 iOS 端。
                当前未连接到 PC 记账服务。

                用户如果想查询记账数据或执行记账操作，请告知用户：
                「PC 记账服务未连接。请确保电脑端笔笔已打开，且与手机在同一 WiFi 下。」

                你可以回答一般性问题，但无法访问任何记账数据。
                """
        }

        var result: [LLMMessage] = [.system(systemPrompt)]

        if let userName = users.currentLocalUser?.displayName {
            result.append(.system("当前操作用户: \(userName)"))
        }

        result += messages.map { $0.toLLMMessage() }

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
     * 追加系统消息
     *
     * @param text 消息文本
     */
    private func appendSystemMessage(_ text: String) {
        messages.append(.system(text))
    }
}

// MARK: - ChatMessage to LLMMessage 转换

private extension ChatMessage {
    /**
     * 转为 LLM 消息
     *
     * @returns LLM 消息类型
     */
    func toLLMMessage() -> LLMMessage {
        switch role {
        case .user:
            return .user(text)
        case .assistant:
            return .assistant(text)
        case .system:
            return .system(text)
        case .toolCall:
            // tool_call 消息在 UI 中展示用，不直接映射到 LLM 消息
            return .system("工具调用: \(toolName ?? "")")
        case .toolResult:
            // tool_result 由 AgentService 自行处理为 LLMMessage.tool
            return .system("工具结果: \(toolSummary ?? "")")
        }
    }
}
