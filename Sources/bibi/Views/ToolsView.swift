import SwiftUI

/**
 * 工具浏览页。
 *
 * @author xiangwei
 */
struct ToolsView: View {
    let localTools: LocalToolService
    let pcTools: PcToolService
    let connectionState: ConnectionState
    let onOpenConnection: () -> Void

    @State private var searchText = ""

    var body: some View {
        ZStack {
            AnimatedBackground()

            if filteredLocalTools.isEmpty
                && filteredPermissionTools.isEmpty
                && filteredComputerTools.isEmpty {
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
                                .categoryIconStyle(color: Color(uiColor: .secondaryLabel))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("电脑未连接")
                                    .foregroundStyle(.primary)
                                Text("连接后可使用电脑工具")
                                    .font(.bibiCaption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
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
                    .font(.body.weight(.medium))
                Text("已载入 \(pcTools.availableTools.count) 个记账能力")
                    .font(.bibiCaption)
                    .foregroundStyle(.secondary)
            }
        }
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
