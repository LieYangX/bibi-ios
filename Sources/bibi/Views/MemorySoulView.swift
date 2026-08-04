import SwiftUI

/**
 * 灵魂设定编辑页。
 *
 * 编辑智能体「小笔」的自我认知、性格与说话方式，
 * 内容保存后作为 system 消息注入每次对话。
 *
 * @author xiangwei
 */
struct MemorySoulView: View {
    @Environment(MemoryManager.self) private var memoryManager
    @State private var draft = ""
    @State private var showsSavedHint = false

    var body: some View {
        ZStack {
            AnimatedBackground()

            List {
                Section {
                    TextEditor(text: $draft)
                        .font(.bibiBody)
                        .frame(minHeight: 260)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                } header: {
                    Text("小笔的自我认知")
                } footer: {
                    Text("保存在本机，随对话注入到系统提示中。留空则使用默认人格。")
                }

                Section {
                    Button(action: save) {
                        HStack {
                            Spacer()
                            if showsSavedHint {
                                Label("已保存", systemImage: "checkmark")
                            } else {
                                Text("保存灵魂设定")
                            }
                            Spacer()
                        }
                        .font(.bibiBodyMedium)
                        .foregroundStyle(Color.brandGold)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("灵魂设定")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            draft = memoryManager.soulItem?.content ?? ""
        }
        .onDisappear {
            if draft.trimmingCharacters(in: .whitespacesAndNewlines) !=
                (memoryManager.soulItem?.content ?? "") {
                save()
            }
        }
    }

    /**
     * 保存灵魂设定内容。
     * @author xiangwei
     */
    private func save() {
        memoryManager.saveSoul(content: draft)
        showsSavedHint = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            showsSavedHint = false
        }
    }
}
