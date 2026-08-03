import Foundation
import GRDB

/**
 * 智能体请求日志持久化服务。
 *
 * 保存每次 LLM API 请求的完整入参出参到 SQLite，供诊断页面查看。
 *
 * @author xiangwei
 */
final class AgentLogger {
    /// 单条日志最大体积。
    private static let maximumEntrySize = 128 * 1_024

    /// 日志最大保存数量。
    private static let maximumEntryCount = 500

    /// 全局共享实例。
    nonisolated(unsafe) static let shared = AgentLogger()

    private let db = DatabaseManager.shared

    private init() {}

    /**
     * 写入一条智能体请求日志。
     *
     * @param entry 日志记录
     */
    func save(_ entry: AgentLogEntry) {
        let record = AgentLogRecord.from(entry)
        do {
            try db.run("""
                INSERT INTO agent_log(id,trace_id,timestamp,model,round_index,status,
                    request_json,response_json,duration_ms,error_message)
                VALUES(?,?,?,?,?,?,?,?,?,?)
                """,
                args: [
                    record.id, record.traceId, record.timestamp,
                    record.model, record.roundIndex, record.status,
                    truncate(record.requestJSON, to: Self.maximumEntrySize),
                    truncate(record.responseJSON, to: Self.maximumEntrySize),
                    record.durationMS, record.errorMessage
                ]
            )
            purgeOldEntries()
        } catch {
            // 日志写入失败时静默忽略，避免干扰主流程。
        }
    }

    /**
     * 读取最近的智能体请求日志。
     *
     * @param limit 最大返回数量
     * @returns 按时间倒序排列的日志列表
     */
    func loadEntries(limit: Int = 200) -> [AgentLogEntry] {
        do {
            let records: [AgentLogRecord] = try db.fetch(
                "SELECT * FROM agent_log ORDER BY timestamp DESC LIMIT ?",
                args: [limit]
            )
            return records.map { $0.toEntry() }
        } catch {
            return []
        }
    }

    /**
     * 读取指定调用链的全部日志。
     *
     * @param traceId 调用链标识
     * @returns 按轮次正序排列的日志列表
     */
    func loadEntries(for traceId: String) -> [AgentLogEntry] {
        do {
            let records: [AgentLogRecord] = try db.fetch(
                "SELECT * FROM agent_log WHERE trace_id = ? ORDER BY round_index",
                args: [traceId]
            )
            return records.map { $0.toEntry() }
        } catch {
            return []
        }
    }

    /**
     * 清空全部智能体请求日志。
     */
    func clear() {
        try? db.run("DELETE FROM agent_log")
    }

    /**
     * 清理超出数量限制的旧日志。
     */
    private func purgeOldEntries() {
        try? db.run("""
            DELETE FROM agent_log WHERE id NOT IN (
                SELECT id FROM agent_log ORDER BY timestamp DESC LIMIT ?
            )
            """,
            args: [Self.maximumEntryCount]
        )
    }

    /**
     * 截断过长字符串。
     *
     * @param text 原始文本
     * @param maximumLength 最大字节数
     * @returns 截断后的文本
     */
    private func truncate(_ text: String, to maximumLength: Int) -> String {
        guard text.utf8.count > maximumLength else { return text }
        return String(text.prefix(maximumLength)) + "...[已截断]"
    }
}
