import SwiftUI

/**
 * 记忆条目列表页（用户画像 / 长久记忆共用）。
 *
 * 按类别展示记忆条目，支持新增、编辑与滑动删除。
 *
 * @author xiangwei
 */
struct MemoryItemsView: View {
    /// 展示的记忆类别（userProfile 或 longTerm）
    let category: MemoryCategory

    @Environment(MemoryManager.self) private var memoryManager
    @State private var showAddAlert = false
    @State private var newContent = ""
    @State private var editingItem: MemoryItem?
    @State private var editContent = ""

    /// 页面标题。
    private var title: String {
        category.displayName
    }

    /// 页面副标题说明。
    private var subtitle: String {
        switch category {
        case .userProfile:
            return "关于你的信息，小笔会在对话中参考"
        case .longTerm:
            return "跨会话记住的重要事实，对话中自动积累"
        case .soul:
            return ""
        }
    }

    /// 当前类别的条目列表。
    private var items: [MemoryItem] {
        switch category {
        case .userProfile: return memoryManager.profileItems
        case .longTerm: return memoryManager.longTermItems
        case .soul: return []
        }
    }

    var body: some View {
        ZStack {
            AnimatedBackground()

            List {
                if items.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: emptyIcon)
                                .font(.bibiLargeTitle)
                                .foregroundStyle(.secondary)
                            Text("还没有\(title)")
                                .font(.bibiBodyMedium)
                            Text(emptyDescription)
                                .font(.bibiCaption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section(subtitle) {
                        ForEach(items) { item in
                            itemRow(item)
                        }
                        .onDelete(perform: deleteItems)
                    }
                }

                Section {
                    Button {
                        newContent = ""
                        showAddAlert = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .categoryIconStyle(color: .brandGold)
                            Text("新增\(title)")
                                .font(.bibiBodyMedium)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text(addFooter)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .alert("新增\(title)", isPresented: $showAddAlert) {
            TextField("输入内容", text: $newContent)
            Button("添加") {
                addItem()
            }
            Button("取消", role: .cancel) { }
        }
        .alert("编辑\(title)", isPresented: editingBinding) {
            TextField("内容", text: $editContent)
            Button("保存") {
                saveEdit()
            }
            Button("取消", role: .cancel) { }
        }
    }

    // MARK: - 视图

    /**
     * 构建记忆条目行。
     *
     * @param item 记忆条目
     * @returns 条目行视图
     * @author xiangwei
     */
    private func itemRow(_ item: MemoryItem) -> some View {
        Button {
            editingItem = item
            editContent = item.content
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: category == .longTerm ? "brain" : "person.text.rectangle")
                    .font(.bibiBody)
                    .foregroundStyle(category == .longTerm ? Color.brandGold : Color.accentBlue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.content)
                        .font(.bibiBody)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(relativeDate(item.updatedAt))
                        .font(.bibiCaption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if category == .longTerm {
                    importanceBadge(item.importance)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /**
     * 构建重要度徽标。
     *
     * @param importance 重要度（0~1）
     * @returns 重要度徽标视图
     * @author xiangwei
     */
    private func importanceBadge(_ importance: Double) -> some View {
        let level: Int = importance >= 0.75 ? 3 : (importance >= 0.4 ? 2 : 1)
        return HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < level ? "star.fill" : "star")
                    .font(.bibiCaption)
                    .foregroundStyle(index < level ? Color.brandGold : Color.secondary.opacity(0.4))
            }
        }
    }

    // MARK: - 动作

    /**
     * 新增记忆条目。
     * @author xiangwei
     */
    private func addItem() {
        let content = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        switch category {
        case .userProfile:
            memoryManager.addProfile(content: content)
        case .longTerm:
            memoryManager.addLongTerm(content: content, importance: 0.5)
        case .soul:
            break
        }
        newContent = ""
    }

    /**
     * 保存编辑后的记忆条目。
     * @author xiangwei
     */
    private func saveEdit() {
        guard let editingItem else { return }
        memoryManager.updateItem(editingItem, content: editContent)
        self.editingItem = nil
    }

    /**
     * 删除记忆条目。
     *
     * @param offsets 删除位置索引
     * @author xiangwei
     */
    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = items[index]
            memoryManager.deleteItem(item)
        }
    }

    // MARK: - 辅助

    /// 空状态图标。
    private var emptyIcon: String {
        category == .longTerm ? "brain.head.profile" : "person.crop.circle.badge.questionmark"
    }

    /// 空状态描述。
    private var emptyDescription: String {
        switch category {
        case .userProfile:
            return "手动添加关于你的信息，或在对话中让小笔了解你"
        case .longTerm:
            return "对话达到 4 轮后自动提取，也可手动添加"
        case .soul:
            return ""
        }
    }

    /// 新增按钮下方说明。
    private var addFooter: String {
        category == .longTerm
            ? "重要度由记忆来源决定：明确的「记住」指令最高，自动提取次之。"
            : "画像信息会随对话注入给智能体参考。"
    }

    /// 编辑弹窗绑定。
    private var editingBinding: Binding<Bool> {
        Binding(
            get: { editingItem != nil },
            set: { isPresented in
                if !isPresented { editingItem = nil }
            }
        )
    }

    /**
     * 格式化相对时间。
     *
     * @param date 日期
     * @returns 相对时间文本
     * @author xiangwei
     */
    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
