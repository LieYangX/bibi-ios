import SwiftUI

// MARK: - 系统形状

/**
 * 应用统一形状。
 *
 * @author xiangwei
 */
enum BibiShape {
    /// iOS 26 内容卡片形状，缺少外层圆角参照时仍保留最小圆角。
    static var contentCard: ConcentricRectangle {
        ConcentricRectangle(
            corners: .concentric(minimum: .fixed(16)),
            isUniform: true
        )
    }
}

// MARK: - 自适应色彩

extension Color {
    /// 应用画布背景。
    static var appBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    /// 表层卡片背景。
    static var appCardBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    /// 主要文字。
    static var primaryText: Color {
        Color(uiColor: .label)
    }

    /// 次要文字。
    static var secondaryText: Color {
        Color(uiColor: .secondaryLabel)
    }

    /// 三级文字。
    static var tertiaryText: Color {
        Color(uiColor: .tertiaryLabel)
    }

    /**
     * 根据十六进制字符串创建颜色。
     *
     * @param hex 十六进制颜色，支持 RRGGBB 或 RRGGBBAA
     */
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - 分类图标样式

struct CategoryIconModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 38, height: 38)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

extension View {
    /// 应用分类图标样式。
    func categoryIconStyle(color: Color) -> some View {
        modifier(CategoryIconModifier(color: color))
    }
}
