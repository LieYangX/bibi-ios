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
    @Environment(\.dismiss) private var dismiss

    /// 是否展开系统提示词编辑区
    @State private var isPromptExpanded = false

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
