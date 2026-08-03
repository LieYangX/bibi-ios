import SwiftUI

/**
 * 技能管理页面。
 *
 * 列表展示所有技能，支持新增、编辑、启用/禁用和删除。
 *
 * @author xiangwei
 */
struct SkillsView: View {
    @State private var sheetSkill: Skill?

    var body: some View {
        List {
            if SkillMCPService.shared.skills.isEmpty {
                ContentUnavailableView(
                    "还没有技能",
                    systemImage: "wand.and.stars",
                    description: Text("添加自定义技能以扩展智能体能力")
                )
            } else {
                ForEach(SkillMCPService.shared.skills) { skill in
                    skillRow(skill)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                SkillMCPService.shared.deleteSkill(skill)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.contentBackground.ignoresSafeArea())
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sheetSkill = Skill()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $sheetSkill) { skill in
            SkillEditView(skill: skill, service: SkillMCPService.shared)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    /// 技能列表行。
    private func skillRow(_ skill: Skill) -> some View {
        Button {
            sheetSkill = skill
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .categoryIconStyle(color: skill.isEnabled ? .brandGold : .secondaryText)

                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.name.isEmpty ? "未命名技能" : skill.name)
                        .font(.bibiBodyMedium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(skill.description.isEmpty ? "暂无描述" : skill.description)
                        .font(.bibiCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.bibiCaptionSemibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/**
 * 技能编辑表单。
 *
 * @author xiangwei
 */
private struct SkillEditView: View {
    let skill: Skill
    let service: SkillMCPService
    let isNew: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var desc: String
    @State private var prompt: String
    @State private var isEnabled: Bool

    init(skill: Skill, service: SkillMCPService) {
        self.skill = skill
        self.service = service
        self.isNew = !service.skills.contains(where: { $0.id == skill.id })
        _name = State(initialValue: skill.name)
        _desc = State(initialValue: skill.description)
        _prompt = State(initialValue: skill.prompt)
        _isEnabled = State(initialValue: skill.isEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("技能名称", text: $name)
                    TextField("触发描述", text: $desc)
                    Toggle("启用", isOn: $isEnabled)
                        .tint(.accentBlue)
                }

                Section("提示词") {
                    TextEditor(text: $prompt)
                        .font(.bibiMonospacedCaption)
                        .frame(minHeight: 200, maxHeight: 320)
                        .overlay(alignment: .topLeading) {
                            if prompt.isEmpty {
                                Text("输入智能体调用此技能时使用的系统提示词…")
                                    .font(.bibiMonospacedCaption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section {
                    Text("在描述中说明何时触发此技能，智能体会自动匹配。")
                        .font(.bibiCaption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle(isNew ? "新增技能" : "编辑技能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    /**
     * 保存技能编辑。
     * @author xiangwei
     */
    private func save() {
        var updated = skill
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.prompt = prompt
        updated.isEnabled = isEnabled
        service.saveSkill(updated)
    }
}
