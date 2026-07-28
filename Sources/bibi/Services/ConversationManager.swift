import Foundation

@Observable
final class ConversationManager {
    private(set) var conversations: [Conversation] = []
    private(set) var currentConversationId: UUID?
    private let db = DatabaseManager.shared
    init() { loadAll() }
    private func loadAll() {
        guard let records: [ConversationRecord] = try? db.fetch("SELECT * FROM conversation ORDER BY updated_at DESC") else { return }
        conversations = records.map { $0.toConversation() }
    }
    func loadConversations(for userId: UUID) {
        guard let records: [ConversationRecord] = try? db.fetch("SELECT * FROM conversation WHERE owner_id = ? ORDER BY updated_at DESC", args: [userId.uuidString]) else { return }
        conversations = records.map { $0.toConversation() }
    }
    @discardableResult
    func createConversation(title: String = "新对话", ownerId: UUID) -> Conversation {
        let c = Conversation(title: title, ownerId: ownerId); let r = ConversationRecord.from(c)
        try? db.run("INSERT INTO conversation(id,title,created_at,updated_at,message_count,owner_id) VALUES(?,?,?,?,?,?)", args: [r.id, r.title, r.createdAt, r.updatedAt, r.messageCount, r.ownerId])
        conversations.insert(c, at: 0); currentConversationId = c.id; return c
    }
    func deleteConversation(id: UUID) {
        try? db.run("DELETE FROM conversation WHERE id = ?", args: [id.uuidString])
        try? db.run("DELETE FROM chat_message_record WHERE conversation_id = ?", args: [id.uuidString])
        conversations.removeAll { $0.id == id }; if currentConversationId == id { currentConversationId = nil }
    }
    func renameConversation(id: UUID, title: String) {
        try? db.run("UPDATE conversation SET title = ?, updated_at = ? WHERE id = ?", args: [title, Date(), id.uuidString])
        conversations.first(where: { $0.id == id })?.title = title
    }
    func switchConversation(id: UUID) { currentConversationId = id }
    func saveMessages(_ messages: [ChatMessage], for userId: UUID?) {
        guard let convId = currentConversationId?.uuidString else { return }
        let now = Date()
        for m in messages {
            let json = m.toolArgs.flatMap { try? JSONSerialization.data(withJSONObject: $0) }.flatMap { String(data: $0, encoding: .utf8) }
            try? db.run("INSERT INTO chat_message_record(id,role,content,created_at,tool_name,tool_args_json,tool_status,tool_summary,conversation_id) VALUES(?,?,?,?,?,?,?,?,?)",
                        args: [UUID().uuidString, m.role.rawValue, m.text, now, m.toolName ?? .none, json ?? .none, m.toolStatus?.rawValue ?? .none, m.toolSummary ?? .none, convId])
        }
        try? db.run("UPDATE conversation SET message_count = message_count + ?, updated_at = ? WHERE id = ?", args: [messages.count, now, convId])
        conversations.first(where: { $0.id.uuidString == convId })?.messageCount += messages.count
    }
}
