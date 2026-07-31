import SwiftUI

/**
 * 笔笔应用入口。
 *
 * 所有页面共享同一组连接、用户、会话和设置服务，保证跨标签状态一致。
 *
 * @author xiangwei
 */
@main
struct bibiApp: App {
    @State private var connectionManager: ConnectionManager
    @State private var settingsStore: SettingsStore
    @State private var conversationManager: ConversationManager
    @State private var pcToolService: PcToolService
    @State private var localToolService: LocalToolService
    @State private var userManager: UserManager
    @State private var agentService: AgentService
    @State private var themeManager = ThemeManager()

    init() {
        let pendingOperation = CrashBreadcrumbStore.consumePending()
        if let pendingOperation {
            Task {
                await AppLogger.shared.log(
                    .error,
                    category: "crash",
                    message: "上次运行在关键操作期间意外中断",
                    traceId: pendingOperation.traceId,
                    metadata: [
                        "operation": pendingOperation.operation,
                        "stage": pendingOperation.stage,
                        "tool_name": pendingOperation.toolName ?? "unknown",
                        "last_updated_at": pendingOperation.updatedAt.ISO8601Format()
                    ]
                )
            }
        }

        do {
            try DatabaseManager.shared.open()
            Task {
                await AppLogger.shared.log(.info, category: "app", message: "应用启动，数据库初始化完成")
            }
        } catch {
            let message = error.localizedDescription
            Task {
                await AppLogger.shared.log(.error, category: "database", message: message)
            }
        }

        let connection = ConnectionManager()
        let settings = SettingsStore()
        let conversations = ConversationManager()
        let pcTools = PcToolService(connection: connection)
        let localTools = LocalToolService()
        let users = UserManager(connection: connection)
        let agent = AgentService(
            connection: connection,
            conversations: conversations,
            users: users,
            pcTools: pcTools,
            localTools: localTools,
            settings: settings
        )

        _connectionManager = State(initialValue: connection)
        _settingsStore = State(initialValue: settings)
        _conversationManager = State(initialValue: conversations)
        _pcToolService = State(initialValue: pcTools)
        _localToolService = State(initialValue: localTools)
        _userManager = State(initialValue: users)
        _agentService = State(initialValue: agent)
        agent.initialize()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                agent: agentService,
                connection: connectionManager,
                userManager: userManager,
                pcTools: pcToolService,
                localTools: localToolService
            )
            .environment(connectionManager)
            .environment(userManager)
            .environment(conversationManager)
            .environment(pcToolService)
            .environment(settingsStore)
            .environment(themeManager)
            .preferredColorScheme(themeManager.preferredScheme.toColorScheme)
        }
    }
}
