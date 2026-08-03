import Foundation

/**
 * 本地用户。
 *
 * 使用 @Observable 实现响应式状态。本地用户可独立存在，也可与 PC 端用户关联。
 *
 * @author xiangwei
 */
@Observable
final class LocalUser: Identifiable {
    var id: UUID; var displayName: String; var avatarColor: String
    var createdAt: Date; var lastActiveAt: Date
    var pcUserId: String?; var pcDeviceId: String?
    init(displayName: String, avatarColor: String = "#F7BA1E") {
        self.id = UUID(); self.displayName = displayName; self.avatarColor = avatarColor
        self.createdAt = Date(); self.lastActiveAt = Date()
    }
}
