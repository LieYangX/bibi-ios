import Foundation
import GRDB

final class DatabaseManager {
    nonisolated(unsafe) static let shared = DatabaseManager()
    private var dbQueue: DatabaseQueue?
    private init() {}
    func open() throws {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: dir.appending(path: "bibi.sqlite").path)
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "local_user", ifNotExists: true) { t in
                t.column("id", .text).primaryKey(); t.column("display_name", .text).notNull()
                t.column("avatar_color", .text).notNull().defaults(to: "#F7BA1E")
                t.column("created_at", .datetime).notNull(); t.column("last_active_at", .datetime).notNull()
                t.column("pc_user_id", .text); t.column("pc_device_id", .text)
            }
            try db.create(table: "conversation", ifNotExists: true) { t in
                t.column("id", .text).primaryKey(); t.column("title", .text).notNull().defaults(to: "新对话")
                t.column("created_at", .datetime).notNull(); t.column("updated_at", .datetime).notNull()
                t.column("message_count", .integer).notNull().defaults(to: 0); t.column("owner_id", .text).notNull()
            }
            try db.create(table: "chat_message_record", ifNotExists: true) { t in
                t.column("id", .text).primaryKey(); t.column("role", .text).notNull(); t.column("content", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("tool_name", .text); t.column("tool_args_json", .text)
                t.column("tool_status", .text); t.column("tool_summary", .text); t.column("conversation_id", .text)
            }
            try db.create(table: "app_setting", ifNotExists: true) { t in
                t.column("key", .text).primaryKey(); t.column("value", .text).notNull(); t.column("updated_at", .datetime).notNull()
            }
        }
        m.registerMigration("v2") { db in
            try db.create(table: "agent_log", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("trace_id", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("model", .text).notNull()
                t.column("round_index", .integer).notNull()
                t.column("status", .text).notNull()
                t.column("request_json", .text).notNull()
                t.column("response_json", .text).notNull()
                t.column("duration_ms", .integer).notNull()
                t.column("error_message", .text)
            }
        }
        m.registerMigration("v3") { db in
            // 思考模式推理内容持久化，用于历史对话中弱化展示
            try db.alter(table: "chat_message_record") { t in
                t.add(column: "reasoning_content", .text)
            }
        }
        m.registerMigration("v4") { db in
            // 智能体记忆表：灵魂设定（soul）/ 用户画像（user_profile）/ 长久记忆（long_term）
            try db.create(table: "memory_item", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("owner_id", .text).notNull()
                t.column("category", .text).notNull()
                t.column("content", .text).notNull()
                t.column("importance", .double).notNull().defaults(to: 0.5)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            // 按用户与类别建立查询索引，加快记忆注入时的读取
            try db.create(indexOn: "memory_item", columns: ["owner_id", "category"])
        }
        try m.migrate(dbQueue!)
    }
    func fetch<T: FetchableRecord & Decodable>(_ sql: String, args: StatementArguments = []) throws -> [T] {
        guard let q = dbQueue else { return [] }
        return try q.read { db in try T.fetchAll(db, sql: sql, arguments: args) }
    }
    func run(_ sql: String, args: StatementArguments = []) throws {
        guard let q = dbQueue else { return }
        try q.write { db in try db.execute(sql: sql, arguments: args) }
    }

    /**
     * 在同一事务中删除本地用户及其全部对话数据。
     *
     * @param id 本地用户标识
     * @throws 数据库写入异常
     * @author xiangwei
     */
    func deleteLocalUserData(id: String) throws {
        guard let q = dbQueue else { return }
        try q.write { db in
            try db.execute(
                sql: """
                    DELETE FROM chat_message_record
                    WHERE conversation_id IN (
                        SELECT id FROM conversation WHERE owner_id = ?
                    )
                    """,
                arguments: [id]
            )
            try db.execute(
                sql: "DELETE FROM conversation WHERE owner_id = ?",
                arguments: [id]
            )
            try db.execute(
                sql: "DELETE FROM local_user WHERE id = ?",
                arguments: [id]
            )
            // 同步清理该用户的全部智能体记忆
            try db.execute(
                sql: "DELETE FROM memory_item WHERE owner_id = ?",
                arguments: [id]
            )
        }
    }
}

