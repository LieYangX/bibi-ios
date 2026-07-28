import Foundation

@Observable
final class AppSetting: Identifiable {
    let id: UUID; var key: String; var value: String; var updatedAt: Date
    init(key: String, value: String) { self.id = UUID(); self.key = key; self.value = value; self.updatedAt = Date() }
}
enum SettingKey: String {
    case defaultMode = "default_mode"; case autoReconnect = "auto_reconnect"; case theme = "theme"
    case lastPcDeviceId = "last_pc_device_id"; case llmModel = "llm_model"
}
