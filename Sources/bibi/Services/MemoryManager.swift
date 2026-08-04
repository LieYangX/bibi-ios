import Foundation

/**
 * 智能体记忆管理器
 *
 * 负责灵魂设定、用户画像、长久记忆三类记忆的持久化读写，
 * 并提供注入到 LLM 上下文的格式化文本。
 *
 * @author xiangwei
 */
@MainActor
@Observable
final class MemoryManager {
    /// 灵魂设定（每用户仅一条，编辑即覆盖）
    private(set) var soulItem: MemoryItem?

    /// 用户画像条目
    private(set) var profileItems: [MemoryItem] = []

    /// 长久记忆条目
    private(set) var longTermItems: [MemoryItem] = []

    /// 当前记忆归属的用户标识
    private var currentUserId: UUID?

    /// 数据库管理器
    private let db = DatabaseManager.shared

    /// 单条长久记忆注入的最大字符数
    private static let longTermItemLimit = 200

    /// 注入长久记忆的条数上限
    private static let longTermCountLimit = 20

    /// 灵魂设定注入的最大字符数
    private static let soulLimit = 1_500

    /// 单条用户画像注入的最大字符数
    private static let profileItemLimit = 200

    /// 注入用户画像的条数上限
    private static let profileCountLimit = 10

    /// 用户画像注入的总字符数上限
    private static let profileTotalLimit = 1_200

    /**
     * 加载指定用户的全部记忆。
     *
     * @param userId 本地用户标识
     * @author xiangwei
     */
    func loadMemories(for userId: UUID) {
        currentUserId = userId

        let soulRecords: [MemoryItemRecord] = fetchRecords(category: .soul, userId: userId)
        soulItem = soulRecords.first.map { $0.toMemoryItem() }

        profileItems = fetchRecords(category: .userProfile, userId: userId)
            .map { $0.toMemoryItem() }
            .sorted { $0.updatedAt > $1.updatedAt }

        longTermItems = fetchRecords(category: .longTerm, userId: userId)
            .map { $0.toMemoryItem() }
            .sorted { $0.importance > $1.importance }
    }

    /**
     * 保存灵魂设定内容。
     *
     * 已存在则覆盖内容并更新时间，不存在则新建条目。
     *
     * @param content 灵魂设定文本
     * @author xiangwei
     */
    func saveSoul(content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let currentUserId else { return }

        if let soulItem {
            soulItem.content = trimmed
            soulItem.updatedAt = Date()
            updateRecord(soulItem)
        } else {
            let item = MemoryItem(
                ownerId: currentUserId,
                category: .soul,
                content: trimmed,
                importance: 1.0
            )
            insertRecord(item)
            soulItem = item
        }
    }

    /**
     * 追加合并灵魂设定。
     *
     * 用于对话中自动提炼出的行为指导：以"补充规则"形式追加到现有灵魂内容末尾，
     * 不覆盖用户手写内容；未设置灵魂时直接新建。
     *
     * @param content 追加的灵魂设定文本
     * @author xiangwei
     */
    func appendSoul(content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let currentUserId, !trimmed.isEmpty else { return }

        if let soulItem {
            // 已包含相同内容时跳过，避免重复积累
            guard !soulItem.content.contains(trimmed) else { return }
            soulItem.content = soulItem.content + "\n\n## 对话中提炼的行为规则\n" + trimmed
            soulItem.updatedAt = Date()
            updateRecord(soulItem)
        } else {
            let item = MemoryItem(
                ownerId: currentUserId,
                category: .soul,
                content: trimmed,
                importance: 1.0
            )
            insertRecord(item)
            soulItem = item
        }
    }

    /**
     * 新增一条用户画像。
     *
     * @param content 画像内容
     * @author xiangwei
     */
    func addProfile(content: String) {
        guard !hasSimilarItem(in: profileItems, content: content) else { return }
        addItem(category: .userProfile, content: content, importance: 0.7)
    }

