import SwiftUI

/**
 * 历史对话列表 Sheet
 *
 * @author xiangwei
 */
struct ConversationListView: View {
    let agent: AgentService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(agent.conversations.conversations) { conversation in
                    Button(action: {
                        agent.conversations.switchConversation(id: conversation.id)
                        dismiss()
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.title)
                                .font(.bibiBody)
                                .foregroundColor(.primary)

                            Text("\(conversation.messageCount) 条消息")
                                .font(.bibiCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            agent.conversations.deleteConversation(id: conversation.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("历史对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
