import Foundation

/**
 * PC 端工具定义
 *
 * 对应 PC 端 AgentToolInfo 结构，可转为 DeepSeek function calling schema。
 *
 * @author xiangwei
 */
struct PcToolDef: Identifiable, Codable {
    /// 工具名
    let name: String

    /// 工具描述
    let description: String

    /// 工具参数定义
    let parameters: PcToolParameters

    /// 唯一标识
    var id: String { name }

    /**
     * 转为 DeepSeek function calling 的 JSON Schema
     *
     * @returns OpenAI 兼容的函数定义字典
     */
    func toFunctionSchema() -> [String: Any] {
        [
            "name": name,
            "description": description,
            "parameters": parameters.toJSONSchema()
        ]
    }
}

/**
 * PC 端工具参数定义
 *
 * @author xiangwei
 */
struct PcToolParameters: Codable {
    /// JSON Schema 格式的参数定义
    let schema: [String: AnyCodable]

    /**
     * 提取为普通字典
     *
     * @returns 去除 AnyCodable 包装后的 JSON Schema 字典
     */
    func toJSONSchema() -> [String: Any] {
        schema.mapValues { $0.value }
    }
}

/**
 * PC 端工具执行结果
 *
 * @author xiangwei
 */
struct PcToolResult: Codable {
    /// 是否成功
    let success: Bool

    /// 返回数据
    let data: AnyCodable?

    /// 错误信息
    let error: PcToolError?
}

/**
 * PC 端工具错误
 *
 * @author xiangwei
 */
struct PcToolError: Codable {
    /// 错误码
    let code: String

    /// 错误信息
    let message: String
}

/**
 * 工具列表响应
 *
 * @author xiangwei
 */
struct ToolListResponse: Decodable {
    /// 是否成功
    let success: Bool

    /// 工具列表
    let data: [PcToolDef]?

    /// 错误信息
    let error: PcToolError?
}

/**
 * 用户列表响应
 *
 * @author xiangwei
 */
struct UsersResponse: Decodable {
    /// 是否成功
    let success: Bool

    /// 用户列表
    let data: [RemoteUser]?

    /// 错误信息
    let error: PcToolError?
}

/**
 * PC 工具服务错误
 *
 * @author xiangwei
 */
enum PcError: Error, LocalizedError {
    /// 未连接到 PC
    case notConnected

    /// 未认证
    case notAuthenticated

    /// 工具执行失败
    case toolFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "未连接到 PC"
        case .notAuthenticated:
            return "PC 认证失效，请重新配对"
        case .toolFailed(let message):
            return "工具执行失败: \(message)"
        }
    }
}
