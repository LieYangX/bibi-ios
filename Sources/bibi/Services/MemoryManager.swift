import Foundation

/**
 * 智能体记忆管理器
 *
 * 负责灵魂设定、用户画像、长久记忆三类记忆的持久化读写、去重合并、
 * 生命周期维护，并提供注入到 LLM 上下文的格式化文本。
 *
 * 改造要点：
 * - 灵魂设定拆分为「手写核心」与「自动提炼规则」，防止规则无限追加。
 * - 记忆条目记录来源（手动 / 记住指令 / 自动提炼）与置信度。
 * - 长久记忆支持按当前话题检索相关条目，而非仅按重要度排序。
 * - 新增记忆时进行相似度去重，定期合并冗余条目。
 *
 * @author xiangwei
 */
@MainActor
@Observable
final class MemoryManager {
    /// 手写灵魂核心（每用户仅一条）
    private(set) var soulCoreItem: MemoryItem?

    /// 自动提炼的灵魂规则（可多条，去重维护）
    private(set) var soulRuleItems: [MemoryItem] = []

    /// 用户画像条目
    private(set) var profileItems: [MemoryItem] = []

    /// 长久记忆条目
    private(set) var longTermItems: [MemoryItem] = []

    /// 当前记忆归属的用户标识
    private var currentUserId: UUID?

    /// 数据库管理器
    private let db = DatabaseManager.shared

    // MARK: - 注入上限

    /// 灵魂核心注入的最大字符数
    private static let soulCoreLimit = 1_200

    /// 自动灵魂规则注入的最大字符数
    private static let soulRulesLimit = 600

    /// 单条长久记忆注入的最大字符数
    private static let longTermItemLimit = 200

    /// 注入长久记忆的条数上限
    private static let longTermCountLimit = 16

    /// 长久记忆注入的总字符数上限
    private static let longTermTotalLimit = 1_200

    /// 单条用户画像注入的最大字符数
    private static let profileItemLimit = 160

    /// 注入用户画像的条数上限
    private static let profileCountLimit = 10

    /// 用户画像注入的总字符数上限
    private static let profileTotalLimit = 1_000

    /// 自动提取记忆的最低置信度，低于此值丢弃
    private static let minConfidence = 0.55

    /// 相似内容判定阈值（较短内容被较长内容包含即视为重复）
    private static let similarityOverlapThreshold = 6

    // MARK: - 加载与清空

    /**
     * 加载指定用户的全部记忆。
     *
     * @param userId 本地用户标识
     * @author xiangwei
     */
    func loadMemories(for userId: UUID) {
        currentUserId = userId

        let soulRecords = fetchRecords(category: .soul, userId: userId)
        let soulItems = soulRecords.map { $0.toMemoryItem() }
        soulCoreItem = soulItems.first { $0.source == .manual }
        soulRuleItems = soulItems
            .filter { $0.source != .manual }
            .sorted { $0.updatedAt > $1.updatedAt }

        profileItems = fetchRecords(category: .userProfile, userId: userId)
            .map { $0.toMemoryItem() }
            .sorted { $0.updatedAt > $1.updatedAt }

        longTermItems = fetchRecords(category: .longTerm, userId: userId)
            .map { $0.toMemoryItem() }
            .sorted { $0.effectiveImportance() > $1.effectiveImportance() }

        // 记录加载结果，便于排查记忆为空的问题
        Task {
            await AppLogger.shared.log(
                .info,
                category: "memory",
                message: "记忆加载完成",
                metadata: [
                    "user_id": userId.uuidString,
                    "soul_core": "\(soulCoreItem != nil ? 1 : 0)",
                    "soul_rules": "\(soulRuleItems.count)",
                    "profiles": "\(profileItems.count)",
                    "long_term": "\(longTermItems.count)"
                ]
            )
        }
    }

