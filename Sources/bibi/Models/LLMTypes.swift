import Foundation

/**
 * LLM 流式事件
 *
 * 表示 DeepSeek SSE 流中的三种事件类型：文本片段、工具调用分片、结束信号。
 *
 * @author xiangwei
 */
enum LLMStreamEvent {
    /// 文本片段
    case chunk(String)

    /// 工具调用分片
    case toolCallDelta(index: Int, id: String?, name: String?, arguments: String?)

    /// 流式结束信号
    case finish(reason: String?)
}

/**
 * 完整的工具调用
 *
 * @author xiangwei
 */
struct ToolCall {
    /// 工具调用唯一标识
    let id: String

    /// 工具名
    let name: String

    /// 已解析的参数字典
    let arguments: [String: Any]
}

/**
 * LLM 消息类型
 *
 * 用于构建 DeepSeek API 请求体，支持 system、user、assistant、tool 四种角色。
 *
 * @author xiangwei
 */
enum LLMMessage {
    /// 系统提示词
    case system(String)

    /// 用户消息
    case user(String)

    /// 助手纯文本消息
    case assistant(String)

    /// 助手工具调用消息
    case assistantToolCalls(content: String, toolCalls: [ToolCall])

    /// 工具执行结果消息
    case tool(toolCallId: String, content: String)

    /**
     * 转为 DeepSeek API 的 JSON 字典
     *
     * @returns OpenAI 兼容格式的消息字典
     */
    func toJSON() -> [String: Any] {
        switch self {
        case .system(let text):
            return ["role": "system", "content": text]

        case .user(let text):
            return ["role": "user", "content": text]

        case .assistant(let text):
            return ["role": "assistant", "content": text]

        case .assistantToolCalls(let content, let toolCalls):
            let toolCallsJSON = toolCalls.map { toolCall -> [String: Any] in
                let argsString = (try? String(
                    data: JSONSerialization.data(withJSONObject: toolCall.arguments),
                    encoding: .utf8
                )) ?? "{}"

                return [
                    "id": toolCall.id,
                    "type": "function",
                    "function": [
                        "name": toolCall.name,
                        "arguments": argsString
                    ] as [String: Any]
                ]
            }

            var result: [String: Any] = [
                "role": "assistant",
                "tool_calls": toolCallsJSON
            ]

            if !content.isEmpty {
                result["content"] = content
            } else {
                result["content"] = NSNull()
            }

            return result

        case .tool(let toolCallId, let content):
            return [
                "role": "tool",
                "tool_call_id": toolCallId,
                "content": content
            ]
        }
    }
}

/**
 * SSE 响应块
 *
 * @author xiangwei
 */
struct StreamChunk: Decodable {
    /// 选择列表
    let choices: [StreamChoice]?
}

/**
 * SSE 选择项
 *
 * @author xiangwei
 */
struct StreamChoice: Decodable {
    /// 增量内容
    let delta: StreamDelta?

    /// 结束原因
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

/**
 * SSE 增量内容
 *
 * @author xiangwei
 */
struct StreamDelta: Decodable {
    /// 文本内容
    let content: String?

    /// 工具调用分片列表
    let toolCalls: [StreamToolCall]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

/**
 * SSE 工具调用分片
 *
 * @author xiangwei
 */
struct StreamToolCall: Decodable {
    /// 工具调用索引
    let index: Int

    /// 工具调用标识
    let id: String?

    /// 函数信息
    let function: StreamToolFunction?
}

/**
 * SSE 工具函数分片
 *
 * @author xiangwei
 */
struct StreamToolFunction: Decodable {
    /// 工具名
    let name: String?

    /// 参数 JSON 片段
    let arguments: String?
}

/**
 * LLM 调用错误
 *
 * @author xiangwei
 */
enum LLMError: Error, LocalizedError {
    /// API 调用失败
    case apiError(String)

    /// 工具调用数据不完整
    case invalidToolCall

    /// 工具调用轮次超过限制
    case toolCallLimitExceeded

    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "LLM 调用失败: \(message)"
        case .invalidToolCall:
            return "智能体返回了不完整的工具调用，请重试"
        case .toolCallLimitExceeded:
            return "工具连续调用次数过多，已停止本次请求"
        }
    }
}
