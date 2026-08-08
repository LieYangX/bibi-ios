import SwiftUI

/**
 * 对话输入工具栏。
 *
 * 输入工具栏属于导航控制层，使用单层 Liquid Glass 承载文本、语音与发送动作。
 * 支持语音模式切换：文本模式下显示输入框，语音模式下显示按住说话的长条按钮。
 *
 * @author xiangwei
 */
struct InputBar: View {
    @Binding var text: String
    @Binding var isVoiceMode: Bool
    let isProcessing: Bool
    let isRecording: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onVoicePressBegan: () -> Void
    let onVoiceDragChanged: (CGSize) -> Void
    let onVoicePressEnded: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                modeToggleButton

                if isVoiceMode {
                    voiceRecordButton
                } else {
                    textField
                }

                if !isVoiceMode {
                    sendButton
                }
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
        .onChange(of: isVoiceMode) { _, voiceMode in
            // 切换到语音模式时收起键盘
            if voiceMode {
                isFocused = false
            }
        }
    }

    /// 文本/语音模式切换按钮。
    private var modeToggleButton: some View {
        Button {
            isVoiceMode.toggle()
        } label: {
            Label(
                isVoiceMode ? "键盘输入" : "语音输入",
                systemImage: isVoiceMode ? "keyboard" : "waveform"
            )
            .labelStyle(.iconOnly)
            .font(.bibiButton)
            .foregroundStyle(.secondary)
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .contentTransition(.symbolEffect(.replace))
    }

    /// 文本输入框。
    private var textField: some View {
        TextField("向星枢提问", text: $text, axis: .vertical)
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
    }

    /// 按住说话按钮，视觉风格与文本输入框保持一致。
    private var voiceRecordButton: some View {
        Button(action: {}) {
            HStack(spacing: 6) {
                Image(systemName: isRecording ? "waveform" : "mic.fill")
                    .font(.bibiBody)
                Text(isRecording ? "聆听中… 松开结束" : "按住说话")
                    .font(.bibiBody)
            }
            .foregroundStyle(isRecording ? .primary : .secondary)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .scaleEffect(isRecording ? 1.04 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isRecording)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if !isRecording {
                        onVoicePressBegan()
                    }
                    onVoiceDragChanged(value.translation)
                }
                .onEnded { _ in
                    onVoicePressEnded()
                }
        )
    }

    /// 发送/停止按钮。
    private var sendButton: some View {
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
