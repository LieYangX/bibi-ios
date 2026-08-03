import SwiftUI

// MARK: - 品牌色

extension Color {
    /// 品牌暖金，用于标识与少量强调，不承担大面积内容背景。
    static let brandGold = Color(hex: "E9A91B")

    /// 品牌暖金浅色层。
    static let brandGoldLight = Color(hex: "E9A91B").opacity(0.14)

    /// 品牌暖金深色层。
    static let brandGoldDark = Color(hex: "B87400")

    /// 主要交互色，跟随系统明暗模式。
    static var accentBlue: Color {
        Color(uiColor: .systemBlue)
    }
}

// MARK: - 界面层级色

extension Color {
    /// 导航层背景。
    static var navigationBackground: Color {
        Color(uiColor: .systemBackground)
    }

    /// 内容层背景。
    static var contentBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    /// 内容卡片背景。
    static var contentCardBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    /// 细分隔线。
    static var hairline: Color {
        Color(uiColor: .separator).opacity(0.45)
    }
}

// MARK: - 消息色

extension Color {
    /// 用户消息卡片背景（暖灰，与助手冷灰区分）。
    static var userBubbleBackground: Color {
        Color(uiColor: .systemGray5).mix(with: .brandGold, by: 0.04)
    }

    /// 用户消息气泡文字。
    static var userBubbleText: Color {
        Color(uiColor: .label)
    }

    /// 助手消息气泡背景。
    static var assistantBubbleBackground: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    /// 工具调用卡片背景。
    static var toolCardBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    /// 工具结果卡片背景。
    static var toolResultBackground: Color {
        Color(uiColor: .tertiarySystemGroupedBackground)
    }
}

// MARK: - 状态色

extension Color {
    static var successGreen: Color { Color(uiColor: .systemGreen) }
    static var errorRed: Color { Color(uiColor: .systemRed) }
    static var warningYellow: Color { Color(uiColor: .systemOrange) }
    static var linkColor: Color { Color(uiColor: .link) }
    static let incomeGreen = Color(uiColor: .systemGreen)
    static let expenseRed = Color(uiColor: .systemRed)
}
