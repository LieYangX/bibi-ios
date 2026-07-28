import Foundation
import GRDB

final class DatabaseManager {
    nonisolated(unsafe) static let shared = DatabaseManager()
    private var dbQueue: DatabaseQueue?
    private init() {}
    func open() throws {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: dir.appendingPathComponent("bibi.sqlite").path)
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
