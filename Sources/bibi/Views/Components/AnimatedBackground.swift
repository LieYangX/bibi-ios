import SwiftUI

/// 动态 MeshGradient 背景视图
///
/// 使用 iOS 18+ 的 MeshGradient 创建缓慢流动的渐变背景，
/// 根据当前色彩模式自动切换暗色/亮色调色板。
struct AnimatedBackground: View {
    @State private var startTime = Date()
    @Environment(\.colorScheme) private var colorScheme

    /// 根据当前色彩模式选择 MeshGradient 颜色
    private var meshColors: [Color] {
        colorScheme == .dark ? Color.darkMeshColors : Color.lightMeshColors
    }

    var body: some View {
        if #available(iOS 18, *) {
            TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(startTime)

                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5],
                        [0.5 + 0.12 * Float(sin(elapsed * 0.25 + 1.0)),
                         0.5 + 0.08 * Float(cos(elapsed * 0.35))],
                        [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1]
                    ],
                    colors: meshColors
                )
            }
            .ignoresSafeArea()
        } else {
            Color.appBackground.ignoresSafeArea()
        }
    }
}
