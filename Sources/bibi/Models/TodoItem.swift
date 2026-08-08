import Foundation

/**
 * 待办事项
 *
 * 用户通过待办工具创建的任务项，归属于本地用户。
 *
 * @author xiangwei
 */
@Observable
final class TodoItem: Identifiable {
    /// 待办唯一标识
    let id: UUID

    /// 归属的本地用户标识
    let conversationId: UUID

    /// 待办标题
    var title: String

    /// 是否已完成
    var isCompleted: Bool

    /// 创建时间
    let createdAt: Date

    /// 最近更新时间
    var updatedAt: Date

    /**
     * 初始化待办事项
     *
     * @param id 待办标识
     * @param conversationId 归属用户标识
     * @param title 待办标题
     * @param isCompleted 是否已完成
     * @param createdAt 创建时间
     * @param updatedAt 最近更新时间
     * @author xiangwei
     */
    init(
        id: UUID = UUID(),
        conversationId: UUID,
        title: String,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
