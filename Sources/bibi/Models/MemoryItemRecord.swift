import Foundation
import GRDB

/**
 * 智能体记忆 GRDB 记录
 *
 * 与 memory_item 表一一对应，负责记忆条目的持久化读写。
 *
 * @author xiangwei
 */
struct MemoryItemRecord: Codable, FetchableRecord, PersistableRecord {
    /// 条目标识
    let id: String

    /// 归属用户标识
    let ownerId: String

    /// 记忆类别原始值
    let category: String

    /// 记忆内容
    let content: String

    /// 重要度
    let importance: Double

    /// 记忆来源原始值
    let source: String

    /// 提取置信度
    let confidence: Double

    /// 引用次数
    let accessCount: Int

    /// 最近引用时间
    let lastAccessedAt: Date

    /// 创建时间
    let createdAt: Date

    /// 最近更新时间
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case category
        case content
        case importance
        case source
        case confidence
        case accessCount = "access_count"
        case lastAccessedAt = "last_accessed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /**
     * 转为 UI 层使用的记忆模型
     *
     * @returns 记忆条目模型
     * @author xiangwei
     */
    func toMemoryItem() -> MemoryItem {
        MemoryItem(
            id: UUID(uuidString: id) ?? UUID(),
            ownerId: UUID(uuidString: ownerId) ?? UUID(),
            category: MemoryCategory(rawValue: category) ?? .longTerm,
            content: content,
            importance: importance,
            source: MemorySource(rawValue: source) ?? .manual,
            confidence: confidence,
            accessCount: accessCount,
            lastAccessedAt: lastAccessedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /**
     * 从 UI 层模型创建 GRDB 记录
     *
     * @param item 记忆条目模型
     * @returns GRDB 记录
     * @author xiangwei
     */
    static func from(_ item: MemoryItem) -> Self {
        Self(
            id: item.id.uuidString,
            ownerId: item.ownerId.uuidString,
            category: item.category.rawValue,
            content: item.content,
            importance: item.importance,
            source: item.source.rawValue,
            confidence: item.confidence,
            accessCount: item.accessCount,
            lastAccessedAt: item.lastAccessedAt,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}
