import SwiftUI

// MARK: - 自适应色彩

extension Color {
    /// 深层画布背景（暗色：深蓝黑 / 亮色：暖白）
    static var appBackground: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.02, green: 0.04, blue: 0.10, alpha: 1)
                : UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
        })
    }

    /// 表层卡片背景（暗色：深蓝 / 亮色：浅灰白）
    static var appCardBackground: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.04, green: 0.08, blue: 0.18, alpha: 1)
                : UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1)
        })
    }

    // MARK: - 语义色彩（双模式通用）

    /// 收入/正向 - 绿色
    static let incomeGreen = Color(red: 0.20, green: 0.80, blue: 0.29)
    /// 支出/负向 - 红色
    static let expenseRed = Color(red: 1.00, green: 0.27, blue: 0.23)
    // accentCyan 和 warningYellow 移至 Theme/BibiColor.swift

    // MARK: - 自适应文字色

    /// 主要文字（暗色：白 / 亮色：黑）
    static var primaryText: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.white
                : UIColor.black
        })
    }

    /// 次要文字（暗色：白 55% / 亮色：黑 55%）
    static var secondaryText: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.55)
                : UIColor.black.withAlphaComponent(0.55)
        })
    }

    /// 三级文字（暗色：白 30% / 亮色：黑 30%）
    static var tertiaryText: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.30)
                : UIColor.black.withAlphaComponent(0.30)
        })
    }

    // MARK: - MeshGradient 背景色

    /// 暗色模式下的 MeshGradient 颜色
    static var darkMeshColors: [Color] {
        [
            Color(red: 0.03, green: 0.05, blue: 0.14),
            Color(red: 0.08, green: 0.12, blue: 0.26),
            Color(red: 0.02, green: 0.04, blue: 0.10),
            Color(red: 0.10, green: 0.16, blue: 0.30),
            Color(red: 0.06, green: 0.14, blue: 0.28),
            Color(red: 0.12, green: 0.18, blue: 0.34),
            Color(red: 0.02, green: 0.03, blue: 0.08),
            Color(red: 0.06, green: 0.10, blue: 0.20),
            Color(red: 0.03, green: 0.05, blue: 0.12),
        ]
    }

    /// 亮色模式下的 MeshGradient 颜色
    static var lightMeshColors: [Color] {
        [
            Color(red: 0.92, green: 0.94, blue: 0.98),
            Color(red: 0.88, green: 0.90, blue: 0.96),
            Color(red: 0.95, green: 0.96, blue: 0.99),
            Color(red: 0.85, green: 0.88, blue: 0.95),
            Color(red: 0.90, green: 0.92, blue: 0.98),
            Color(red: 0.82, green: 0.86, blue: 0.94),
            Color(red: 0.94, green: 0.95, blue: 0.98),
            Color(red: 0.86, green: 0.89, blue: 0.95),
            Color(red: 0.93, green: 0.94, blue: 0.97),
        ]
    }

    // MARK: - 十六进制颜色初始化

    /// 根据十六进制字符串创建颜色（格式：RRGGBB 或 RRGGBBAA）
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

// MARK: - 玻璃卡片样式修饰符

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

extension View {
    /// 应用玻璃卡片样式
    func glassCardStyle() -> some View {
        modifier(GlassCardModifier())
    }
}

// MARK: - 分类图标样式修饰符

struct CategoryIconModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(.system(size: 18))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(color.opacity(0.3))
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )
    }
}

extension View {
    /// 应用分类图标圆形背景样式
    func categoryIconStyle(color: Color) -> some View {
        modifier(CategoryIconModifier(color: color))
    }
}
