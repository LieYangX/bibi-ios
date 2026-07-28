import Foundation

/**
 * PC 工具服务
 *
 * 通过配对认证后的 HTTP 请求调用 PC 端记账工具。
 *
 * @author xiangwei
 */
@MainActor
@Observable
final class PcToolService {
    /// 当前连接管理器（注入）
    private let connection: ConnectionManager

    /// 动态获取的工具列表
    private(set) var availableTools: [PcToolDef] = []

    /**
     * 初始化
     *
     * @param connection 连接管理器
     */
    init(connection: ConnectionManager) {
        self.connection = connection
    }

    /**
     * 从 PC 端动态获取可用工具列表
     */
    func loadTools() async throws {
        let request = try connection.authenticatedRequest(path: "api/v1/tools")
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ToolListResponse.self, from: data)

        guard response.success, let tools = response.data else {
            throw PcError.toolFailed(response.error?.message ?? "加载工具列表失败")
        }

        availableTools = tools
    }

    /**
     * 调用 PC 端的记账工具
     *
     * @param toolName 工具名
     * @param args 参数字典
     * @returns 工具执行结果
     */
    func execute(toolName: String, args: [String: Any]) async throws -> PcToolResult {
        var request = try connection.authenticatedRequest(
            path: "api/v1/tools/\(toolName)",
            method: "POST"
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: args)
        request.timeoutInterval = 30

        let (data, _) = try await URLSession.shared.data(for: request)
        let result = try JSONDecoder().decode(PcToolResult.self, from: data)

        return result
    }

    /**
     * 健康检查
     */
    @discardableResult
    func ping() async -> Bool {
        guard let request = try? connection.authenticatedRequest(path: "api/v1/ping") else {
            return false
        }

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    /**
     * 断线时清理
     */
    func reset() {
        availableTools = []
    }
}
