import SwiftUI

/**
 * 历史对话列表。
 *
 * 按当前用户过滤，右滑修改，左滑删除。
 *
 * @author xiangwei
 */
struct ConversationListView: View {
    let agent: AgentService
    @Environment(\.dismiss) private var dismiss
    @State private var renameTarget: Conversation?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground()

                if agent.conversations.conversations.isEmpty {
                    ContentUnavailableView(
                        "还没有历史对话",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("完成一次对话后会显示在这里")
                    )
                } else {
                    List {
                        ForEach(agent.conversations.conversations) { conversation in
                            conversationRow(conversation)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        renameTarget = conversation
                                        renameText = conversation.title
                                    } label: {
                                        Image(systemName: "pencil")
                                    }
                                    .tint(.accentBlue)
                                    .accessibilityLabel("修改")
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        agent.deleteConversation(id: conversation.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .accessibilityLabel("删除")
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("对话记录")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("修改标题", isPresented: renameBinding) {
                TextField("对话标题", text: $renameText)
                Button("保存") {
                    if let target = renameTarget, !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        agent.renameConversation(id: target.id, title: renameText.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    renameTarget = nil
                }
                Button("取消", role: .cancel) {
                    renameTarget = nil
                }
            }
        }
    }

    /// 对话行，匹配工具页 ToolRow 风格。
    private func conversationRow(_ conversation: Conversation) -> some View {
        Button {
            agent.openConversation(id: conversation.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.fill")
                    .categoryIconStyle(color: .accentBlue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.bibiBodyMedium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(conversation.messageCount) 条消息")
                        .font(.bibiCaption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(AppFormatters.conversationTime(conversation.updatedAt))
                        .font(.bibiCaption)
                        .foregroundStyle(.secondary)

                    if conversation.id == agent.conversations.currentConversationId {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.brandGold)
                            .font(.caption.weight(.semibold))
                            .accessibilityLabel("当前对话")
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { isPresented in
                if !isPresented {
                    renameTarget = nil
                }
            }
        )
    }
}
