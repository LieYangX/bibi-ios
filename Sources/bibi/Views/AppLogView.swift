import SwiftUI

/**
 * 应用日志查询页面。
 *
 * @author xiangwei
 */
struct AppLogView: View {
    @State private var entries: [AppLogEntry] = []
    @State private var selectedFilter = LogFilter.all
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var exportURL: URL?
    @State private var showsClearConfirmation = false
    @State private var showsDebugConfig = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("日志等级", selection: $selectedFilter) {
                ForEach(LogFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: selectedFilter == .error ? "checkmark.shield" : "doc.text.magnifyingglass",
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredEntries) { entry in
                            AppLogEntryRow(entry: entry)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.contentBackground.ignoresSafeArea())
        .navigationTitle("应用日志")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索内容或日志编号")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    AgentLogView()
                } label: {
                    Image(systemName: "cpu")
                }
                .accessibilityLabel("智能体日志")

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("导出日志")
                }

                Menu {
                    Button(action: reload) {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    Button {
                        showsDebugConfig = true
                    } label: {
                        Label("调试智能体", systemImage: "ladybug")
                    }
                    Button(role: .destructive) {
                        showsClearConfirmation = true
                    } label: {
                        Label("清空日志", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("日志操作")
            }
        }
        .task {
            await loadLogs()
        }
        .refreshable {
            await loadLogs()
        }
        .alert("无法读取日志", isPresented: loadErrorBinding) {
            Button("好", role: .cancel) { }
        } message: {
            Text(loadError ?? "请稍后重试。")
        }
        .confirmationDialog("清空全部应用日志？", isPresented: $showsClearConfirmation) {
            Button("清空日志", role: .destructive) {
                clearLogs()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("清空后无法恢复。")
        }
        .sheet(isPresented: $showsDebugConfig) {
            DebugAgentConfigView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var filteredEntries: [AppLogEntry] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            guard selectedFilter.includes(entry.level) else { return false }
            guard !keyword.isEmpty else { return true }
            return entry.category.lowercased().contains(keyword)
                || entry.message.lowercased().contains(keyword)
                || entry.traceId?.lowercased().contains(keyword) == true
                || entry.metadata.values.contains { $0.lowercased().contains(keyword) }
        }
    }

    private var emptyTitle: String {
        searchText.isEmpty && selectedFilter == .error ? "暂无错误" : "没有匹配日志"
    }

    private var emptyDescription: String {
        searchText.isEmpty && selectedFilter == .error
            ? "应用尚未记录到错误信息。"
            : "可以切换等级或调整搜索内容。"
    }

    /**
     * 触发日志刷新。
     * @author xiangwei
     */
    private func reload() {
        Task {
            await loadLogs()
        }
    }

    /**
     * 加载日志和导出文件。
     * @author xiangwei
     */
    @MainActor
    private func loadLogs() async {
        do {
            entries = try await AppLogger.shared.loadEntries()
            exportURL = try await AppLogger.shared.makeExportFile()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /**
     * 清空日志并刷新页面。
     * @author xiangwei
     */
    private func clearLogs() {
        Task { @MainActor in
            do {
                try await AppLogger.shared.clear()
                entries = []
                exportURL = nil
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private var loadErrorBinding: Binding<Bool> {
        Binding(
            get: { loadError != nil },
            set: { isPresented in
                if !isPresented {
                    loadError = nil
                }
            }
        )
    }
}

/**
 * 日志等级筛选项。
 *
 * @author xiangwei
 */
private enum LogFilter: String, CaseIterable, Identifiable {
    case all
    case error
    case warning
    case info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .error: "错误"
        case .warning: "警告"
        case .info: "信息"
        }
    }

    /**
     * 判断日志等级是否属于当前筛选项。
     *
     * @param level 日志等级
     * @returns 是否包含
     * @author xiangwei
     */
    func includes(_ level: AppLogLevel) -> Bool {
        switch self {
        case .all:
            return true
        case .error:
            return level == .error
        case .warning:
            return level == .warning
        case .info:
            return level == .info || level == .debug
        }
    }
}

/**
 * 单条应用日志视图。
 *
 * @author xiangwei
 */
private struct AppLogEntryRow: View {
    let entry: AppLogEntry
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let traceId = entry.traceId {
                    logDetail(title: "日志编号", value: traceId)
                }

                ForEach(entry.metadata.keys.sorted(), id: \.self) { key in
                    logDetail(title: key, value: entry.metadata[key] ?? "")
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: entry.level.systemImage)
                    .foregroundStyle(entry.level.color)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(entry.category)
                            .font(.bibiCaptionSemibold)
                        Spacer()
                        Text(entry.timestamp, format: .dateTime.hour().minute().second())
                            .font(.bibiMonospacedCaption)
                            .foregroundStyle(.secondary)
                    }

                    Text(entry.message)
                        .font(.bibiCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(13)
        .background(Color.contentCardBackground, in: BibiShape.contentCard)
        .textSelection(.enabled)
    }

    /**
     * 构建日志明细行。
     *
     * @param title 明细名称
     * @param value 明细内容
     * @returns 日志明细行
     * @author xiangwei
     */
    private func logDetail(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.bibiMonospacedCaption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension AppLogLevel {
    var systemImage: String {
        switch self {
        case .debug: "ladybug"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .debug: .secondary
        case .info: .accentBlue
        case .warning: .warningYellow
        case .error: .errorRed
        }
    }
}