    /**
     * 新增一条长久记忆。
     *
     * @param content 记忆内容
     * @param importance 重要度（0~1）
     * @author xiangwei
     */
    func addLongTerm(content: String, importance: Double = 0.6) {
        guard !hasSimilarItem(in: longTermItems, content: content) else { return }
        addItem(category: .longTerm, content: content, importance: importance)
    }

    /**
     * 更新条目内容。
     *
     * @param item 待更新的记忆条目
     * @param content 新内容
     * @author xiangwei
     */
    func updateItem(_ item: MemoryItem, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        item.content = trimmed
        item.updatedAt = Date()
        updateRecord(item)
    }

    /**
     * 删除一条记忆条目。
     *
     * @param item 待删除的记忆条目
     * @author xiangwei
     */
    func deleteItem(_ item: MemoryItem) {
        deleteRecord(item)
        switch item.category {
        case .soul:
            if soulItem?.id == item.id { soulItem = nil }
        case .userProfile:
            profileItems.removeAll { $0.id == item.id }
        case .longTerm:
            longTermItems.removeAll { $0.id == item.id }
        }
    }

    /**
     * 清空当前用户的某类记忆（测试与调试用）。
     *
     * @param category 记忆类别
     * @author xiangwei
     */
    func clear(category: MemoryCategory) {
        guard let currentUserId else { return }
        let sql = "DELETE FROM memory_item WHERE owner_id = ? AND category = ?"
        try? db.run(sql, args: [currentUserId.uuidString, category.rawValue])
        switch category {
        case .soul:
            soulItem = nil
        case .userProfile:
            profileItems.removeAll()
        case .longTerm:
            longTermItems.removeAll()
        }
    }

    // MARK: - 注入文本构建

    /**
     * 构建灵魂设定注入文本。
     *
     * 裁剪到字符上限，避免用户手写内容过长撑爆上下文。
     *
     * @returns 灵魂设定文本，未设置时返回 nil
     * @author xiangwei
     */
    func soulPrompt() -> String? {
        guard let soulItem, !soulItem.content.isEmpty else { return nil }
        let content = soulItem.content.count > Self.soulLimit
            ? String(soulItem.content.prefix(Self.soulLimit))
            : soulItem.content
        return "【灵魂设定】\n\(content)"
    }

