import SwiftUI

/**
 * 智能体思考状态。
 *
 * @author xiangwei
 */
struct ThinkingIndicator: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.brandGold)
                        .frame(width: 6, height: 6)
                        .scaleEffect(phase ? 1 : 0.55)
                        .opacity(phase ? 1 : 0.28)
                        .animation(
                            .easeInOut(duration: 0.62)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.16),
                            value: phase
                        )
                }
            }

            Text("小笔正在整理")
                .font(.bibiCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .onAppear {
            phase = true
        }
    }
}
