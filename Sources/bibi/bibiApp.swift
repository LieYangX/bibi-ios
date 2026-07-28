import SwiftUI

@main
struct bibiApp: App {
    @State private var connectionManager = ConnectionManager()
    @State private var settingsStore = SettingsStore()
    @State private var conversationManager = ConversationManager()
    @State private var pcToolService: PcToolService
    @State private var userManager: UserManager
    @State private var agentService: AgentService

    init() {
        try? DatabaseManager.shared.open()
        let c = ConnectionManager()
        let pcTools = PcToolService(connection: c)
        let users = UserManager(connection: c)
        let agent = AgentService(connection: c, conversations: ConversationManager(), users: users, pcTools: pcTools, settings: SettingsStore())
        _pcToolService = State(initialValue: pcTools); _userManager = State(initialValue: users); _agentService = State(initialValue: agent)
        agent.initialize()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(agent: agentService, connection: connectionManager, userManager: userManager, pcTools: pcToolService)
                .environment(connectionManager).environment(userManager).environment(conversationManager)
                .environment(pcToolService).environment(settingsStore)
        }
    }
}
