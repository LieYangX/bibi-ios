import Foundation

/**
 * 智能体记忆类别
 *
 * 记忆分为三类：灵魂设定、用户画像、长久记忆。
 *
 * @author xiangwei
 */
enum MemoryCategory: String, CaseIterable {
    /// 灵魂设定：星枢的自我认知、性格与说话方式
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
 * 记忆来源
 *
 * 标识记忆是如何进入系统的，影响去重、合并与注入策略。
 *
 * @author xiangwei
 */
enum MemorySource: String, CaseIterable {
    /// 用户手动编辑或添加
    case manual

    /// 来自「记住...」等明确指令
    case rememberCommand = "remember_command"

    /// 对话结束后自动提炼
    case autoExtracted = "auto_extracted"

    /// 展示名称
    var displayName: String {
        switch self {
        case .manual: return "手动"
        case .rememberCommand: return "指令"
        case .autoExtracted: return "自动"
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

    /// 重要度（0~1），用于注入排序与淘汰
    var importance: Double

    /// 记忆来源
    let source: MemorySource

    /// 提取置信度（0~1），自动提取时使用
    var confidence: Double

    /// 被引用次数，引用可提升重要度
    var accessCount: Int

    /// 最近被引用时间，用于重要度衰减
    var lastAccessedAt: Date

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
     * @param source 记忆来源（默认 manual）
     * @param confidence 提取置信度（默认 1.0）
     * @param accessCount 引用次数（默认 0）
     * @param lastAccessedAt 最近引用时间（默认当前时间）
     * @param createdAt 创建时间
     * @param updatedAt 最近更新时间
     * @author xiangwei
     */
    init(
        id: UUID = UUID(),
        ownerId: UUID,
        category: MemoryCategory,
        content: String,
        importance: Double = 0.5,
        source: MemorySource = .manual,
        confidence: Double = 1.0,
        accessCount: Int = 0,
        lastAccessedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ownerId = ownerId
        self.category = category
        self.content = content
        self.importance = importance
        self.source = source
        self.confidence = confidence
        self.accessCount = accessCount
        self.lastAccessedAt = lastAccessedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /**
     * 计算当前有效重要度。
     *
     * 重要度会随时间衰减，引用可提升并刷新衰减起点。
     *
     * @returns 衰减后的有效重要度
     * @author xiangwei
     */
    func effectiveImportance() -> Double {
        let daysSinceAccess = Date().timeIntervalSince(lastAccessedAt) / 86_400
        let decay = min(daysSinceAccess * 0.01, 0.3)
        let boost = min(Double(accessCount) * 0.03, 0.15)
        return max(0, min(1, importance - decay + boost))
    }
}
