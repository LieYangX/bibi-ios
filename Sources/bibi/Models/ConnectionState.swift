import Foundation

/**
 * PC 连接状态
 *
 * @author xiangwei
 */
enum ConnectionState {
    /// 正在搜索 PC
    case searching

    /// 已发现 PC 但未连接
    case found

    /// 已连接并认证通过
    case connected

    /// 已断开连接
    case disconnected
}

/**
 * PC 设备信息
 *
 * @author xiangwei
 */
struct PCDevice: Identifiable, Hashable {
    /// Bonjour 服务名
    let id: String

    /// 设备显示名
    let name: String

    /// IP 地址或主机名
    let hostName: String

    /// 从 Bonjour 解析出的直连 IP 地址（优先于 hostName 使用）
    let ipAddress: String?

    /// HTTP API 端口
    let port: Int

    /// Bonjour 广播端口
    let bonjourPort: Int

    /// PC 端当前用户名
    let currentUser: String?

    /// 协议版本
    let version: String?
}
