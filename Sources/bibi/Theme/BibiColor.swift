import SwiftUI

// MARK: - 品牌色 (iOS 短信风格)

extension Color {
    /// 品牌蓝色 - iOS 短信蓝 #007AFF
    static let brandBlue = Color(hex: "007AFF")

    /// 品牌蓝色（半透明）
    static let brandBlueLight = Color(hex: "007AFF").opacity(0.15)

    /// 品牌蓝色（深色变体）
    static let brandBlueDark = Color(hex: "0055CC")
}

// MARK: - 语义色彩（自适应深色/亮色模式）

extension Color {
    /// 导航层背景
    static var navigationBackground: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
                : UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
        })
    }

    /// 内容层背景
    static var contentBackground: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
                : UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
        })
    }

    /// 内容层卡片背景
    static var contentCardBackground: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
                : UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
        })
    }
}

// MARK: - 消息气泡色彩（iOS 短信风格）

extension Color {
    /// 用户消息气泡背景 - iOS 蓝色
    static let userBubbleBackground = Color.brandBlue

    /// 用户消息气泡文字 - 白色
    static let userBubbleText = Color.white

    /// 助手消息气泡背景 - 浅灰（亮色）/ 深灰（暗色）
    static var assistantBubbleBackground: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
                : UIColor(red: 0.91, green: 0.91, blue: 0.92, alpha: 1)
        })
    }

    /// 工具调用卡片背景
    static var toolCardBackground: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
                : UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1)
        })
    }

    /// 工具结果卡片背景
    static var toolResultBackground: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
                : UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        })
    }
}

// MARK: - 交互状态色彩

extension Color {
    /// 成功/正向 - 绿色
    static let successGreen = Color(red: 0.20, green: 0.80, blue: 0.29)

    /// 错误/负向 - 红色
    static let errorRed = Color(red: 1.00, green: 0.27, blue: 0.23)

    /// 交互强调 - 蓝色
    static let accentBlue = Color(hex: "007AFF")

    /// 警告 - 黄色
    static let warningYellow = Color(red: 1.00, green: 0.80, blue: 0.30)

    /// 链接文字色 - 蓝色
    static let linkColor = Color(hex: "007AFF")
}
