import SwiftUI

/**
 * 对话输入工具栏。
 *
 * 输入工具栏属于导航控制层，使用单层 Liquid Glass 承载文本、语音与发送动作。
 *
 * @author xiangwei
 */
struct InputBar: View {
    @Binding var text: String
    let isProcessing: Bool
    let isRecording: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onVoice: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Button(action: onVoice) {
                    Label(isRecording ? "停止录音" : "语音输入", systemImage: isRecording ? "stop.fill" : "waveform")
                        .labelStyle(.iconOnly)
                        .font(.bibiButton)
                        .foregroundStyle(isRecording ? .white : .secondary)
                        .frame(width: 36, height: 36)
                        .background(isRecording ? Color.brandGold : Color.clear, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
                .contentTransition(.symbolEffect(.replace))

                TextField("向小笔提问", text: $text, axis: .vertical)
                    .font(.bibiBody)
                    .lineLimit(1...5)
                    .frame(minHeight: 36, alignment: .center)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .disabled(isProcessing)
                    .onSubmit {
                        if canSend {
                            onSend()
                        }
                    }

                Button(action: isProcessing ? onStop : onSend) {
                    Label(actionLabel, systemImage: actionIcon)
                        .labelStyle(.iconOnly)
                        .font(.bibiCaptionBold)
                        .foregroundStyle(actionForeground)
                        .frame(width: 36, height: 36)
                        .background(actionBackground, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!isProcessing && !canSend)
                .contentTransition(.symbolEffect(.replace))
            }
            .padding(.leading, 8)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .rect(cornerRadius: 25))
            .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var actionLabel: String {
        isProcessing ? "停止生成" : "发送"
    }

    private var actionIcon: String {
        isProcessing ? "stop.fill" : "arrow.up"
    }

    private var actionForeground: Color {
        if isProcessing || canSend {
            return .white
        }
        return .secondary
    }

    private var actionBackground: Color {
        if isProcessing {
            return .secondary.opacity(0.45)
        }
        return canSend ? .brandGold : Color.secondary.opacity(0.12)
    }
}
