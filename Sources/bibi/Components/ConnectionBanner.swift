import SwiftUI

/**
 * 连接状态横幅
 *
 * 展示 PC 连接状态：搜索中、已连接、已断开。
 * 使用 .glassEffect()（导航层材质）。可折叠。
 *
 * @author xiangwei
 */
struct ConnectionBanner: View {
    let state: ConnectionState
    let pcName: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.bibiCaption)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var statusColor: Color {
        switch state {
        case .searching: return .warningYellow
        case .found: return .accentCyan
        case .connected: return .successGreen
        case .disconnected: return .errorRed
        }
    }

    private var statusText: String {
        switch state {
        case .searching:
            return "正在搜索 PC..."
        case .found:
            return "已发现 PC，请配对连接"
        case .connected:
            return "已连接到 \(pcName ?? "PC")"
        case .disconnected:
            return "已断开连接"
        }
    }
}
