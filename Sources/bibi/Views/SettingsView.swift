import SwiftUI

/**
 * 设置页
 *
 * 用户管理、PC 连接管理、智能体配置、主题。
 *
 * @author xiangwei
 */
struct SettingsView: View {
    @State private var userManager: UserManager
    @State private var connection: ConnectionManager
    @State private var newUserName = ""
    @State private var showNewUser = false
    @State private var showPairing: PCDevice?

    init(userManager: UserManager, connection: ConnectionManager) {
        self._userManager = State(initialValue: userManager)
        self._connection = State(initialValue: connection)
    }

    var body: some View {
        NavigationStack {
            Form {
                // 用户管理
                Section("用户") {
                    if let current = userManager.currentLocalUser {
                        HStack {
                            UserAvatarView(
                                name: current.displayName,
                                color: Color(hex: current.avatarColor),
                                size: 40
                            )
                            VStack(alignment: .leading) {
                                Text(current.displayName)
                                    .font(.bibiBody)
                                if let pcId = current.pcUserId {
                                    Text("已关联 PC 用户: \(pcId)")
                                        .font(.bibiCaption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    ForEach(userManager.localUsers) { user in
                        Button(action: { Task { @MainActor in await userManager.switchUser(user) } }) {
                            HStack {
                                UserAvatarView(
                                    name: user.displayName,
                                    color: Color(hex: user.avatarColor),
                                    size: 28
                                )
                                Text(user.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if user.id == userManager.currentLocalUser?.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.brandGold)
                                }
                            }
                        }
                    }

                    Button("新增用户") { showNewUser = true }
                }

                // PC 连接
                Section("PC 连接") {
                    if let pc = connection.connectedPC {
                        HStack {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("已连接到 \(pc.name)")
                        }
                        Button("断开连接", role: .destructive) {
                            connection.disconnect()
                        }
                    }

                    ForEach(connection.discoveredPCs) { pc in
                        HStack {
                            Text(pc.name)
                            Spacer()
                            Button("配对连接") {
                                showPairing = pc
                            }
                        }
                    }

                    if !connection.discoveredPCs.isEmpty {
                        Button("刷新") {
                            connection.startSearching()
                        }
                    }
                }

                // 智能体
                Section("智能体") {
                    SecureField("DeepSeek API Key", text: apiKeyBinding)
                        .font(.bibiCaption)

                    Picker("默认模式", selection: .constant("快速")) {
                        Text("快速").tag("快速")
                        Text("专家").tag("专家")
                    }
                }

                // 主题
                Section("主题") {
                    Picker("外观", selection: .constant(0)) {
                        Text("跟随系统").tag(0)
                        Text("浅色").tag(1)
                        Text("深色").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("设置")
            .alert("新增用户", isPresented: $showNewUser) {
                TextField("名称", text: $newUserName)
                Button("创建") {
                    Task { @MainActor in await userManager.createLocalUser(name: newUserName) }
                    newUserName = ""
                }
                Button("取消", role: .cancel) {}
            }
            .sheet(item: $showPairing) { pc in
                PairingView(
                    pc: pc,
                    connection: connection,
                    onConnected: {}
                )
            }
        }
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { KeychainHelper.shared.readAPIKey() ?? "" },
            set: { KeychainHelper.shared.saveAPIKey($0) }
        )
    }
}
