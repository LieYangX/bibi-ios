import Foundation
import GRDB

/**
 * 定时任务 GRDB 记录
 *
 * 与 scheduled_task 表一一对应，负责定时任务的持久化读写。
 *
 * @author xiangwei
 */
struct ScheduledTaskRecord: Codable, FetchableRecord, PersistableRecord {
    /// 任务标识
    let id: String

    /// 归属用户标识
    let conversationId: String

    /// 任务标题
    let title: String

    /// 计划触发时间
    let scheduledAt: Date

    /// 是否重复触发
    let isRecurring: Bool

    /// 重复规则描述
    let recurrenceRule: String?

    /// 是否启用
    let isEnabled: Bool

    /// 创建时间
    let createdAt: Date

    /// 最近更新时间
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "owner_id"
        case title
        case scheduledAt = "scheduled_at"
        case isRecurring = "is_recurring"
        case recurrenceRule = "recurrence_rule"
        case isEnabled = "is_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /**
     * 转为 UI 层使用的定时任务模型
     *
     * @returns 定时任务模型
     * @author xiangwei
     */
    func toScheduledTask() -> ScheduledTask {
        let normalizedRule = recurrenceRule?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScheduledTask(
            id: UUID(uuidString: id) ?? UUID(),
            conversationId: UUID(uuidString: conversationId) ?? UUID(),
            title: title,
            scheduledAt: scheduledAt,
            isRecurring: isRecurring,
            recurrenceRule: normalizedRule?.isEmpty == false ? normalizedRule : nil,
            isEnabled: isEnabled,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /**
     * 从 UI 层模型创建 GRDB 记录
     *
     * @param task 定时任务模型
     * @returns GRDB 记录
     * @author xiangwei
     */
    static func from(_ task: ScheduledTask) -> Self {
        Self(
            id: task.id.uuidString,
            conversationId: task.conversationId.uuidString,
            title: task.title,
            scheduledAt: task.scheduledAt,
            isRecurring: task.isRecurring,
            recurrenceRule: task.recurrenceRule,
            isEnabled: task.isEnabled,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt
        )
    }
}
