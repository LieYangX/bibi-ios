import SwiftUI

/**
 * PC 记账工具浏览页
 *
 * 连接 PC 后动态显示可用工具列表。
 *
 * @author xiangwei
 */
struct ToolsView: View {
    let pcTools: PcToolService
    let connectionState: ConnectionState

    var body: some View {
        NavigationStack {
            Group {
                if connectionState == .connected {
                    List(pcTools.availableTools) { tool in
                        ToolRow(tool: tool)
                    }
                    .listStyle(.plain)
                } else {
                    ContentUnavailableView(
                        "未连接到 PC",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("请先连接 PC 记账服务以查看可用工具")
                    )
                }
            }
            .navigationTitle("记账工具")
        }
    }
}
