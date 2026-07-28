import SwiftUI

/// 主题偏好枚举
enum ThemePreference: String, CaseIterable, Codable {
    /// 跟随系统设置
    case system = "跟随系统"
    /// 强制浅色
    case light = "浅色"
    /// 强制深色
    case dark = "深色"

    /// 转换为 SwiftUI ColorScheme（nil 表示跟随系统）
    var toColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 主题管理器
///
/// 使用 @Observable 实现响应式主题切换。
/// 支持系统、浅色、深色三种模式。
@Observable
final class ThemeManager {
    /// 当前主题偏好（持久化到 UserDefaults）
    var preferredScheme: ThemePreference {
        didSet {
            UserDefaults.standard.set(preferredScheme.rawValue, forKey: "theme_preference")
        }
    }

    init() {
        // 从 UserDefaults 恢复上次的偏好
        if let saved = UserDefaults.standard.string(forKey: "theme_preference"),
           let preference = ThemePreference(rawValue: saved) {
            self.preferredScheme = preference
        } else {
            self.preferredScheme = .system
        }
    }
}
