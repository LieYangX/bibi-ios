import SwiftUI

/**
 * 输入工具栏
 *
 * 文本输入框（自动增长 1-5 行）、语音按钮、发送/停止按钮。
 * 使用 .glassEffect()（导航层材质）。
 *
 * @author xiangwei
 */
struct InputBar: View {
    @Binding var text: String
    let isProcessing: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onVoice: () -> Void

    @State private var textHeight: CGFloat = 36

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // 语音按钮
            Button(action: onVoice) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.brandGold)
                    .frame(width: 36, height: 36)
            }
            .disabled(isProcessing)

            // 文本输入
            TextField("给小笔发消息...", text: $text, axis: .vertical)
                .font(.bibiBody)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .disabled(isProcessing)

            // 发送 / 停止
            if isProcessing {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.errorRed)
                        .clipShape(Circle())
                }
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(text.trimmingCharacters(in: .whitespaces).isEmpty ? .gray.opacity(0.3) : .brandGold)
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
