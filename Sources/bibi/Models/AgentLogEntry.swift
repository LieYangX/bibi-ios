import Foundation

/**
 * 智能体请求日志状态。
 *
 * @author xiangwei
 */
enum AgentLogStatus: String, Codable {
    /// 请求成功
    case success

    /// 请求失败
    case error
}

/**
 * 智能体 API 请求日志记录。
 *
 * 保存每次 LLM 请求的完整入参出参，方便调试智能体行为。
 *
 * @author xiangwei
 */
struct AgentLogEntry: Codable, Identifiable {
    /// 日志唯一标识
    let id: UUID

    /// 调用链标识
    let traceId: String

    /// 记录时间
    let timestamp: Date

    /// 模型名称
    let model: String

    /// 多轮对话中的轮次（从 1 开始）
    let roundIndex: Int

    /// 请求状态
    let status: AgentLogStatus

    /// 请求体 JSON（含 messages、tools、stream 等）
    let requestJSON: String

    /// 完整响应 JSON
    let responseJSON: String

    /// 耗时（毫秒）
    let durationMS: Int

    /// 错误信息（仅 status == .error 时有值）
    let errorMessage: String?
}
