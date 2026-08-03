import SwiftUI

/**
 * 智能体请求日志查询页面。
 *
 * 展示每次 LLM API 请求的完整入参出参，方便调试智能体行为。
 *
 * @author xiangwei
 */
struct AgentLogView: View {
    @State private var entries: [AgentLogEntry] = []
    @State private var selectedFilter = AgentLogFilter.all
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var showsClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("状态", selection: $selectedFilter) {
                ForEach(AgentLogFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "terminal",
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredEntries) { entry in
                            AgentLogEntryRow(entry: entry)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.contentBackground.ignoresSafeArea())
        .navigationTitle("智能体日志")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索 traceId 或模型名")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")

                Button(role: .destructive) {
                    showsClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("清空日志")
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
        .confirmationDialog("清空全部智能体日志？", isPresented: $showsClearConfirmation) {
            Button("清空日志", role: .destructive) {
                clearLogs()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("清空后无法恢复。")
        }
    }

    private var filteredEntries: [AgentLogEntry] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            guard selectedFilter.includes(entry.status) else { return false }
            guard !keyword.isEmpty else { return true }
            return entry.traceId.lowercased().contains(keyword)
                || entry.model.lowercased().contains(keyword)
        }
    }

    private var emptyTitle: String {
        selectedFilter == .error ? "暂无错误" : "暂无请求记录"
    }

    private var emptyDescription: String {
        selectedFilter == .error
            ? "智能体尚未记录到错误请求。"
            : "完成一次对话请求后会显示在这里。"
    }

    /**
     * 触发日志刷新。
     *
     * @author xiangwei
     */
    private func reload() {
        Task {
            await loadLogs()
        }
    }

    /**
     * 加载智能体日志。
     *
     * @author xiangwei
     */
    @MainActor
    private func loadLogs() async {
        entries = AgentLogger.shared.loadEntries()
    }

    /**
     * 清空日志并刷新页面。
     *
     * @author xiangwei
     */
    private func clearLogs() {
        AgentLogger.shared.clear()
        entries = []
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
 * 智能体日志筛选项。
 *
 * @author xiangwei
 */
private enum AgentLogFilter: String, CaseIterable, Identifiable {
    case all
    case error
    case success

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .error: "错误"
        case .success: "成功"
        }
    }

    /**
     * 判断日志状态是否属于当前筛选项。
     *
     * @param status 日志状态
     * @returns 是否包含
     * @author xiangwei
     */
    func includes(_ status: AgentLogStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .error:
            return status == .error
        case .success:
            return status == .success
        }
    }
}

/**
 * 单条智能体请求日志视图。
 *
 * @author xiangwei
 */
private struct AgentLogEntryRow: View {
    let entry: AgentLogEntry
    @State private var isExpanded = false
    @State private var showsRequest = true
    @State private var didCopy = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                detailRow("调用链", entry.traceId)

                HStack(spacing: 10) {
                    Picker("查看", selection: $showsRequest) {
                        Text("请求体").tag(true)
                        Text("响应体").tag(false)
                    }
                    .pickerStyle(.segmented)

                    Button(action: copyDisplayedJSON) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.bibiCaption2Medium)
                            .foregroundStyle(didCopy ? Color.successGreen : Color.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制当前内容")
                }

                ScrollView(.vertical, showsIndicators: false) {
                    Text(displayedJSON)
                        .font(.bibiMonospacedCaption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 300)
            }
            .padding(.top, 10)
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: entry.status == .success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(entry.status == .success ? Color.successGreen : Color.errorRed)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("第 \(entry.roundIndex) 轮")
                            .font(.bibiCaptionSemibold)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(entry.model)
                            .font(.bibiCaption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(entry.durationMS)ms")
                            .font(.bibiMonospacedCaption)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage = entry.errorMessage {
                        Text(errorMessage)
                            .font(.bibiCaption2)
                            .foregroundStyle(Color.errorRed)
                            .lineLimit(2)
                    }

                    Text(entry.timestamp, format: .dateTime.hour().minute().second())
                        .font(.bibiMonospacedCaption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(13)
        .background(Color.contentCardBackground, in: BibiShape.contentCard)
    }

    /**
     * 当前选中查看的 JSON 内容。
     *
     * 请求体或响应体为空时返回占位文本，便于区分数据缺失与渲染问题。
     */
    private var displayedJSON: String {
        let json = showsRequest ? formatJSON(entry.requestJSON) : formatJSON(entry.responseJSON)
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return showsRequest ? "（请求体为空）" : "（响应体为空）"
        }
        return trimmed
    }

    /**
     * 格式化 JSON 字符串为缩进可读形式。
     *
     * @param json 原始 JSON 字符串
     * @returns 格式化后的 JSON 字符串
     * @author xiangwei
     */
    private func formatJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let result = String(data: pretty, encoding: .utf8) else {
            return json
        }
        return result
    }

    /**
     * 将当前选中的请求体或响应体复制到剪贴板并短暂展示勾选反馈。
     *
     * @author xiangwei
     */
    private func copyDisplayedJSON() {
        UIPasteboard.general.string = displayedJSON
        withAnimation(.smooth(duration: 0.25)) {
            didCopy = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.smooth(duration: 0.25)) {
                didCopy = false
            }
        }
    }

    /**
     * 构建明细行。
     *
     * @param title 明细名称
     * @param value 明细内容
     * @returns 明细行视图
     * @author xiangwei
     */
    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.bibiCaption2Medium)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.bibiMonospacedCaption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
