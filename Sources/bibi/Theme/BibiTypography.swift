import SwiftUI

// MARK: - 动态字体

extension Font {
    /// 空状态主标题。
    static let bibiLargeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)

    /// 页面与模块标题。
    static let bibiTitle = Font.system(.title2, design: .rounded, weight: .semibold)

    /// 正文。
    static let bibiBody = Font.system(.body, design: .default, weight: .regular)

    /// 助手消息正文。
    static let bibiAssistant = Font.system(.subheadline, design: .default, weight: .regular)

    /// 辅助说明。
    static let bibiCaption = Font.system(.footnote, design: .default, weight: .regular)

    /// 强调辅助说明。
    static let bibiCaptionSemibold = Font.system(.footnote, design: .default, weight: .semibold)

    /// 按钮文字。
    static let bibiButton = Font.system(.body, design: .rounded, weight: .semibold)

    /// 金额与数字正文。
    static let bibiMonospacedBody = Font.system(.body, design: .monospaced, weight: .medium)

    /// 小号金额与数字。
    static let bibiMonospacedCaption = Font.system(.footnote, design: .monospaced, weight: .medium)
}

// MARK: - 字体便捷修饰符

extension View {
    /// 应用空状态主标题样式。
    func bibiLargeTitleStyle() -> some View {
        font(.bibiLargeTitle)
    }

    /// 应用标题样式。
    func bibiTitleStyle() -> some View {
        font(.bibiTitle)
    }

    /// 应用正文样式。
    func bibiBodyStyle() -> some View {
        font(.bibiBody)
    }

    /// 应用辅助说明样式。
    func bibiCaptionStyle() -> some View {
        font(.bibiCaption)
    }
}
