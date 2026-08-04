import Foundation

/**
 * 对话持久化管理器。
 *
 * @author xiangwei
 */
@Observable
final class ConversationManager {
    private(set) var conversations: [Conversation] = []
    private(set) var currentConversationId: UUID?
    private let db = DatabaseManager.shared

    init() {}

    /**
     * 加载指定用户的历史对话。
     *
     * 加载后尝试恢复该用户上次打开的会话。
     *
     * @param userId 本地用户标识
     * @author xiangwei
     */
    func loadConversations(for userId: UUID) {
        let sql = """
            SELECT * FROM conversation
            WHERE owner_id = ?
            ORDER BY updated_at DESC
            """
        guard let records: [ConversationRecord] = try? db.fetch(sql, args: [userId.uuidString]) else {
            return
        }
        conversations = records.map { $0.toConversation() }
        // 恢复上次打开的会话（若仍存在）
        if let lastId = UserDefaults.standard.string(forKey: Self.lastConversationKey(for: userId)),
           let lastConversationId = UUID(uuidString: lastId),
           conversations.contains(where: { $0.id == lastConversationId }) {
            currentConversationId = lastConversationId
        } else if !conversations.contains(where: { $0.id == currentConversationId }) {
            currentConversationId = nil
        }
    }

    /**
     * 创建新对话。
     *
     * @param title 对话标题
     * @param ownerId 本地用户标识
     * @returns 新对话
     * @author xiangwei
     */
    @discardableResult
    func createConversation(title: String = "新对话", ownerId: UUID) -> Conversation {
        let conversation = Conversation(title: title, ownerId: ownerId)
        let record = ConversationRecord.from(conversation)
        let sql = """
            INSERT INTO conversation(
                id, title, created_at, updated_at, message_count, owner_id
            ) VALUES(?, ?, ?, ?, ?, ?)
            """
        try? db.run(
            sql,
            args: [
                record.id,
                record.title,
                record.createdAt,
                record.updatedAt,
                record.messageCount,
                record.ownerId
            ]
        )
        conversations.insert(conversation, at: 0)
        currentConversationId = conversation.id
        persistCurrentConversation(for: ownerId)
        return conversation
    }

    /**
     * 切换对话并加载消息。
     *
     * 切换后持久化当前会话，便于下次启动恢复。
     *
     * @param id 对话标识
     * @returns 对话消息
     * @author xiangwei
     */
    func switchConversation(id: UUID) -> [ChatMessage] {
        currentConversationId = id
        if let conversation = conversations.first(where: { $0.id == id }) {
            persistCurrentConversation(for: conversation.ownerId)
        }
        return loadMessages(for: id)
    }

    /**
     * 重命名对话。
     *
     * @param id 对话标识
     * @param title 新标题
     * @author xiangwei
     */
    func renameConversation(id: UUID, title: String) {
        let updatedAt = Date()
        try? db.run(
            "UPDATE conversation SET title = ?, updated_at = ? WHERE id = ?",
            args: [title, updatedAt, id.uuidString]
        )
        if let conversation = conversations.first(where: { $0.id == id }) {
            conversation.title = title
            conversation.updatedAt = updatedAt
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }

    /**
     * 删除对话及其消息。
     *
     * @param id 对话标识
     * @author xiangwei
     */
    func deleteConversation(id: UUID) {
        try? db.run("DELETE FROM chat_message_record WHERE conversation_id = ?", args: [id.uuidString])
        try? db.run("DELETE FROM conversation WHERE id = ?", args: [id.uuidString])
        conversations.removeAll { $0.id == id }
        if currentConversationId == id {
            currentConversationId = nil
        }
    }

    /**
     * 清空内存中的会话状态。
     * @author xiangwei
     */
    func clear() {
        conversations.removeAll()
        currentConversationId = nil
    }

    /**
     * 增量追加消息。
     *
     * @param messages 本轮新增消息
     * @author xiangwei
     */
    func appendMessages(_ messages: [ChatMessage]) {
        guard let conversationId = currentConversationId, !messages.isEmpty else { return }
        let sql = """
            INSERT OR REPLACE INTO chat_message_record(
                id, role, content, reasoning_content, created_at, tool_name,
                tool_args_json, tool_status, tool_summary, conversation_id
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

        for message in messages {
            let record = ChatMessageRecord.from(message, conversationId: conversationId)
            try? db.run(
                sql,
                args: [
                    record.id,
                    record.role,
                    record.content,
                    record.reasoningContent ?? .none,
                    record.createdAt,
                    record.toolName ?? .none,
                    record.toolArgsJSON ?? .none,
                    record.toolStatus ?? .none,
                    record.toolSummary ?? .none,
                    record.conversationId ?? .none
                ]
            )
        }

        let updatedAt = Date()
        let updateSql = """
            UPDATE conversation
            SET message_count = message_count + ?, updated_at = ?
            WHERE id = ?
            """
        try? db.run(updateSql, args: [messages.count, updatedAt, conversationId.uuidString])

        if let conversation = conversations.first(where: { $0.id == conversationId }) {
            conversation.messageCount += messages.count
            conversation.updatedAt = updatedAt
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }

    private func loadAll() {
        let sql = "SELECT * FROM conversation ORDER BY updated_at DESC"
        guard let records: [ConversationRecord] = try? db.fetch(sql) else { return }
        conversations = records.map { $0.toConversation() }
    }

    private func loadMessages(for conversationId: UUID) -> [ChatMessage] {
        let sql = """
            SELECT * FROM chat_message_record
            WHERE conversation_id = ?
            ORDER BY created_at ASC
            """
        guard let records: [ChatMessageRecord] = try? db.fetch(
            sql,
            args: [conversationId.uuidString]
        ) else {
            return []
        }
        return records.map { $0.toChatMessage() }
    }

    /**
     * 持久化指定用户的当前会话标识。
     *
     * @param userId 本地用户标识
     * @author xiangwei
     */
    private func persistCurrentConversation(for userId: UUID) {
        guard let conversationId = currentConversationId else { return }
        UserDefaults.standard.set(
            conversationId.uuidString,
            forKey: Self.lastConversationKey(for: userId)
        )
    }

    /**
     * 生成指定用户的"上次会话"存储键。
     *
     * @param userId 本地用户标识
     * @returns UserDefaults 存储键
     * @author xiangwei
     */
    private static func lastConversationKey(for userId: UUID) -> String {
        "last_conversation_id_\(userId.uuidString)"
    }
}