    /**
     * 重新加载当前用户的记忆。
     *
     * 设置页打开时调用，确保内存与数据库状态一致。
     *
     * @author xiangwei
     */
    func reload() {
        guard let currentUserId else { return }
        loadMemories(for: currentUserId)
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
            soulCoreItem = nil
            soulRuleItems.removeAll()
        case .userProfile:
            profileItems.removeAll()
        case .longTerm:
            longTermItems.removeAll()
        }
    }

    // MARK: - 灵魂设定

    /**
     * 追加一条灵魂规则。
     *
     * 与已有规则去重，不覆盖用户手写核心；当核心为空时，规则即作为临时核心。
     *
     * @param content 规则内容
     * @param source 记忆来源（默认 autoExtracted）
     * @author xiangwei
     */
    func appendSoul(content: String, source: MemorySource = .autoExtracted) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let currentUserId, !trimmed.isEmpty else { return }

        // 与已有规则去重
        let existingRules = soulRuleItems.map { $0.content }
        guard !isContentRedundant(trimmed, among: existingRules) else { return }

        let item = MemoryItem(
            ownerId: currentUserId,
            category: .soul,
            content: trimmed,
            importance: 0.95,
            source: source,
            confidence: source == .rememberCommand ? 0.9 : 0.8
        )
        insertRecord(item)
        soulRuleItems.insert(item, at: 0)

        // 限制规则数量，防止无限增长
        if soulRuleItems.count > 20 {
            let overflow = soulRuleItems.suffix(from: 20)
            soulRuleItems = Array(soulRuleItems.prefix(20))
            for old in overflow {
                deleteRecord(old)
            }
        }
    }

    // MARK: - 用户画像

    /**
     * 新增一条用户画像。
     *
     * @param content 画像内容
     * @param source 记忆来源（默认 manual）
     * @param confidence 置信度（默认 1.0）
     * @author xiangwei
     */
    func addProfile(content: String, source: MemorySource = .manual, confidence: Double = 1.0) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 尝试合并到已有相似画像
        if let existing = findSimilarItem(in: profileItems, content: trimmed) {
            // 新内容更丰富时更新，否则跳过
            if trimmed.count > existing.content.count {
                existing.content = trimmed
                existing.updatedAt = Date()
                existing.confidence = max(existing.confidence, confidence)
                updateRecord(existing)
                profileItems.sort { $0.updatedAt > $1.updatedAt }
            }
            return
        }

        addItem(category: .userProfile, content: trimmed, importance: 0.75, source: source, confidence: confidence)
    }

    // MARK: - 长久记忆

    /**
     * 新增一条长久记忆。
     *
     * @param content 记忆内容
     * @param importance 重要度（0~1）
     * @param source 记忆来源（默认 autoExtracted）
     * @param confidence 置信度（默认 0.6）
     * @author xiangwei
     */
    func addLongTerm(
        content: String,
        importance: Double = 0.6,
        source: MemorySource = .autoExtracted,
        confidence: Double = 0.6
    ) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, confidence >= Self.minConfidence else { return }

        // 与已有相似记忆合并
        if let existing = findSimilarItem(in: longTermItems, content: trimmed) {
            if trimmed.count > existing.content.count {
                existing.content = trimmed
                existing.updatedAt = Date()
                existing.importance = max(existing.importance, importance)
                existing.confidence = max(existing.confidence, confidence)
                updateRecord(existing)
                longTermItems.sort { $0.effectiveImportance() > $1.effectiveImportance() }
            }
            return
        }

        addItem(category: .longTerm, content: trimmed, importance: importance, source: source, confidence: confidence)

        // 数量超过上限时淘汰有效重要度最低的条目
        if longTermItems.count > 50 {
            pruneLongTermMemories(targetCount: 40)
        }
    }

    /**
     * 根据当前用户输入检索相关长久记忆。
     *
     * 采用简单关键词覆盖排序：命中关键词越多的记忆越相关。
     *
     * @param query 当前用户输入
     * @returns 按相关度排序的记忆条目
     * @author xiangwei
     */
    func relevantLongTermMemories(for query: String) -> [MemoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let keywords = extractKeywords(from: trimmed)
        guard !keywords.isEmpty else { return [] }

        let scored: [(item: MemoryItem, score: Int)] = longTermItems
            .filter { !$0.content.isEmpty }
            .map { item in
                let score = keywords.reduce(0) { count, keyword in
                    item.content.localizedStandardContains(keyword) ? count + 1 : count
                }
                return (item: item, score: score)
            }

        return scored
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                // 相关度优先，同相关度按有效重要度排序
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.item.effectiveImportance() > rhs.item.effectiveImportance()
            }
            .map { $0.item }
    }

    /**
     * 标记某条记忆被引用，提升其重要度。
     *
     * @param item 被引用的记忆条目
     * @author xiangwei
     */
    func recordAccess(_ item: MemoryItem) {
        item.accessCount += 1
        item.lastAccessedAt = Date()
        updateRecord(item)
    }

    // MARK: - 通用条目维护

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
            if soulCoreItem?.id == item.id { soulCoreItem = nil }
            soulRuleItems.removeAll { $0.id == item.id }
        case .userProfile:
            profileItems.removeAll { $0.id == item.id }
        case .longTerm:
            longTermItems.removeAll { $0.id == item.id }
        }
    }

    /**
     * 合并指定类别中的冗余记忆。
     *
     * 内容高度重叠的条目合并为最新/最完整的那一条。
     *
     * @param category 要合并的记忆类别
     * @author xiangwei
     */
    func consolidate(category: MemoryCategory) {
        switch category {
        case .soul:
            consolidateSoulRules()
        case .userProfile:
            profileItems = consolidate(items: profileItems)
        case .longTerm:
            longTermItems = consolidate(items: longTermItems)
        }
    }

    // MARK: - 注入文本构建

    /**
     * 构建灵魂设定注入文本。
     *
     * 手写核心优先，自动规则作为补充，分别裁剪避免撑爆上下文。
     *
     * @returns 灵魂设定文本，未设置时返回 nil
     * @author xiangwei
     */
    func soulPrompt() -> String? {
        var parts: [String] = []

        if let core = soulCoreItem, !core.content.isEmpty {
            let content = core.content.count > Self.soulCoreLimit
                ? String(core.content.prefix(Self.soulCoreLimit))
                : core.content
            parts.append(content)
        }

        let activeRules = soulRuleItems
            .filter { !$0.content.isEmpty }
            .prefix(10)
        if !activeRules.isEmpty {
            var ruleLines: [String] = []
            var totalLength = 0
            for item in activeRules {
                let line = "- \(item.content)"
                totalLength += line.count
                if totalLength > Self.soulRulesLimit { break }
                ruleLines.append(line)
            }
            if !ruleLines.isEmpty {
                let rulesText = ruleLines.joined(separator: "\n")
                parts.append("## 对话中提炼的行为规则\n\(rulesText)")
            }
        }

        guard !parts.isEmpty else { return nil }
        return "【灵魂设定】\n" + parts.joined(separator: "\n\n")
    }

    /**
     * 构建用户画像注入文本。
     *
     * 按最近更新时间取前若干条，并裁剪单条与总字符数上限。
     *
     * @returns 用户画像文本，无条目时返回 nil
     * @author xiangwei
     */
    func profilePrompt() -> String? {
        let items = profileItems
            .filter { !$0.content.isEmpty }
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
     * 优先取与当前话题相关的记忆，再补充高重要度记忆，控制上下文开销。
     *
     * @param currentQuery 当前用户输入，用于检索相关记忆
     * @returns 长久记忆文本，无条目时返回 nil
     * @author xiangwei
     */
    func longTermPrompt(for currentQuery: String? = nil) -> String? {
        var selected: [MemoryItem] = []

        // 1. 先取与当前输入相关的记忆
        if let query = currentQuery, !query.isEmpty {
            let relevant = relevantLongTermMemories(for: query).prefix(6)
            selected.append(contentsOf: relevant)
        }

        // 2. 再按有效重要度补充，直到达到条数上限
        if selected.count < Self.longTermCountLimit {
            let remaining = longTermItems
                .filter { item in
                    !selected.contains { $0.id == item.id } && !item.content.isEmpty
                }
                .sorted { $0.effectiveImportance() > $1.effectiveImportance() }
            selected.append(contentsOf: remaining.prefix(Self.longTermCountLimit - selected.count))
        }

        guard !selected.isEmpty else { return nil }

        var lines: [String] = []
        var totalLength = 0
        for item in selected {
            let content = item.content.count > Self.longTermItemLimit
                ? String(item.content.prefix(Self.longTermItemLimit))
                : item.content
            let line = "- \(content)"
            totalLength += line.count
            if totalLength > Self.longTermTotalLimit { break }
            lines.append(line)
            recordAccess(item)
        }
        guard !lines.isEmpty else { return nil }
        return "【长久记忆】\n" + lines.joined(separator: "\n")
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
        do {
            return try db.fetch(sql, args: [userId.uuidString, category.rawValue])
        } catch {
            // 记录读取失败原因（如迁移未完成导致的缺列）
            let errorMessage = error.localizedDescription
            Task {
                await AppLogger.shared.log(
                    .error,
                    category: "memory",
                    message: "记忆读取失败",
                    metadata: [
                        "user_id": userId.uuidString,
                        "category": category.rawValue,
                        "error": errorMessage
                    ]
                )
            }
            return []
        }
    }

    /**
     * 新增一条记忆条目并同步内存列表。
     *
     * @param category 记忆类别
     * @param content 记忆内容
     * @param importance 重要度
     * @param source 记忆来源
     * @param confidence 置信度
     * @author xiangwei
     */
    private func addItem(
        category: MemoryCategory,
        content: String,
        importance: Double,
        source: MemorySource,
        confidence: Double
    ) {
        guard let currentUserId else { return }

        let item = MemoryItem(
            ownerId: currentUserId,
            category: category,
            content: content,
            importance: importance,
            source: source,
            confidence: confidence
        )
        insertRecord(item)

        switch category {
        case .soul:
            if source == .manual {
                soulCoreItem = item
            } else {
                soulRuleItems.insert(item, at: 0)
            }
        case .userProfile:
            profileItems.insert(item, at: 0)
        case .longTerm:
            longTermItems.append(item)
            longTermItems.sort { $0.effectiveImportance() > $1.effectiveImportance() }
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
                id, owner_id, category, content, importance, source,
                confidence, access_count, last_accessed_at, created_at, updated_at
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        do {
            try db.run(
                sql,
                args: [
                    record.id,
                    record.ownerId,
                    record.category,
                    record.content,
                    record.importance,
                    record.source,
                    record.confidence,
                    record.accessCount,
                    record.lastAccessedAt,
                    record.createdAt,
                    record.updatedAt
                ]
            )
        } catch {
            // 记录写入失败原因（如迁移未完成导致的缺列）
            let errorMessage = error.localizedDescription
            Task {
                await AppLogger.shared.log(
                    .error,
                    category: "memory",
                    message: "记忆写入失败",
                    metadata: [
                        "category": item.category.rawValue,
                        "content_preview": String(item.content.prefix(50)),
                        "error": errorMessage
                    ]
                )
            }
        }
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
            SET content = ?, importance = ?, source = ?, confidence = ?,
                access_count = ?, last_accessed_at = ?, updated_at = ?
            WHERE id = ?
            """
        try? db.run(
            sql,
            args: [
                record.content,
                record.importance,
                record.source,
                record.confidence,
                record.accessCount,
                record.lastAccessedAt,
                record.updatedAt,
                record.id
            ]
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
     * 在列表中查找内容相似的条目。
     *
     * 采用简单启发式：完全相同、互相包含或共享较长公共子串视为相似。
     *
     * @param items 待查找列表
     * @param content 目标内容
     * @returns 最相似的条目，无则返回 nil
     * @author xiangwei
     */
    private func findSimilarItem(in items: [MemoryItem], content: String) -> MemoryItem? {
        let normalized = content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        return items.first { item in
            let existing = item.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if existing == normalized { return true }
            if existing.contains(normalized) || normalized.contains(existing) { return true }
            return longestCommonSubstringLength(existing, normalized) >= Self.similarityOverlapThreshold
        }
    }

    /**
     * 判断新内容是否已在指定内容列表中存在。
     *
     * @param content 新内容
     * @param contents 已有内容列表
     * @returns 是否冗余
     * @author xiangwei
     */
    private func isContentRedundant(_ content: String, among contents: [String]) -> Bool {
        let normalized = content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return contents.contains { existing in
            let e = existing.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return e == normalized || e.contains(normalized) || normalized.contains(e)
        }
    }

    /**
     * 合并列表中的冗余条目。
     *
     * 保留内容最长、更新最晚的版本，删除被合并的旧记录。
     *
     * @param items 原始条目列表
     * @returns 合并后的列表
     * @author xiangwei
     */
    private func consolidate(items: [MemoryItem]) -> [MemoryItem] {
        var result: [MemoryItem] = []
        var removed: [MemoryItem] = []

        for item in items {
            if let similar = result.first(where: { existing in
                let e = existing.content.lowercased()
                let c = item.content.lowercased()
                return e == c || e.contains(c) || c.contains(e)
            }) {
                // 保留内容更长或更新的一条
                if item.content.count > similar.content.count ||
                    (item.content.count == similar.content.count && item.updatedAt > similar.updatedAt) {
                    removed.append(similar)
                    result.removeAll { $0.id == similar.id }
                    result.append(item)
                } else {
                    removed.append(item)
                }
            } else {
                result.append(item)
            }
        }

        for item in removed {
            deleteRecord(item)
        }
        return result
    }

    /**
     * 合并冗余的灵魂规则。
     *
     * @author xiangwei
     */
    private func consolidateSoulRules() {
        soulRuleItems = consolidate(items: soulRuleItems)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /**
     * 淘汰有效重要度最低的长久记忆。
     *
     * @param targetCount 目标保留数量
     * @author xiangwei
     */
    private func pruneLongTermMemories(targetCount: Int) {
        let sorted = longTermItems.sorted { $0.effectiveImportance() > $1.effectiveImportance() }
        let keep = Array(sorted.prefix(targetCount))
        let remove = Array(sorted.suffix(from: targetCount))
        for item in remove {
            deleteRecord(item)
        }
        longTermItems = keep
    }

    /**
     * 从文本中提取关键词。
     *
     * 简单实现：按非中文/英文/数字字符分割，过滤停用词与过短词。
     *
     * @param text 输入文本
     * @returns 关键词集合
     * @author xiangwei
     */
    private func extractKeywords(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "的", "了", "是", "我", "你", "在", "和", "就", "都", "要", "有", "这", "那",
            "个", "为", "之", "与", "及", "或", "但", "而", "啊", "呢", "吗", "吧", "嗯",
            "the", "a", "an", "is", "are", "was", "were", "i", "you", "he", "she", "it",
            "we", "they", "this", "that", "these", "those", "and", "or", "but", "in", "on",
            "at", "to", "for", "of", "with", "about", "from"
        ]

        var keywords: [String] = []
        let pattern = try? NSRegularExpression(pattern: "[a-zA-Z0-9]+|[^\\s\\p{P}]+", options: [])
        let range = NSRange(text.startIndex..., in: text)
        pattern?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let range = match?.range, let swiftRange = Range(range, in: text) else { return }
            let word = String(text[swiftRange]).lowercased()
            if word.count >= 2, !stopWords.contains(word) {
                keywords.append(word)
            }
        }
        return keywords
    }

    /**
     * 计算两个字符串的最长公共子串长度。
     *
     * @param a 字符串 a
     * @param b 字符串 b
     * @returns 最长公共子串长度
     * @author xiangwei
     */
    private func longestCommonSubstringLength(_ a: String, _ b: String) -> Int {
        let charsA = Array(a)
        let charsB = Array(b)
        guard !charsA.isEmpty, !charsB.isEmpty else { return 0 }

        var previous = [Int](repeating: 0, count: charsB.count + 1)
        var current = [Int](repeating: 0, count: charsB.count + 1)
        var maxLength = 0

        for i in 1...charsA.count {
            for j in 1...charsB.count {
                if charsA[i - 1] == charsB[j - 1] {
                    current[j] = previous[j - 1] + 1
                    maxLength = max(maxLength, current[j])
                } else {
                    current[j] = 0
                }
            }
            previous = current
            current = [Int](repeating: 0, count: charsB.count + 1)
        }
        return maxLength
    }
}
