import Foundation

@Observable
final class Conversation: Identifiable {
    var id: UUID; var title: String; var createdAt: Date; var updatedAt: Date
    var messageCount: Int; var ownerId: UUID
    init(title: String = "新对话", ownerId: UUID) {
        self.id = UUID(); self.title = title; self.ownerId = ownerId
        self.createdAt = Date(); self.updatedAt = Date(); self.messageCount = 0
    }
}
