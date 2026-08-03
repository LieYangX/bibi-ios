import SwiftUI

/**
 * MCP 服务配置页面。
 *
 * 管理智能体可连接的 MCP 服务端点，支持新增、编辑、启用/禁用和删除。
 *
 * @author xiangwei
 */
struct MCPConfigView: View {
    @State private var sheetConfig: MCPConfig?

    var body: some View {
        List {
            if SkillMCPService.shared.mcpConfigs.isEmpty {
                ContentUnavailableView(
                    "还没有 MCP 配置",
                    systemImage: "server.rack",
                    description: Text("添加 MCP 服务以扩展智能体工具")
                )
            } else {
                ForEach(SkillMCPService.shared.mcpConfigs) { config in
                    mcpRow(config)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                SkillMCPService.shared.deleteMCPConfig(config)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.contentBackground.ignoresSafeArea())
        .navigationTitle("MCP 服务")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sheetConfig = MCPConfig()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $sheetConfig) { config in
            MCPEditView(config: config, service: SkillMCPService.shared)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    /// MCP 配置行。
    private func mcpRow(_ config: MCPConfig) -> some View {
        Button {
            sheetConfig = config
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .categoryIconStyle(color: config.isEnabled ? .accentBlue : .secondaryText)

                VStack(alignment: .leading, spacing: 4) {
                    Text(config.name.isEmpty ? "未命名服务" : config.name)
                        .font(.bibiBodyMedium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(config.serverURL.isEmpty ? "未配置端点" : config.serverURL)
                        .font(.bibiCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.bibiCaptionSemibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/**
 * MCP 配置编辑表单。
 *
 * @author xiangwei
 */
private struct MCPEditView: View {
    let config: MCPConfig
    let service: SkillMCPService
    let isNew: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var desc: String
    @State private var serverURL: String
    @State private var token: String
    @State private var isEnabled: Bool

    init(config: MCPConfig, service: SkillMCPService) {
        self.config = config
        self.service = service
        self.isNew = !service.mcpConfigs.contains(where: { $0.id == config.id })
        _name = State(initialValue: config.name)
        _desc = State(initialValue: config.description)
        _serverURL = State(initialValue: config.serverURL)
        _token = State(initialValue: config.token)
        _isEnabled = State(initialValue: config.isEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("服务名称", text: $name)
                    TextField("服务描述", text: $desc)
                    Toggle("启用", isOn: $isEnabled)
                        .tint(.accentBlue)
                }

                Section("连接配置") {
                    TextField("服务端点 URL", text: $serverURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocapitalization(.none)

                    SecureField("认证令牌（可选）", text: $token)
                        .textContentType(.password)
                }

                Section {
                    Text("MCP 服务遵循 Model Context Protocol，为智能体提供额外工具能力。")
                        .font(.bibiCaption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle(isNew ? "新增 MCP" : "编辑 MCP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                        dismiss()
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }

    /**
     * 保存 MCP 配置编辑。
     * @author xiangwei
     */
    private func save() {
        var updated = config
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.token = token
        updated.isEnabled = isEnabled
        service.saveMCPConfig(updated)
    }
}
