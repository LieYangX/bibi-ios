import SwiftUI

/**
 * 应用内容画布。
 *
 * 使用低饱和多色网格为玻璃导航提供采样层，同时保持对话与工具内容的可读性。
 *
 * @author xiangwei
 */
struct AnimatedBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5, 0.5], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: meshColors
        )
        .ignoresSafeArea()
    }

    private var meshColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(hex: "101113"), Color(hex: "171613"), Color(hex: "101416"),
                Color(hex: "131719"), Color(hex: "111214"), Color(hex: "181411"),
                Color(hex: "0C0D0F"), Color(hex: "101312"), Color(hex: "0D0E10")
            ]
        }
        return [
            Color(hex: "F7F7F9"), Color(hex: "FFF8E9"), Color(hex: "F2F8F7"),
            Color(hex: "F1F5FA"), Color(hex: "F7F7F8"), Color(hex: "FFF5EF"),
            Color(hex: "F5F5F7"), Color(hex: "F0F7F4"), Color(hex: "F6F4F8")
        ]
    }
}