struct LocalUserRecord: Codable, FetchableRecord, PersistableRecord {
    let id, displayName, avatarColor: String; let createdAt, lastActiveAt: Date
    let pcUserId, pcDeviceId: String?
    enum CodingKeys: String, CodingKey {
        case id, displayName = "display_name", avatarColor = "avatar_color"
        case createdAt = "created_at", lastActiveAt = "last_active_at"
        case pcUserId = "pc_user_id", pcDeviceId = "pc_device_id"
    }
    func toLocalUser() -> LocalUser {
        let u = LocalUser(displayName: displayName, avatarColor: avatarColor)
        u.id = UUID(uuidString: id) ?? u.id; u.createdAt = createdAt; u.lastActiveAt = lastActiveAt
        u.pcUserId = pcUserId; u.pcDeviceId = pcDeviceId; return u
    }
    static func from(_ u: LocalUser) -> Self {
        Self(id: u.id.uuidString, displayName: u.displayName, avatarColor: u.avatarColor,
             createdAt: u.createdAt, lastActiveAt: u.lastActiveAt, pcUserId: u.pcUserId, pcDeviceId: u.pcDeviceId)
    }
}

struct ConversationRecord: Codable, FetchableRecord, PersistableRecord {
    let id, title: String; let createdAt, updatedAt: Date; let messageCount: Int; let ownerId: String
    enum CodingKeys: String, CodingKey {
        case id, title, messageCount = "message_count"
        case createdAt = "created_at", updatedAt = "updated_at", ownerId = "owner_id"
    }
    func toConversation() -> Conversation {
        let c = Conversation(title: title, ownerId: UUID(uuidString: ownerId) ?? UUID())
        c.id = UUID(uuidString: id) ?? c.id; c.createdAt = createdAt; c.updatedAt = updatedAt
        c.messageCount = messageCount; return c
    }
    static func from(_ c: Conversation) -> Self {
        Self(id: c.id.uuidString, title: c.title, createdAt: c.createdAt, updatedAt: c.updatedAt,
             messageCount: c.messageCount, ownerId: c.ownerId.uuidString)
    }
}

/**
 * 智能体请求日志 GRDB 记录。
 *
 * @author xiangwei
 */
struct AgentLogRecord: Codable, FetchableRecord, PersistableRecord {
    let id: String
    let traceId: String
    let timestamp: Date
    let model: String
    let roundIndex: Int
    let status: String
    let requestJSON: String
    let responseJSON: String
    let durationMS: Int
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case traceId = "trace_id"
        case timestamp
        case model
        case roundIndex = "round_index"
        case status
        case requestJSON = "request_json"
        case responseJSON = "response_json"
        case durationMS = "duration_ms"
        case errorMessage = "error_message"
    }

    /**
     * 转为 UI 层使用的模型。
     *
     * @returns 智能体日志记录模型
     */
    func toEntry() -> AgentLogEntry {
        AgentLogEntry(
            id: UUID(uuidString: id) ?? UUID(),
            traceId: traceId,
            timestamp: timestamp,
            model: model,
            roundIndex: roundIndex,
            status: AgentLogStatus(rawValue: status) ?? .error,
            requestJSON: requestJSON,
            responseJSON: responseJSON,
            durationMS: durationMS,
            errorMessage: errorMessage
        )
    }

    /**
     * 从 UI 层模型创建 GRDB 记录。
     *
     * @param entry 智能体日志记录模型
     * @returns GRDB 记录
     */
    static func from(_ entry: AgentLogEntry) -> Self {
        Self(
            id: entry.id.uuidString,
            traceId: entry.traceId,
            timestamp: entry.timestamp,
            model: entry.model,
            roundIndex: entry.roundIndex,
            status: entry.status.rawValue,
            requestJSON: entry.requestJSON,
            responseJSON: entry.responseJSON,
            durationMS: entry.durationMS,
            errorMessage: entry.errorMessage
        )
    }
}
