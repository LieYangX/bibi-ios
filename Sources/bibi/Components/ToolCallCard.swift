import SwiftUI

/**
 * 低强调工具调用状态行。
 *
 * @author xiangwei
 */
struct ToolCallCard: View {
    let name: String
    let status: ToolCallStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(statusColor)

            Text(statusText)
                .font(.caption2)
                .foregroundStyle(status == .failed ? Color.secondary : Color.secondary.opacity(0.72))
                .lineLimit(1)

            Spacer(minLength: 8)

            if status == .inProgress {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.secondary)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    private var statusIcon: String {
        if status == .inProgress, let localToolIcon = LocalToolService.iconName(for: name) {
            return localToolIcon
        }

        switch status {
        case .inProgress:
            return "gearshape"
        case .succeeded:
            return "checkmark"
        case .failed:
            return "exclamationmark.circle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .inProgress:
            return .secondary
        case .succeeded:
            return .secondary.opacity(0.72)
        case .failed:
            return .errorRed.opacity(0.85)
        }
    }

    private var statusText: String {
        switch status {
        case .inProgress:
            return "正在使用 \(displayName)"
        case .succeeded:
            return "\(displayName) 已完成"
        case .failed:
            return "\(displayName) 执行失败"
        }
    }

    private var displayName: String {
        LocalToolService.displayName(for: name)
    }
}
