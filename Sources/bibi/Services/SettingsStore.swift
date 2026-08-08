import Foundation

/**
 * 设置存储服务。
 *
 * 基于 UserDefaults 的键值存储，配合 SettingKey 枚举提供类型安全的访问。
 * 需要 UI 即时响应的项使用存储属性（@Observable 可追踪），变更时同步写回 UserDefaults。
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
        didSet { self.set(.customSystemPrompt, value: customSystemPrompt) }
    }

    /// 会话滑动窗口条数（默认 20 条消息，超出部分自动提炼记忆）。
    var conversationWindowSize: Int {
        didSet { self.set(.conversationWindowSize, value: String(conversationWindowSize)) }
    }

    /// 是否启用主动消息（定时让 AI 主动发起对话）。
    var proactiveEnabled: Bool {
        didSet { self.set(.proactiveEnabled, value: proactiveEnabled ? "true" : "false") }
    }

    /// 主动消息触发间隔（分钟，默认 120 分钟）。
    var proactiveIntervalMinutes: Int {
        didSet { self.set(.proactiveIntervalMinutes, value: String(proactiveIntervalMinutes)) }
    }

    /// LLM 模型标识（默认 deepseek-v4-flash）。
    var llmModel: String {
        didSet { self.set(.llmModel, value: llmModel) }
    }

    /// 思考强度（low / high / max，默认 high）。
    var reasoningEffort: String {
        didSet { self.set(.reasoningEffort, value: reasoningEffort) }
    }

    /// 上次主动消息触发时间（Unix 时间戳）。
    var lastProactiveAt: Date? {
        get {
            guard let value = self.get(.lastProactiveAt),
                  let timestamp = TimeInterval(value) else { return nil }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            if let newValue {
                self.set(.lastProactiveAt, value: String(newValue.timeIntervalSince1970))
            } else {
                self.set(.lastProactiveAt, value: "")
            }
        }
    }

    /// 是否启用语音识别后自动矫正。
    var speechCorrectionEnabled: Bool {
        didSet { self.set(.speechCorrectionEnabled, value: speechCorrectionEnabled ? "true" : "false") }
    }

    /**
     * 初始化设置存储。
     *
     * 从 UserDefaults 读取存储属性初始值（init 中赋值不会触发 didSet）。
     * @author xiangwei
     */
    init() {
        customSystemPrompt = defaults.string(forKey: SettingKey.customSystemPrompt.rawValue) ?? ""
        conversationWindowSize = Int(defaults.string(forKey: SettingKey.conversationWindowSize.rawValue) ?? "") ?? 20
        proactiveEnabled = defaults.string(forKey: SettingKey.proactiveEnabled.rawValue) == "true"
        proactiveIntervalMinutes = Int(defaults.string(forKey: SettingKey.proactiveIntervalMinutes.rawValue) ?? "") ?? 120
        llmModel = defaults.string(forKey: SettingKey.llmModel.rawValue) ?? DeepSeekModel.flash.rawValue
        reasoningEffort = defaults.string(forKey: SettingKey.reasoningEffort.rawValue) ?? "high"
        speechCorrectionEnabled = defaults.string(forKey: SettingKey.speechCorrectionEnabled.rawValue) != "false"
    }
}
