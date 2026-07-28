import SwiftUI

/**
 * PC 端用户
 *
 * 从 PC 端 GET /api/v1/users 获取的用户信息。
 *
 * @author xiangwei
 */
struct RemoteUser: Identifiable, Codable, Hashable {
    /// 用户 ID
    let id: String

    /// 用户名称
    let name: String

    /// 主题颜色 hex
    let color: String

    /// 名称首字母
    var initial: String {
        String(name.prefix(1))
    }

    /// UI 颜色
    var uiColor: Color {
        Color(hex: color.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
    }
}
