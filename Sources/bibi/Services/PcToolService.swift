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
     * @author xiangwei
     */
    init(connection: ConnectionManager) {
        self.connection = connection
    }

    /**
     * 从 PC 端动态获取可用工具列表
     * @author xiangwei
     */
    func loadTools() async throws {
        let request = try connection.authenticatedRequest(path: "api/v1/tools")
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        try validate(response: urlResponse, data: data, operation: "加载工具列表")
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
     * @param traceId 调用链标识
     * @returns 工具执行结果
     * @author xiangwei
     */
    func execute(
        toolName: String,
        args: [String: Any],
        traceId: String? = nil
    ) async throws -> PcToolResult {
        var request = try connection.authenticatedRequest(
            path: "api/v1/tools/\(toolName)",
            method: "POST"
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: args)
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data, operation: "执行工具 \(toolName)")
            return try JSONDecoder().decode(PcToolResult.self, from: data)
        } catch {
            await AppLogger.shared.log(
                .error,
                category: "pc-tool",
                message: "电脑工具请求失败: \(error.localizedDescription)",
                traceId: traceId,
                metadata: ["tool_name": toolName]
            )
            throw error
        }
    }

    /**
     * 健康检查
     * @author xiangwei
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
     * @author xiangwei
     */
    func reset() {
        availableTools = []
    }

    /**
     * 校验电脑服务 HTTP 响应。
     *
     * @param response HTTP 响应
     * @param data 响应数据
     * @param operation 操作名称
     * @throws 响应状态异常
     * @author xiangwei
     */
    private func validate(response: URLResponse, data: Data, operation: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PcError.toolFailed("\(operation)未返回有效响应")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseError = try? JSONDecoder().decode(PcErrorResponse.self, from: data)
            let message = responseError?.error?.message ?? "HTTP \(httpResponse.statusCode)"
            throw PcError.toolFailed("\(operation)失败: \(message)")
        }
    }
}

/**
 * 电脑服务通用错误响应。
 * @author xiangwei
 */
private struct PcErrorResponse: Decodable {
    /// 错误详情。
    let error: PcToolError?
}
