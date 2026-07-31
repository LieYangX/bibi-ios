import Foundation
import GRDB

/**
 * 聊天消息数据库记录。
 *
 * @author xiangwei
 */
struct ChatMessageRecord: Codable, FetchableRecord, PersistableRecord {
    let id: String
    let role: String
    let content: String
    let createdAt: Date
    let toolName: String?
    let toolArgsJSON: String?
    let toolStatus: String?
    let toolSummary: String?
    let conversationId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt = "created_at"
        case toolName = "tool_name"
        case toolArgsJSON = "tool_args_json"
        case toolStatus = "tool_status"
        case toolSummary = "tool_summary"
        case conversationId = "conversation_id"
    }

    /**
     * 转换为界面消息。
     *
     * @returns 聊天消息
     */
    func toChatMessage() -> ChatMessage {
        var message = ChatMessage(
            id: UUID(uuidString: id) ?? UUID(),
            role: MessageRole(rawValue: role) ?? .system,
            text: content,
            timestamp: createdAt
        )
        message.toolName = toolName
        message.toolStatus = toolStatus.flatMap { ToolCallStatus(rawValue: $0) }
        message.toolSummary = toolSummary
        message.toolArgs = decodedToolArguments
        return message
    }

    /**
     * 从界面消息创建数据库记录。
     *
     * @param message 聊天消息
     * @param conversationId 对话标识
     * @returns 数据库记录
     */
    static func from(_ message: ChatMessage, conversationId: UUID) -> ChatMessageRecord {
        ChatMessageRecord(
            id: message.id.uuidString,
            role: message.role.rawValue,
            content: message.text,
            createdAt: message.timestamp,
            toolName: message.toolName,
            toolArgsJSON: encodeToolArguments(message.toolArgs),
            toolStatus: message.toolStatus?.rawValue,
            toolSummary: message.toolSummary,
            conversationId: conversationId.uuidString
        )
    }

    private var decodedToolArguments: [String: Any]? {
        guard let toolArgsJSON,
              let data = toolArgsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return object as? [String: Any]
    }

    private static func encodeToolArguments(_ arguments: [String: Any]?) -> String? {
        guard let arguments,
              let data = try? JSONSerialization.data(withJSONObject: arguments) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
