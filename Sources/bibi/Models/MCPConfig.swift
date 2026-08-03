import Foundation

/**
 * MCP 服务配置。
 *
 * 定义智能体可连接的 MCP（Model Context Protocol）服务端点。
 *
 * @author xiangwei
 */
struct MCPConfig: Identifiable, Codable, Equatable {
    /// 配置唯一标识
    var id: UUID

    /// 服务名称
    var name: String

    /// 服务描述
    var description: String

    /// MCP 服务端点 URL
    var serverURL: String

    /// 认证令牌
    var token: String

    /// 是否启用
    var isEnabled: Bool

    /// 创建时间
    var createdAt: Date

    /**
     * 创建新 MCP 配置。
     *
     * @param name 服务名称
     * @param description 服务描述
     * @param serverURL 服务端点
     * @param token 认证令牌
     * @param isEnabled 是否启用
     * @author xiangwei
     */
    init(
        name: String = "",
        description: String = "",
        serverURL: String = "",
        token: String = "",
        isEnabled: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.serverURL = serverURL
        self.token = token
        self.isEnabled = isEnabled
        self.createdAt = Date()
    }
}
