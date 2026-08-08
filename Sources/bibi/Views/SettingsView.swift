import SwiftUI

/**
 * 应用设置页。
 *
 * 使用与工具页一致的原生列表风格：动态背景、insetGrouped 分组、分类图标行。
 * 作为导航栈中的整页显示，覆盖账户、连接、智能体和外观设置。
 *
 * @author xiangwei
 */
struct SettingsView: View {
    @State private var userManager: UserManager
    @State private var connection: ConnectionManager
    @State private var newUserName = ""
    @State private var showNewUser = false
    @State private var showPairing: PCDevice?
    @State private var userPendingDeletion: LocalUser?
    @State private var deletionError: String?
    @State private var thinkingEnabled = true
    @State private var showsDebugConfig = false
    @Environment(ThemeManager.self) private var themeManager
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(MemoryManager.self) private var memoryManager
    @Environment(ProactiveMessageService.self) private var proactiveService
    let onDeleteUser: @MainActor (LocalUser) async throws -> Void

    /**
     * 初始化设置页。
     *
     * @param userManager 用户管理器
     * @param connection 连接管理器
     * @param onDeleteUser 删除用户回调
     * @author xiangwei
     */
    init(
        userManager: UserManager,
        connection: ConnectionManager,
        onDeleteUser: @escaping @MainActor (LocalUser) async throws -> Void
    ) {
        _userManager = State(initialValue: userManager)
        _connection = State(initialValue: connection)
        self.onDeleteUser = onDeleteUser
    }

