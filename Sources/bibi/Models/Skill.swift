import Foundation

/**
 * AI 技能定义。
 *
 * 每个技能包含触发描述和提示词模板，由智能体按需调用。
 *
 * @author xiangwei
 */
struct Skill: Identifiable, Codable, Equatable {
    /// 技能唯一标识
    var id: UUID

    /// 技能名称
    var name: String

    /// 触发描述，用于智能体判断何时激活
    var description: String

    /// 提示词内容
    var prompt: String

    /// 是否启用
    var isEnabled: Bool

    /// 创建时间
    var createdAt: Date

    /**
     * 创建新技能。
     *
     * @param name 技能名称
     * @param description 触发描述
     * @param prompt 提示词内容
     * @param isEnabled 是否启用
     * @author xiangwei
     */
    init(
        name: String = "",
        description: String = "",
        prompt: String = "",
        isEnabled: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.prompt = prompt
        self.isEnabled = isEnabled
        self.createdAt = Date()
    }
}
