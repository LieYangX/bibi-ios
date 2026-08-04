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
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var connectionManager: ConnectionManager
    @State private var settingsStore: SettingsStore
    @State private var conversationManager: ConversationManager
    @State private var pcToolService: PcToolService
    @State private var localToolService: LocalToolService
    @State private var userManager: UserManager
    @State private var agentService: AgentService
    @State private var voiceInput: VoiceInputManager
    @State private var memoryManager: MemoryManager
    @State private var themeManager = ThemeManager()
    @State private var notificationManager = NotificationManager.shared
    @State private var proactiveService = ProactiveMessageService.shared

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
        let mcpClient = MCPClient.shared
        let users = UserManager(connection: connection)
        let memory = MemoryManager()
        let voice = VoiceInputManager(settings: settings)
        let agent = AgentService(
            connection: connection,
            conversations: conversations,
            users: users,
            pcTools: pcTools,
            localTools: localTools,
            mcpClient: mcpClient,
            settings: settings,
            memory: memory
        )

        _connectionManager = State(initialValue: connection)
        _settingsStore = State(initialValue: settings)
        _conversationManager = State(initialValue: conversations)
        _pcToolService = State(initialValue: pcTools)
        _localToolService = State(initialValue: localTools)
        _userManager = State(initialValue: users)
        _agentService = State(initialValue: agent)
        _voiceInput = State(initialValue: voice)
        _memoryManager = State(initialValue: memory)
        agent.initialize()
        // 注入主动消息服务依赖并启动调度
        proactiveService.configure(agent: agent, settings: settings)
        proactiveService.start()

        users.onUserSwitched = { [weak agent] userId in
            await agent?.onUserSwitched(to: userId)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                agent: agentService,
                voice: voiceInput,
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
            .environment(memoryManager)
            .environment(themeManager)
            .environment(notificationManager)
            .environment(proactiveService)
            .preferredColorScheme(themeManager.preferredScheme.toColorScheme)
            .task {
                // 启动时申请通知授权
                await notificationManager.requestAuthorization()
            }
            .onChange(of: scenePhase) { _, newPhase in
                proactiveService.handleScenePhase(newPhase)
            }
        }
    }
}
