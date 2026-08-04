import Foundation

/**
 * 应用设置项。
 *
 * 键值对形式存储持久化偏好。
 *
 * @author xiangwei
 */
@Observable
final class AppSetting: Identifiable {
    let id: UUID; var key: String; var value: String; var updatedAt: Date
    init(key: String, value: String) { self.id = UUID(); self.key = key; self.value = value; self.updatedAt = Date() }
}
/**
 * 持久化设置键枚举。
 *
 * 定义所有可持久化设置项的键值，避免字符串散落。
 *
 * @author xiangwei
 */
enum SettingKey: String {
    case defaultMode = "default_mode"; case autoReconnect = "auto_reconnect"; case theme = "theme"
    case lastPcDeviceId = "last_pc_device_id"; case llmModel = "llm_model"
    case thinkingEnabled = "thinking_enabled"; case reasoningEffort = "reasoning_effort"
    case debugEnabled = "debug_enabled"; case customSystemPrompt = "custom_system_prompt"
    case conversationWindowSize = "conversation_window_size"
    case proactiveEnabled = "proactive_enabled"; case proactiveIntervalMinutes = "proactive_interval_minutes"
    case lastProactiveAt = "last_proactive_at"
}
