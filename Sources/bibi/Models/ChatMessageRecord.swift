import Foundation

@Observable
final class ChatMessageRecord: Identifiable {
    let id: UUID; var role: String; var content: String; var timestamp: Date
    var toolName: String?; var toolArgsJSON: String?; var toolStatus: String?
    var toolSummary: String?; var conversationId: UUID?
    init(role: String, content: String, timestamp: Date = Date()) {
        self.id = UUID(); self.role = role; self.content = content; self.timestamp = timestamp
    }
}
