import SwiftUI

/**
 * 根视图
 *
 * TabView 包含三个标签：智能体聊天、记账工具、设置。
 *
 * @author xiangwei
 */
struct ContentView: View {
    let agent: AgentService
    let connection: ConnectionManager
    let userManager: UserManager
    let pcTools: PcToolService

    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            AnimatedBackground()

            TabView(selection: $selectedTab) {
                AgentChatView(agent: agent)
                    .tabItem {
                        Label("聊天", systemImage: "message.fill")
                    }
                    .tag(0)

                ToolsView(pcTools: pcTools, connectionState: connection.state)
                    .tabItem {
                        Label("工具", systemImage: "wrench.and.screwdriver")
                    }
                    .tag(1)

                SettingsView(userManager: userManager, connection: connection)
                    .tabItem {
                        Label("设置", systemImage: "gearshape.fill")
                    }
                    .tag(2)
            }
            .tint(Color.brandGold)
        }
    }
}
