import SwiftUI

// MARK: - 字体尺寸常量

/// 应用统一字体规格
enum BibiFontSize {
    /// 大标题 - 28pt（用于页面主标题、空状态引导文字）
    static let largeTitle: CGFloat = 28

    /// 标题 - 22pt（用于卡片标题、Section 标题）
    static let title: CGFloat = 22

    /// 正文 - 16pt（用于消息内容、列表项文字）
    static let body: CGFloat = 16

    /// 说明文字 - 13pt（用于辅助说明、时间戳、标签）
    static let caption: CGFloat = 13
}

// MARK: - 字体辅助方法

extension Font {
    /// 大标题字体 - 28pt 粗体
    static let bibiLargeTitle = Font.system(size: BibiFontSize.largeTitle, weight: .bold)

    /// 标题字体 - 22pt 半粗体
    static let bibiTitle = Font.system(size: BibiFontSize.title, weight: .semibold)

    /// 正文字体 - 16pt 常规
    static let bibiBody = Font.system(size: BibiFontSize.body, weight: .regular)

    /// 说明文字字体 - 13pt 常规
    static let bibiCaption = Font.system(size: BibiFontSize.caption, weight: .regular)

    /// 说明文字字体 - 13pt 中粗
    static let bibiCaptionSemibold = Font.system(size: BibiFontSize.caption, weight: .semibold)

    /// 按钮文字字体 - 16pt 半粗体
    static let bibiButton = Font.system(size: BibiFontSize.body, weight: .semibold)

    /// 等宽数字字体 - 16pt（用于金额、数字展示）
    static let bibiMonospacedBody = Font.system(size: BibiFontSize.body, weight: .regular, design: .monospaced)

    /// 等宽数字字体 - 13pt（用于小号金额、数字展示）
    static let bibiMonospacedCaption = Font.system(size: BibiFontSize.caption, weight: .regular, design: .monospaced)
}

// MARK: - 自定义字体尺寸方法

extension View {
    /// 应用大标题字体样式
    func bibiLargeTitleStyle() -> some View {
        font(.bibiLargeTitle)
    }

    /// 应用标题字体样式
    func bibiTitleStyle() -> some View {
        font(.bibiTitle)
    }

    /// 应用正文字体样式
    func bibiBodyStyle() -> some View {
        font(.bibiBody)
    }

    /// 应用说明文字字体样式
    func bibiCaptionStyle() -> some View {
        font(.bibiCaption)
    }
}