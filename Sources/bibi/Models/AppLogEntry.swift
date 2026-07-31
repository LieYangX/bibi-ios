import Foundation

/**
 * 应用日志等级。
 *
 * @author xiangwei
 */
enum AppLogLevel: String, Codable, CaseIterable {
    /// 调试信息。
    case debug

    /// 一般信息。
    case info

    /// 警告信息。
    case warning

    /// 错误信息。
    case error
}

/**
 * 应用结构化日志记录。
 *
 * @author xiangwei
 */
struct AppLogEntry: Codable, Identifiable {
    /// 日志唯一标识。
    let id: UUID

    /// 记录时间。
    let timestamp: Date

    /// 日志等级。
    let level: AppLogLevel

    /// 功能分类。
    let category: String

    /// 日志内容。
    let message: String

    /// 调用链标识。
    let traceId: String?

    /// 补充信息。
    let metadata: [String: String]
}
