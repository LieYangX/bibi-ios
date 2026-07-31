import SwiftUI

/**
 * PC 连接状态胶囊。
 *
 * 状态胶囊属于导航层，使用 Liquid Glass 并提供进入连接设置的入口。
 *
 * @author xiangwei
 */
struct ConnectionBanner: View {
    let state: ConnectionState
    let pcName: String?
    let onTap: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 16)

            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .symbolEffect(.pulse, options: state == .searching ? .repeating : .nonRepeating)

                    Text(statusText)
                        .font(.bibiCaptionSemibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 13)
                .frame(minHeight: 36)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityHint("打开 PC 连接设置")

            Spacer(minLength: 16)
        }
        .padding(.vertical, 6)
    }

    private var statusIcon: String {
        switch state {
        case .searching:
            return "antenna.radiowaves.left.and.right"
        case .found:
            return "desktopcomputer"
        case .connected:
            return "checkmark.circle.fill"
        case .disconnected:
            return "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch state {
        case .searching:
            return .warningYellow
        case .found:
            return .accentBlue
        case .connected:
            return .successGreen
        case .disconnected:
            return .errorRed
        }
    }

    private var statusText: String {
        switch state {
        case .searching:
            return "正在寻找电脑"
        case .found:
            return pcName.map { "发现 \($0)" } ?? "发现可连接电脑"
        case .connected:
            return pcName.map { "已连接 \($0)" } ?? "电脑已连接"
        case .disconnected:
            return "电脑未连接"
        }
    }
}
