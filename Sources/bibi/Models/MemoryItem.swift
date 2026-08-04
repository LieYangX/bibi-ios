import Foundation

/**
 * 智能体记忆类别
 *
 * 记忆分为三类：灵魂设定、用户画像、长久记忆。
 *
 * @author xiangwei
 */
enum MemoryCategory: String, CaseIterable {
    /// 灵魂设定：小笔的自我认知、性格与说话方式（每用户一条，编辑即覆盖）
    case soul

    /// 用户画像：关于用户的事实性信息（职业、习惯、偏好等）
    case userProfile = "user_profile"

    /// 长久记忆：跨会话的持久事实与重要事件
    case longTerm = "long_term"

    /// 设置页展示名称
    var displayName: String {
        switch self {
        case .soul: return "灵魂设定"
        case .userProfile: return "用户画像"
        case .longTerm: return "长久记忆"
        }
    }
}

/**
 * 智能体记忆条目
 *
 * UI 层使用的记忆模型，按类别组织，每条记忆归属一个本地用户。
 *
 * @author xiangwei
 */
@Observable
final class MemoryItem: Identifiable {
    /// 记忆条目唯一标识
    let id: UUID

    /// 归属的本地用户标识
    let ownerId: UUID

    /// 记忆类别
    let category: MemoryCategory

    /// 记忆内容
    var content: String

    /// 重要度（0~1），用于注入排序
    var importance: Double

    /// 创建时间
    let createdAt: Date

    /// 最近更新时间
    var updatedAt: Date

    /**
     * 初始化记忆条目
     *
     * @param id 条目标识
     * @param ownerId 归属用户标识
     * @param category 记忆类别
     * @param content 记忆内容
     * @param importance 重要度（默认 0.5）
     * @author xiangwei
     */
    init(
        id: UUID = UUID(),
        ownerId: UUID,
        category: MemoryCategory,
        content: String,
        importance: Double = 0.5,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ownerId = ownerId
        self.category = category
        self.content = content
        self.importance = importance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
