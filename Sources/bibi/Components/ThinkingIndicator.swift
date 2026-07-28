import SwiftUI

/**
 * 思考动画指示器
 *
 * 三点脉动，品牌色，带"小笔正在思考..."文字。
 *
 * @author xiangwei
 */
struct ThinkingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.brandGold)
                        .frame(width: 8, height: 8)
                        .opacity(pulseOpacity(for: index))
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: phase
                        )
                }
            }

            Text("小笔正在思考...")
                .font(.bibiCaption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            phase = 1.0
        }
    }

    private func pulseOpacity(for index: Int) -> Double {
        let base: Double = 0.3
        let peak: Double = 1.0
        let offset = Double(index) * 0.33
        let value = sin((phase + offset) * .pi)
        return base + (peak - base) * value
    }
}