    var body: some View {
        ZStack {
            AnimatedBackground()

            List {
                accountSection
                userSection
                connectionSection
                agentSection
                proactiveSection
                memorySection
                appearanceSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // 从持久化设置同步思考模式开关状态
            thinkingEnabled = settingsStore.get(.thinkingEnabled) != "false"
        }
        .alert("新增用户", isPresented: $showNewUser) {
            TextField("名称", text: $newUserName)
            Button("创建", action: createUser)
            Button("取消", role: .cancel) {
                newUserName = ""
            }
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: deletionConfirmationBinding,
            titleVisibility: .visible,
            presenting: userPendingDeletion
        ) { user in
            Button("删除用户", role: .destructive) {
                deleteUser(user)
            }
            Button("取消", role: .cancel) { }
        } message: { _ in
            Text("该用户保存在本机的对话和消息也会被删除。")
        }
        .alert("无法删除用户", isPresented: deletionErrorBinding) {
            Button("好", role: .cancel) { }
        } message: {
            Text(deletionError ?? "请稍后重试。")
        }
        .sheet(item: $showPairing) { pc in
            PairingView(pc: pc, connection: connection, onConnected: {})
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsDebugConfig) {
            DebugAgentConfigView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    /// 当前账户摘要。
    private var accountSection: some View {
        Section {
            HStack(spacing: 14) {
                if let currentUser = userManager.currentLocalUser {
                    UserAvatarView(
                        name: currentUser.displayName,
                        color: Color(hex: currentUser.avatarColor),
                        size: 52
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentUser.displayName)
                            .font(.bibiTitle)
                        Text(connectionSummary)
                            .font(.bibiCaption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.bibiLargeTitle)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("尚未创建用户")
                            .font(.bibiTitle)
                        Text("创建本地用户后即可开始对话")
                            .font(.bibiCaption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Circle()
                    .fill(connection.state == .connected ? Color.successGreen : Color.secondary.opacity(0.35))
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(connectionSummary)
            }
            .padding(.vertical, 6)
        }
    }

    /// 本地用户管理分组。
    private var userSection: some View {
        Section("本地用户") {
            if userManager.localUsers.isEmpty {
                Label("还没有本地用户", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.bibiBody)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(userManager.localUsers.enumerated()), id: \.element.id) { _, user in
                userRow(user)
            }

            Button {
                showNewUser = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .categoryIconStyle(color: .accentBlue)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("新增用户")
                            .font(.bibiBodyMedium)
                            .foregroundStyle(.primary)
                        Text("创建独立的本地对话空间")
                            .font(.bibiCaption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// 电脑连接分组。
    private var connectionSection: some View {
        Section("电脑连接") {
            if let pc = connection.connectedPC {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer")
                        .categoryIconStyle(color: .successGreen)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(pc.name)
                            .font(.bibiBodyMedium)
                        Text("已连接并通过认证")
                            .font(.bibiCaption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.successGreen)
                }
                .padding(.vertical, 4)

                Button("断开连接", role: .destructive) {
                    connection.disconnect()
                }
            } else {
                Label("尚未连接电脑", systemImage: "desktopcomputer")
                    .font(.bibiBody)
                    .foregroundStyle(.secondary)
            }

            ForEach(connection.discoveredPCs) { pc in
                Button {
                    showPairing = pc
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "link.badge.plus")
                            .categoryIconStyle(color: .accentBlue)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(pc.name)
                                .font(.bibiBodyMedium)
                                .foregroundStyle(.primary)
                            Text("输入配对码连接")
                                .font(.bibiCaption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.bibiCaptionSemibold)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                connection.startSearching()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise")
                        .categoryIconStyle(color: .accentBlue)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(connection.state == .searching ? "正在搜索" : "重新搜索")
                            .font(.bibiBodyMedium)
                            .foregroundStyle(.primary)
                        Text("查找同一网络中的星枢电脑版")
                            .font(.bibiCaption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(connection.state == .searching)
        }
    }

    /// 智能体配置分组。
    private var agentSection: some View {
        Section("智能体") {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .categoryIconStyle(color: .warningYellow)
                SecureField("DeepSeek API Key", text: apiKeyBinding)
                    .font(.bibiBody)
                    .textContentType(.password)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("模型")
                    .font(.bibiCaptionSemibold)
                Picker("模型", selection: modelBinding) {
                    ForEach(DeepSeekModel.allCases, id: \.rawValue) { model in
                        Text(model.displayName).tag(model.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Toggle(isOn: thinkingBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("思考模式")
                        .font(.bibiBody)
                    Text("回答前先推理，提升准确率，回答更慢")
                        .font(.bibiCaption)
                        .foregroundStyle(.secondary)
                }
            }

            if thinkingEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    Text("思考强度")
                        .font(.bibiCaptionSemibold)
                    Picker("思考强度", selection: reasoningEffortBinding) {
                        Text("低").tag("low")
                        Text("高").tag("high")
                        Text("最高").tag("max")
                    }
                    .pickerStyle(.segmented)
                }
            }

            Toggle(isOn: speechCorrectionEnabledBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("语音自动矫正")
                        .font(.bibiBody)
                    Text("识别结束后用 AI 修正同音字和错别字")
                        .font(.bibiCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("API Key 仅保存在系统钥匙串中。")
                .font(.bibiCaption)
                .foregroundStyle(.secondary)
        }
    }

    /// 主动消息配置分组。
    private var proactiveSection: some View {
        Section("主动消息") {
            Toggle(isOn: proactiveEnabledBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("允许星枢主动联系你")
                        .font(.bibiBody)
                    Text("定时主动发消息，你正在使用时不会打扰")
                        .font(.bibiCaption)
                        .foregroundStyle(.secondary)
                }
            }

            if proactiveEnabledBinding.wrappedValue {
                VStack(alignment: .leading, spacing: 10) {
                    Text("触发间隔")
                        .font(.bibiCaptionSemibold)
                    Stepper(
                        value: proactiveIntervalBinding,
                        in: 10...1440,
                        step: 10
                    ) {
                        Text(proactiveIntervalText)
                            .font(.bibiBody)
                    }
                }
            }
        }
    }

    /// 智能体记忆分组。
    private var memorySection: some View {
        Section("记忆") {
            Stepper(
                value: windowSizeBinding,
                in: 4...60,
                step: 2
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("会话滑动窗口：\(windowSizeBinding.wrappedValue) 条")
                        .font(.bibiBody)
                    Text("上下文保留最近消息数，超出部分自动提炼成记忆")
                        .font(.bibiCaption)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                MemorySoulView()
            } label: {
                memoryRow(
                    icon: "sparkles",
                    color: .brandGold,
                    title: "灵魂设定",
                    subtitle: "对话中积累的行为规则，共 \(memoryManager.soulRuleItems.count) 条"
                )
            }

            NavigationLink {
                MemoryItemsView(category: .userProfile)
            } label: {
                memoryRow(
                    icon: "person.text.rectangle",
                    color: .accentBlue,
                    title: "用户画像",
                    subtitle: "关于你的信息，共 \(memoryManager.profileItems.count) 条"
                )
            }

            NavigationLink {
                MemoryItemsView(category: .longTerm)
            } label: {
                memoryRow(
                    icon: "brain",
                    color: .successGreen,
                    title: "长久记忆",
                    subtitle: "跨会话记住的事实，共 \(memoryManager.longTermItems.count) 条"
                )
            }
        }
    }

    /**
     * 构建记忆分组行。
     *
     * @param icon 图标名
     * @param color 图标颜色
     * @param title 行标题
     * @param subtitle 行副标题
     * @returns 记忆设置行
     * @author xiangwei
     */
    private func memoryRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .categoryIconStyle(color: color)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.bibiBodyMedium)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.bibiCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// 外观分组。
    private var appearanceSection: some View {
        Section("外观") {
            Picker("配色", selection: preferredSchemeBinding) {
                Text("自动").tag(ThemePreference.system)
                Text("浅色").tag(ThemePreference.light)
                Text("深色").tag(ThemePreference.dark)
            }
            .pickerStyle(.segmented)
        }
    }

    /// 应用分组。
    private var aboutSection: some View {
        Section("应用") {
            NavigationLink {
                AboutAppView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .categoryIconStyle(color: .brandGoldDark)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("关于应用")
                            .font(.bibiBodyMedium)
                            .foregroundStyle(.primary)
                        Text("版本、隐私与诊断信息")
                            .font(.bibiCaption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    /**
     * 构建用户设置行。
     *
     * @param user 本地用户
     * @returns 用户设置行
     * @author xiangwei
     */
    private func userRow(_ user: LocalUser) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { @MainActor in
                    await userManager.switchUser(user)
                }
            } label: {
                HStack(spacing: 12) {
                    UserAvatarView(
                        name: user.displayName,
                        color: Color(hex: user.avatarColor),
                        size: 38
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.displayName)
                            .foregroundStyle(.primary)
                        Text(user.pcUserId == nil ? "仅保存在此设备" : "已关联电脑用户")
                            .font(.bibiCaption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if user.id == userManager.currentLocalUser?.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.brandGold)
                            .accessibilityLabel("当前用户")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                userPendingDeletion = user
            } label: {
                Image(systemName: "trash")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除 \(user.displayName)")
        }
        .padding(.vertical, 6)
    }

    /**
     * 创建本地用户。
     * @author xiangwei
     */
    private func createUser() {
        let name = newUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task { @MainActor in
            await userManager.createLocalUser(name: name)
        }
        newUserName = ""
    }

    /**
     * 删除本地用户。
     *
     * @param user 待删除用户
     * @author xiangwei
     */
    private func deleteUser(_ user: LocalUser) {
        Task { @MainActor in
            do {
                try await onDeleteUser(user)
            } catch {
                deletionError = error.localizedDescription
            }
        }
    }

    private var connectionSummary: String {
        connection.state == .connected ? "电脑服务已连接" : "电脑服务未连接"
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { KeychainHelper.shared.readAPIKey() ?? "" },
            set: { KeychainHelper.shared.saveAPIKey($0) }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { settingsStore.llmModel },
            set: { settingsStore.llmModel = $0 }
        )
    }

    private var thinkingBinding: Binding<Bool> {
        Binding(
            get: { thinkingEnabled },
            set: { newValue in
                thinkingEnabled = newValue
                settingsStore.set(.thinkingEnabled, value: newValue ? "true" : "false")
            }
        )
    }

    private var reasoningEffortBinding: Binding<String> {
        Binding(
            get: { settingsStore.reasoningEffort },
            set: { settingsStore.reasoningEffort = $0 }
        )
    }

    private var speechCorrectionEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.speechCorrectionEnabled },
            set: { settingsStore.speechCorrectionEnabled = $0 }
        )
    }

    private var windowSizeBinding: Binding<Int> {
        Binding(
            get: { settingsStore.conversationWindowSize },
            set: { settingsStore.conversationWindowSize = $0 }
        )
    }

    private var proactiveEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.proactiveEnabled },
            set: { newValue in
                settingsStore.proactiveEnabled = newValue
                proactiveService.settingsDidChange()
            }
        )
    }

    private var proactiveIntervalBinding: Binding<Int> {
        Binding(
            get: { settingsStore.proactiveIntervalMinutes },
            set: { newValue in
                settingsStore.proactiveIntervalMinutes = newValue
                proactiveService.settingsDidChange()
            }
        )
    }

    /// 触发间隔文案（小时/分钟）。
    private var proactiveIntervalText: String {
        let minutes = settingsStore.proactiveIntervalMinutes
        if minutes % 60 == 0 {
            return "每 \(minutes / 60) 小时"
        }
        if minutes < 60 {
            return "每 \(minutes) 分钟"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return "每 \(hours) 小时 \(remainder) 分钟"
    }

    private var preferredSchemeBinding: Binding<ThemePreference> {
        Binding(
            get: { themeManager.preferredScheme },
            set: { themeManager.preferredScheme = $0 }
        )
    }

    private var deletionTitle: String {
        guard let user = userPendingDeletion else { return "删除本地用户？" }
        return "删除“\(user.displayName)”？"
    }

    private var deletionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { userPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    userPendingDeletion = nil
                }
            }
        )
    }

    private var deletionErrorBinding: Binding<Bool> {
        Binding(
            get: { deletionError != nil },
            set: { isPresented in
                if !isPresented {
                    deletionError = nil
                }
            }
        )
    }
}
