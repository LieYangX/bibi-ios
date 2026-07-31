import SwiftUI

/**
 * 根视图。
 *
 * 聊天作为唯一主画布，工具与设置从顶部控制条打开，避免底部导航挤占输入区域。
 *
 * @author xiangwei
 */
struct ContentView: View {
    let agent: AgentService
    let connection: ConnectionManager
    let userManager: UserManager
    let pcTools: PcToolService
    let localTools: LocalToolService

    @State private var navigationPath: [AppRoute] = []
    @State private var showsTools = false
    @State private var opensSettingsAfterTools = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            AgentChatView(
                agent: agent,
                onOpenTools: { showsTools = true },
                onOpenSettings: openSettings
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .settings:
                    settingsView
                }
            }
        }
        .sheet(isPresented: $showsTools) {
            NavigationStack {
                ToolsView(
                    localTools: localTools,
                    pcTools: pcTools,
                    connectionState: connection.state,
                    onOpenConnection: openSettingsFromTools
                )
                .navigationTitle("工具")
                .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") {
                                showsTools = false
                            }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
        }
        .onChange(of: showsTools) { _, isPresented in
            guard !isPresented, opensSettingsAfterTools else { return }
            opensSettingsAfterTools = false
            openSettings()
        }
    }

    private var settingsView: some View {
        SettingsView(
            userManager: userManager,
            connection: connection,
            onDeleteUser: { user in
                try await agent.deleteLocalUser(user)
            }
        )
    }

    /**
     * 跳转到设置页。
     */
    private func openSettings() {
        guard navigationPath.last != .settings else { return }
        navigationPath.append(.settings)
    }

    /**
     * 关闭工具面板后跳转到设置页。
     */
    private func openSettingsFromTools() {
        opensSettingsAfterTools = true
        showsTools = false
    }
}

/**
 * 顶部菜单可打开的功能面板。
 *
 * @author xiangwei
 */
private enum AppRoute: Hashable {
    case settings
}
