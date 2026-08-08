import SwiftUI

/**
 * 工具浏览页。
 *
 * 展示本机工具、电脑工具，以及 Skills 和 MCP 服务管理入口。
 *
 * @author xiangwei
 */
struct ToolsView: View {
    let localTools: LocalToolService
    let pcTools: PcToolService
    let connectionState: ConnectionState
    let onOpenConnection: () -> Void

    @State private var searchText = ""
    @State private var skillMCPService = SkillMCPService.shared
    @State private var mcpClient = MCPClient.shared

    var body: some View {
        ZStack {
            AnimatedBackground()

            if filteredLocalTools.isEmpty
                && filteredPermissionTools.isEmpty
                && filteredComputerTools.isEmpty
                && searchText.isEmpty == false {
                ContentUnavailableView.search(text: searchText)
            } else {
                toolList
            }
        }
        .navigationTitle("工具")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "搜索工具"
        )
        .task {
            // 打开工具页时主动加载 MCP 工具列表，更新连接状态
            let configs = skillMCPService.enabledMCPConfigs()
            if !configs.isEmpty {
                _ = await mcpClient.loadTools(from: configs)
            }
        }
    }

    private var toolList: some View {
        List {
            if !filteredLocalTools.isEmpty {
                Section("本机工具") {
                    ForEach(filteredLocalTools) { tool in
                        ToolRow(tool: tool, displayName: LocalToolService.displayName(for: tool.name))
                    }
                }
            }

            if !filteredPermissionTools.isEmpty {
                Section {
                    ForEach(filteredPermissionTools) { tool in
                        ToolRow(tool: tool, displayName: LocalToolService.displayName(for: tool.name))
                    }
                } header: {
                    Text("需要系统授权")
                } footer: {
                    Text("仅在调用工具时由 iOS 请求相应权限。")
                }
            }

            Section("电脑工具") {
                if connectionState == .connected {
                    computerStatus

                    if filteredComputerTools.isEmpty && searchText.isEmpty {
                        Label("暂无可用工具", systemImage: "square.grid.2x2")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredComputerTools) { tool in
                            ToolRow(tool: tool)
                        }
                    }
                } else if searchText.isEmpty {
                    Button(action: onOpenConnection) {
                        HStack(spacing: 12) {
                            Image(systemName: "desktopcomputer")
                                .categoryIconStyle(color: Color.secondaryText)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("电脑未连接")
                                    .foregroundStyle(.primary)
                                Text("连接后可使用电脑工具")
                                    .font(.bibiCaption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.bibiCaptionSemibold)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if searchText.isEmpty {
                Section("Skills") {
                    NavigationLink {
                        SkillsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .categoryIconStyle(color: .brandGold)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Skills")
                                    .font(.bibiBodyMedium)
                                    .foregroundStyle(.primary)
                                Text("\(skillMCPService.skills.count) 个技能，自定义智能体行为")
                                    .font(.bibiCaption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("MCP 服务") {
                    NavigationLink {
                        MCPConfigView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .categoryIconStyle(color: .accentBlue)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("MCP 服务")
                                    .font(.bibiBodyMedium)
                                    .foregroundStyle(.primary)

                                Text(mcpSummary)
                                    .font(.bibiCaption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }

                    // 展示各 MCP 服务器的连接状态
                    ForEach(displayedMCPConfigs) { config in
                        mcpStatusRow(for: config)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var computerStatus: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .categoryIconStyle(color: .successGreen)

            VStack(alignment: .leading, spacing: 3) {
                Text("电脑服务在线")
                    .font(.bibiBodyMedium)
                Text("已载入 \(pcTools.availableTools.count) 个电脑端能力")
                    .font(.bibiCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// MCP 状态摘要。
    private var mcpSummary: String {
        let enabledConfigs = skillMCPService.mcpConfigs.filter { $0.isEnabled }
        guard !enabledConfigs.isEmpty else { return "暂无启用的 MCP 配置" }

        let connectedCount = mcpClient.serverStatuses.values.filter { $0.isConnected }.count
        let totalTools = mcpClient.serverStatuses.values.reduce(0) { $0 + $1.toolCount }

        if connectedCount == 0 {
            return "\(enabledConfigs.count) 个配置，均未连接"
        } else if connectedCount == enabledConfigs.count {
            return "\(enabledConfigs.count) 个配置已连接，共 \(totalTools) 个工具"
        } else {
            return "\(connectedCount)/\(enabledConfigs.count) 个已连接，共 \(totalTools) 个工具"
        }
    }

    /// 需要展示的 MCP 配置（仅启用的）。
    private var displayedMCPConfigs: [MCPConfig] {
        skillMCPService.mcpConfigs.filter { $0.isEnabled }
    }

    /// 单个 MCP 服务器状态行。
    private func mcpStatusRow(for config: MCPConfig) -> some View {
        let status = mcpClient.serverStatuses[config.id]
        let isConnected = status?.isConnected ?? false
        let toolCount = status?.toolCount ?? 0
        let error = status?.error

        return HStack(spacing: 10) {
            Circle()
                .fill(isConnected ? Color.successGreen : Color.errorRed)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name.isEmpty ? "未命名服务" : config.name)
                    .font(.bibiCaptionSemibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if isConnected {
                    Text("已连接 · \(toolCount) 个工具")
                        .font(.bibiCaption2)
                        .foregroundStyle(.secondary)
                } else if let error {
                    Text(error)
                        .font(.bibiCaption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("等待连接…")
                        .font(.bibiCaption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.leading, 4)
    }

    private var filteredLocalTools: [PcToolDef] {
        filter(localTools.availableTools.filter { !LocalToolService.requiresPermission($0.name) })
    }

    private var filteredPermissionTools: [PcToolDef] {
        filter(localTools.availableTools.filter { LocalToolService.requiresPermission($0.name) })
    }

    private var filteredComputerTools: [PcToolDef] {
        guard connectionState == .connected else { return [] }
        return filter(pcTools.availableTools)
    }

    private func filter(_ tools: [PcToolDef]) -> [PcToolDef] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return tools }
        return tools.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.description.localizedCaseInsensitiveContains(keyword)
                || LocalToolService.displayName(for: $0.name).localizedCaseInsensitiveContains(keyword)
        }
    }
}
