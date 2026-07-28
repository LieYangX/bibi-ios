import Foundation

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
