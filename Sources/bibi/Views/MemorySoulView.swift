import SwiftUI

/**
 * 灵魂设定页（只读）。
 *
 * 灵魂设定不允许用户手动设置，由对话中星枢通过 manage_memory 工具
 * （add_soul_rule）自动保存行为规则。页面仅展示规则列表，支持滑动删除。
 *
 * @author xiangwei
 */
struct MemorySoulView: View {
    @Environment(MemoryManager.self) private var memoryManager

    var body: some View {
        ZStack {
            AnimatedBackground()

            List {
                if memoryManager.soulRuleItems.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal")
                                .font(.bibiLargeTitle)
                                .foregroundStyle(.secondary)
                            Text("还没有行为规则")
                                .font(.bibiBodyMedium)
                            Text("当你在对话中要求星枢调整说话方式（如\"说话简短点\"）时，规则会在这里自动积累")
                                .font(.bibiCaption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(memoryManager.soulRuleItems) { rule in
                            ruleRow(rule)
                        }
                        .onDelete(perform: deleteRules)
                    } header: {
                        Text("对话中提炼的行为规则（\(memoryManager.soulRuleItems.count) 条）")
                    } footer: {
                        Text("规则由星枢在对话中通过 manage_memory 工具自动保存，可滑动删除。")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("灵魂设定")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // 打开页面时强制重新加载，确保与数据库状态一致
            memoryManager.reload()
        }
    }

    /**
     * 构建规则行视图。
     *
     * @param rule 规则条目
     * @returns 规则行视图
     * @author xiangwei
     */
    private func ruleRow(_ rule: MemoryItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.bibiBody)
                .foregroundStyle(Color.brandGold)

            VStack(alignment: .leading, spacing: 4) {
                Text(rule.content)
                    .font(.bibiBody)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(rule.source.displayName)
                        .font(.bibiCaption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    Text(relativeDate(rule.updatedAt))
                        .font(.bibiCaption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
    }

    /**
     * 删除行为规则。
     *
     * @param offsets 删除位置索引
     * @author xiangwei
     */
    private func deleteRules(at offsets: IndexSet) {
        for index in offsets {
            let rule = memoryManager.soulRuleItems[index]
            memoryManager.deleteItem(rule)
        }
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
