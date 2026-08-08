import Foundation
import GRDB

/**
 * 待办事项 GRDB 记录
 *
 * 与 todo_item 表一一对应，负责待办事项的持久化读写。
 *
 * @author xiangwei
 */
struct TodoItemRecord: Codable, FetchableRecord, PersistableRecord {
    /// 待办标识
    let id: String

    /// 归属用户标识
    let conversationId: String

    /// 待办标题
    let title: String

    /// 是否已完成
    let isCompleted: Bool

    /// 创建时间
    let createdAt: Date

    /// 最近更新时间
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "owner_id"
        case title
        case isCompleted = "is_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /**
     * 转为 UI 层使用的待办模型
     *
     * @returns 待办事项模型
     * @author xiangwei
     */
    func toTodoItem() -> TodoItem {
        TodoItem(
            id: UUID(uuidString: id) ?? UUID(),
            conversationId: UUID(uuidString: conversationId) ?? UUID(),
            title: title,
            isCompleted: isCompleted,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /**
     * 从 UI 层模型创建 GRDB 记录
     *
     * @param item 待办事项模型
     * @returns GRDB 记录
     * @author xiangwei
     */
    static func from(_ item: TodoItem) -> Self {
        Self(
            id: item.id.uuidString,
            conversationId: item.conversationId.uuidString,
            title: item.title,
            isCompleted: item.isCompleted,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}
