import SwiftUI

/**
 * 工具描述行。
 *
 * @author xiangwei
 */
struct ToolRow: View {
    let tool: PcToolDef
    let displayName: String?

    init(tool: PcToolDef, displayName: String? = nil) {
        self.tool = tool
        self.displayName = displayName
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: toolIcon)
                .categoryIconStyle(color: toolColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName ?? tool.name)
                    .font(.bibiBodyMedium)
                    .foregroundStyle(.primary)

                Text(tool.description)
                    .font(.bibiCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var toolIcon: String {
        let name = tool.name.lowercased()
        if let localToolIcon = LocalToolService.iconName(for: tool.name) {
            return localToolIcon
        }
        if name.contains("transaction") || name.contains("bill") {
            return "list.bullet.rectangle.fill"
        }
        if name.contains("account") || name.contains("asset") {
            return "creditcard.fill"
        }
        if name.contains("budget") {
            return "gauge.with.dots.needle.50percent"
        }
        if name.contains("stat") || name.contains("report") {
            return "chart.bar.xaxis"
        }
        if name.contains("category") {
            return "square.grid.2x2.fill"
        }
        if name.contains("time") || name.contains("clock") {
            return "clock.fill"
        }
        return "square.grid.2x2.fill"
    }

    private var toolColor: Color {
        let name = tool.name.lowercased()
        if tool.name == LocalToolService.currentLocationToolName
            || tool.name == LocalToolService.searchContactsToolName {
            return .accentBlue
        }
        if tool.name == LocalToolService.calendarEventsToolName {
            return .successGreen
        }
        if tool.name == LocalToolService.batteryStatusToolName {
            return .warningYellow
        }
        if tool.name == LocalToolService.healthInfoToolName {
            return .successGreen
        }
        if LocalToolService.iconName(for: tool.name) != nil {
            return .brandGold
        }
        if name.contains("budget") {
            return .warningYellow
        }
        if name.contains("stat") || name.contains("report") {
            return .successGreen
        }
        if name.contains("time") || name.contains("clock") {
            return .brandGold
        }
        return .accentBlue
    }
}
