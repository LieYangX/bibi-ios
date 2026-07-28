import Foundation

/**
 * 消息角色
 *
 * @author xiangwei
 */
enum MessageRole: String {
    /// 用户消息
    case user

    /// 助手消息
    case assistant

    /// 工具调用消息
    case toolCall

    /// 工具结果消息
    case toolResult

    /// 系统消息
    case system
}

/**
 * 工具调用状态
 *
 * @author xiangwei
 */
enum ToolCallStatus: String {
    /// 进行中
    case inProgress

    /// 成功
    case succeeded

    /// 失败
    case failed
}

/**
 * 聊天消息
 *
 * UI 层使用的临时消息模型，不直接持久化到 SwiftData。
 *
 * @author xiangwei
 */
struct ChatMessage: Identifiable {
    /// 消息唯一标识
    let id: UUID

    /// 角色
    let role: MessageRole

    /// 文本内容（Markdown）
    var text: String

    /// 时间戳
    let timestamp: Date

    /// 是否仍在流式输出
    var isStreaming: Bool

    /// 工具名（仅 toolCall / toolResult）
    var toolName: String?

    /// 工具参数（仅 UI 展示用）
    var toolArgs: [String: Any]?

    /// 工具调用状态
    var toolStatus: ToolCallStatus?

    /// 工具结果摘要
    var toolSummary: String?

    /**
     * 初始化消息
     */
    init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }

    /**
     * 创建用户消息
     */
    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, text: text)
    }

    /**
     * 创建助手消息
     */
    static func assistant(_ text: String) -> ChatMessage {
        ChatMessage(role: .assistant, text: text, isStreaming: true)
    }

    /**
     * 创建系统消息
     */
    static func system(_ text: String) -> ChatMessage {
        ChatMessage(role: .system, text: text)
    }

    /**
     * 创建工具调用消息
     */
    static func toolCall(name: String, args: [String: Any]) -> ChatMessage {
        var message = ChatMessage(role: .toolCall, text: "")
        message.toolName = name
        message.toolArgs = args
        message.toolStatus = .inProgress
        return message
    }

    /**
     * 创建工具结果消息
     */
    static func toolResult(name: String, summary: String) -> ChatMessage {
        var message = ChatMessage(role: .toolResult, text: "")
        message.toolName = name
        message.toolSummary = summary
        return message
    }
}
