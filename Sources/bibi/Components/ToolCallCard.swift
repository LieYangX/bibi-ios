import SwiftUI

/**
 * 工具调用卡片
 *
 * 显示工具执行的实时状态：进行中、成功、失败。
 *
 * @author xiangwei
 */
struct ToolCallCard: View {
    let name: String
    let status: ToolCallStatus
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .symbolEffect(.pulse, options: status == .inProgress ? .repeating : .nonRepeating)

                Text(name)
                    .font(.bibiCaptionSemibold)
                    .foregroundColor(.primary)

                Spacer()

                if status == .inProgress {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            // 状态文本
            Text(statusText)
                .font(.bibiCaption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusBorderColor, lineWidth: 1)
        )
        .onTapGesture {
            withAnimation(.snappy) {
                isExpanded.toggle()
            }
        }
    }

    private var statusIcon: String {
        switch status {
        case .inProgress: return "circle.dotted"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .inProgress: return .accentCyan
        case .succeeded: return .successGreen
        case .failed: return .errorRed
        }
    }

    private var statusText: String {
        switch status {
        case .inProgress: return "正在调用 \(name)..."
        case .succeeded: return "\(name) 执行成功"
        case .failed: return "\(name) 执行失败"
        }
    }

    private var statusBorderColor: Color {
        switch status {
        case .inProgress: return .accentCyan.opacity(0.3)
        case .succeeded: return .successGreen.opacity(0.3)
        case .failed: return .errorRed.opacity(0.3)
        }
    }
}