    /**
     * 构建用户画像注入文本。
     *
     * 按最近更新时间取前若干条，并裁剪单条与总字符数上限，控制上下文开销。
     *
     * @returns 用户画像文本，无条目时返回 nil
     * @author xiangwei
     */
    func profilePrompt() -> String? {
        // 画像按更新时间倒序，优先注入最新内容
        let items = profileItems
            .filter { !$0.content.isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(Self.profileCountLimit)
        guard !items.isEmpty else { return nil }

        var lines: [String] = []
        var totalLength = 0
        for item in items {
            let content = item.content.count > Self.profileItemLimit
                ? String(item.content.prefix(Self.profileItemLimit))
                : item.content
            let line = "- \(content)"
            totalLength += line.count
            if totalLength > Self.profileTotalLimit { break }
            lines.append(line)
        }
        guard !lines.isEmpty else { return nil }
        return "【用户画像】\n" + lines.joined(separator: "\n")
    }

    /**
     * 构建长久记忆注入文本。
     *
     * 按重要度降序排列，并裁剪到条数与总字符数上限，控制上下文开销。
     *
     * @returns 长久记忆文本，无条目时返回 nil
     * @author xiangwei
     */
    func longTermPrompt() -> String? {
        let items = longTermItems
            .filter { !$0.content.isEmpty }
            .prefix(Self.longTermCountLimit)
        guard !items.isEmpty else { return nil }

        var lines: [String] = []
        var totalLength = 0
        for item in items {
            let content = item.content.count > Self.longTermItemLimit
                ? String(item.content.prefix(Self.longTermItemLimit))
                : item.content
            let line = "- \(content)"
            totalLength += line.count
            if totalLength > 1_200 { break }
            lines.append(line)
        }
        guard !lines.isEmpty else { return nil }
        return "【长久记忆】\n" + lines.joined(separator: "\n")
    }

    // MARK: - 记住指令检测

    /**
     * 从用户消息中提取"记住..."指令的内容。
     *
     * 支持"记住""记下""别忘了""帮我记住"等开头形式，
     * 返回要记住的内容，未命中指令时返回 nil。
     *
     * @param text 用户消息
     * @returns 提取的记忆内容
     * @author xiangwei
     */
    static func extractRememberContent(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            "记住",
            "记下",
            "别忘了",
            "帮我记住"
        ]

        for pattern in patterns {
            guard let range = trimmed.range(of: pattern) else { continue }
            var content = String(trimmed[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            content = content.trimmingCharacters(in: CharacterSet(charactersIn: "，。！？：:、,.!?"))
            if !content.isEmpty, content.count >= 2 {
                return content
            }
        }
        return nil
    }

    // MARK: - 私有方法

    /**
     * 按类别与用户查询记忆记录。
     *
     * @param category 记忆类别
     * @param userId 本地用户标识
     * @returns 记忆记录数组
     * @author xiangwei
     */
    private func fetchRecords(category: MemoryCategory, userId: UUID) -> [MemoryItemRecord] {
        let sql = """
            SELECT * FROM memory_item
            WHERE owner_id = ? AND category = ?
            ORDER BY updated_at DESC
            """
        return (try? db.fetch(sql, args: [userId.uuidString, category.rawValue])) ?? []
    }

    /**
     * 新增一条记忆条目并同步内存列表。
     *
     * @param category 记忆类别
     * @param content 记忆内容
     * @param importance 重要度
     * @author xiangwei
     */
    private func addItem(category: MemoryCategory, content: String, importance: Double) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let currentUserId, !trimmed.isEmpty else { return }

        let item = MemoryItem(
            ownerId: currentUserId,
            category: category,
            content: trimmed,
            importance: importance
        )
        insertRecord(item)

        switch category {
        case .soul:
            soulItem = item
        case .userProfile:
            profileItems.insert(item, at: 0)
        case .longTerm:
            longTermItems.append(item)
            longTermItems.sort { $0.importance > $1.importance }
        }
    }

    /**
     * 插入记忆记录。
     *
     * @param item 记忆条目
     * @author xiangwei
     */
    private func insertRecord(_ item: MemoryItem) {
        let record = MemoryItemRecord.from(item)
        let sql = """
            INSERT INTO memory_item(
                id, owner_id, category, content, importance, created_at, updated_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?)
            """
        try? db.run(
            sql,
            args: [
                record.id,
                record.ownerId,
                record.category,
                record.content,
                record.importance,
                record.createdAt,
                record.updatedAt
            ]
        )
    }

    /**
     * 更新记忆记录。
     *
     * @param item 记忆条目
     * @author xiangwei
     */
    private func updateRecord(_ item: MemoryItem) {
        let record = MemoryItemRecord.from(item)
        let sql = """
            UPDATE memory_item
            SET content = ?, importance = ?, updated_at = ?
            WHERE id = ?
            """
        try? db.run(
            sql,
            args: [record.content, record.importance, record.updatedAt, record.id]
        )
    }

    /**
     * 删除记忆记录。
     *
     * @param item 记忆条目
     * @author xiangwei
     */
    private func deleteRecord(_ item: MemoryItem) {
        try? db.run("DELETE FROM memory_item WHERE id = ?", args: [item.id.uuidString])
    }

    /**
     * 检查列表中是否已存在内容相近的条目。
     *
     * 用于自动提炼去重：完全相同或短内容包含于长内容时视为重复。
     *
     * @param items 待检查的条目列表
     * @param content 新内容
     * @returns 是否已存在相似条目
     * @author xiangwei
     */
    private func hasSimilarItem(in items: [MemoryItem], content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return items.contains { item in
            let existing = item.content
            return existing == trimmed || existing.contains(trimmed) || trimmed.contains(existing)
        }
    }
}
