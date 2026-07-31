import SwiftUI

/**
 * 应用设置页。
 *
 * 使用独立导航页面承载账户、连接、智能体和外观设置。
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
    @Environment(ThemeManager.self) private var themeManager
    @Environment(SettingsStore.self) private var settingsStore
    let onDeleteUser: @MainActor (LocalUser) async throws -> Void

    /**
     * 初始化设置页。
     *
     * @param userManager 用户管理器
     * @param connection 连接管理器
     * @param onDeleteUser 删除用户回调
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                accountSummary
                userSection
                connectionSection
                agentSection
                appearanceSection
                aboutSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(Color.contentBackground.ignoresSafeArea())
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    private var accountSummary: some View {
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
                    .font(.system(size: 44, weight: .light))
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
        .padding(16)
        .background(Color.contentCardBackground, in: BibiShape.contentCard)
    }

    private var userSection: some View {
        SettingsGroup(title: "本地用户", systemImage: "person.2") {
            if userManager.localUsers.isEmpty {
                SettingsEmptyRow(text: "还没有本地用户", systemImage: "person.crop.circle.badge.questionmark")
            }

            ForEach(Array(userManager.localUsers.enumerated()), id: \.element.id) { index, user in
                if index > 0 || userManager.localUsers.isEmpty {
                    Divider()
                }
                userRow(user)
            }

            if !userManager.localUsers.isEmpty {
                Divider()
            }

            Button {
                showNewUser = true
            } label: {
                SettingsActionRow(
                    title: "新增用户",
                    subtitle: "创建独立的本地对话空间",
                    systemImage: "person.crop.circle.badge.plus",
                    tint: .accentBlue
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var connectionSection: some View {
        SettingsGroup(title: "电脑连接", systemImage: "desktopcomputer") {
            if let pc = connection.connectedPC {
                SettingsStatusRow(
                    title: pc.name,
                    subtitle: "已连接并通过认证",
                    systemImage: "desktopcomputer",
                    tint: .successGreen
                )
                Divider()
                Button("断开连接", role: .destructive) {
                    connection.disconnect()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 13)
            } else {
                SettingsEmptyRow(text: "尚未连接电脑", systemImage: "desktopcomputer")
            }

            ForEach(connection.discoveredPCs) { pc in
                Divider()
                Button {
                    showPairing = pc
                } label: {
                    SettingsActionRow(
                        title: pc.name,
                        subtitle: "输入配对码连接",
                        systemImage: "link.badge.plus",
                        tint: .accentBlue
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()
            Button {
                connection.startSearching()
            } label: {
                SettingsActionRow(
                    title: connection.state == .searching ? "正在搜索" : "重新搜索",
                    subtitle: "查找同一网络中的笔笔电脑版",
                    systemImage: "arrow.clockwise",
                    tint: .accentBlue,
                    showsDisclosure: false
                )
            }
            .buttonStyle(.plain)
            .disabled(connection.state == .searching)
        }
    }

    private var agentSection: some View {
        SettingsGroup(title: "智能体", systemImage: "sparkles") {
            HStack(spacing: 12) {
                SettingsIcon(systemImage: "key.fill", tint: .warningYellow)
                SecureField("DeepSeek API Key", text: apiKeyBinding)
                    .font(.bibiBody)
                    .textContentType(.password)
            }
            .padding(.vertical, 11)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("默认模式")
                    .font(.bibiCaptionSemibold)
                Picker("默认模式", selection: defaultModeBinding) {
                    Text("快速").tag("快速")
                    Text("专家").tag("专家")
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 11)

            Text("API Key 仅保存在系统钥匙串中。")
                .font(.bibiCaption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 11)
        }
    }

    private var appearanceSection: some View {
        SettingsGroup(title: "外观", systemImage: "circle.lefthalf.filled") {
            Picker("配色", selection: preferredSchemeBinding) {
                Text("自动").tag(ThemePreference.system)
                Text("浅色").tag(ThemePreference.light)
                Text("深色").tag(ThemePreference.dark)
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 13)
        }
    }

    private var aboutSection: some View {
        SettingsGroup(title: "应用", systemImage: "info.circle") {
            NavigationLink {
                AboutAppView()
            } label: {
                SettingsActionRow(
                    title: "关于应用",
                    subtitle: "版本、隐私与诊断信息",
                    systemImage: "info.circle.fill",
                    tint: .brandGoldDark
                )
            }
            .buttonStyle(.plain)
        }
    }

    /**
     * 构建用户设置行。
     *
     * @param user 本地用户
     * @returns 用户设置行
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
        .padding(.vertical, 9)
    }

    /**
     * 创建本地用户。
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

    private var defaultModeBinding: Binding<String> {
        Binding(
            get: { settingsStore.get(.defaultMode) ?? "快速" },
            set: { settingsStore.set(.defaultMode, value: $0) }
        )
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

/**
 * 设置页分组容器。
 *
 * @author xiangwei
 */
private struct SettingsGroup<Content: View>: View {
    let title: String
    let systemImage: String
    let content: () -> Content

    /**
     * 初始化设置分组。
     *
     * @param title 分组标题
     * @param systemImage 分组图标
     * @param content 分组内容
     */
    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.bibiCaptionSemibold)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .background(Color.contentCardBackground, in: BibiShape.contentCard)
        }
    }
}

/**
 * 设置页标准图标。
 *
 * @author xiangwei
 */
private struct SettingsIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/**
 * 可操作的设置行。
 *
 * @author xiangwei
 */
private struct SettingsActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var showsDisclosure = true

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.bibiCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/**
 * 设置状态行。
 *
 * @author xiangwei
 */
private struct SettingsStatusRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(subtitle)
                    .font(.bibiCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(tint)
                .accessibilityLabel(subtitle)
        }
        .padding(.vertical, 11)
    }
}

/**
 * 设置空状态行。
 *
 * @author xiangwei
 */
private struct SettingsEmptyRow: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.bibiBody)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
    }
}
