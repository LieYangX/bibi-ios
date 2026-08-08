import Foundation

/**
 * 定时任务
 *
 * 用户为 AI 设置的时间触发任务，到达指定时间后 AI 会收到通知并主动联系用户。
 *
 * @author xiangwei
 */
@Observable
final class ScheduledTask: Identifiable {
    /// 任务唯一标识
    let id: UUID

    /// 归属的本地用户标识
    let conversationId: UUID

    /// 任务标题（提醒 AI 做什么）
    var title: String

    /// 计划触发时间
    var scheduledAt: Date

    /// 是否重复触发
    var isRecurring: Bool

    /// 重复规则描述（如 daily、weekly、weekdays）
    var recurrenceRule: String?

    /// 是否启用
    var isEnabled: Bool

    /// 创建时间
    let createdAt: Date

    /// 最近更新时间
    var updatedAt: Date

    /**
     * 初始化定时任务
     *
     * @param id 任务标识
     * @param conversationId 归属用户标识
     * @param title 任务标题
     * @param scheduledAt 计划触发时间
     * @param isRecurring 是否重复触发
     * @param recurrenceRule 重复规则描述
     * @param isEnabled 是否启用
     * @param createdAt 创建时间
     * @param updatedAt 最近更新时间
     * @author xiangwei
     */
    init(
        id: UUID = UUID(),
        conversationId: UUID,
        title: String,
        scheduledAt: Date,
        isRecurring: Bool = false,
        recurrenceRule: String? = nil,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.title = title
        self.scheduledAt = scheduledAt
        self.isRecurring = isRecurring
        self.recurrenceRule = recurrenceRule
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
