import Foundation

/**
 * 设置存储服务。
 *
 * 基于 UserDefaults 的键值存储，配合 SettingKey 枚举提供类型安全的访问。
 *
 * @author xiangwei
 */
@Observable
final class SettingsStore {
    private let defaults = UserDefaults.standard

    func get(_ key: SettingKey) -> String? { defaults.string(forKey: key.rawValue) }
    func set(_ key: SettingKey, value: String) { defaults.set(value, forKey: key.rawValue) }

    /// 是否启用调试模式。
    var isDebugEnabled: Bool {
        self.get(.debugEnabled) == "true"
    }

    /// 自定义系统提示词。
    var customSystemPrompt: String {
        get { self.get(.customSystemPrompt) ?? "" }
        set { self.set(.customSystemPrompt, value: newValue) }
    }
}
