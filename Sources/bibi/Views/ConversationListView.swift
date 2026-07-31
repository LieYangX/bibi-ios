import SwiftUI

/**
 * 历史对话列表。
 *
 * @author xiangwei
 */
struct ConversationListView: View {
    let agent: AgentService
    @Environment(\.dismiss) private var dismiss

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
                        Section {
                            ForEach(agent.conversations.conversations) { conversation in
                                conversationRow(conversation)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            agent.deleteConversation(id: conversation.id)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                            }
                        } footer: {
                            Text("共 \(agent.conversations.conversations.count) 个对话")
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("对话记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

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
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text("\(conversation.messageCount) 条消息")
                        Text("·")
                        Text(conversation.updatedAt, style: .relative)
                    }
                    .font(.bibiCaption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if conversation.id == agent.conversations.currentConversationId {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brandGold)
                        .accessibilityLabel("当前对话")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
