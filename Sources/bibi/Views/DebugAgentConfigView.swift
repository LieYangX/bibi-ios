import SwiftUI

/**
 * 调试智能体配置面板。
 *
 * 通过右上角菜单打开，支持启用调试模式并填写自定义系统提示词。
 *
 * @author xiangwei
 */
struct DebugAgentConfigView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ProactiveMessageService.self) private var proactiveService
    @Environment(\.dismiss) private var dismiss

    /// 是否展开系统提示词编辑区
    @State private var isPromptExpanded = false

    /// 手动测试发送状态文案
    @State private var testStatus = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: debugBinding) {
                        HStack(spacing: 8) {
                            Image(systemName: "ladybug")
                                .foregroundStyle(Color.accentBlue)
                            Text("启用调试智能体")
                        }
                        .font(.bibiBodyMedium)
                    }
                    .tint(.accentBlue)
                } footer: {
                    Text("开启后，将使用下方自定义系统提示词替换默认设定，可在智能体日志中查看效果。")
                }

                Section {
                    if settingsStore.isDebugEnabled {
                        DisclosureGroup(isExpanded: $isPromptExpanded) {
                            TextEditor(text: customPromptBinding)
                                .font(.bibiMonospacedCaption)
                                .frame(minHeight: 140, maxHeight: 260)
                                .padding(8)
                                .background(Color.contentCardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.hairline, lineWidth: 0.5)
                                }
                                .overlay(alignment: .topLeading) {
                                    if customPromptBinding.wrappedValue.isEmpty {
                                        Text("在此输入自定义系统提示词，将替换默认提示词。")
                                            .font(.bibiMonospacedCaption)
                                            .foregroundStyle(.tertiary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 16)
                                            .allowsHitTesting(false)
                                    }
                                }
                        } label: {
                            Text("系统提示词")
                                .font(.bibiCaptionSemibold)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("开启调试开关后可填写自定义系统提示词。")
                            .font(.bibiCaption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Section {
                    Button {
                        sendTestProactiveMessage()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(Color.brandGold)
                            Text("发送测试主动消息")
                        }
                        .font(.bibiBodyMedium)
                    }

                    if !testStatus.isEmpty {
                        Text(testStatus)
                            .font(.bibiCaption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("主动消息测试")
                } footer: {
                    Text("立即生成一条主动消息并写入当前会话，用于验证后台生成与通知链路。")
                }
            }
            .navigationTitle("调试智能体")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    /**
     * 手动触发主动消息测试。
     * @author xiangwei
     */
    private func sendTestProactiveMessage() {
        testStatus = "正在生成..."
        Task { @MainActor in
            await proactiveService.triggerNow()
            testStatus = "已触发，请查看会话列表或通知。"
        }
    }

    private var debugBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.isDebugEnabled },
            set: { enabled in
                settingsStore.set(.debugEnabled, value: enabled ? "true" : "false")
                if !enabled {
                    isPromptExpanded = false
                }
            }
        )
    }

    private var customPromptBinding: Binding<String> {
        Binding(
            get: { settingsStore.customSystemPrompt },
            set: { settingsStore.customSystemPrompt = $0 }
        )
    }
}
