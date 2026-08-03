import Foundation

/**
 * 技能与 MCP 配置持久化服务。
 *
 * 基于 UserDefaults JSON 编码存储，通过 @Observable 驱动 UI 更新。
 *
 * @author xiangwei
 */
@Observable
final class SkillMCPService {
    private let defaults = UserDefaults.standard
    private let skillsKey = "bibi_skills"
    private let mcpConfigsKey = "bibi_mcp_configs"

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// 已保存的技能列表。
    private(set) var skills: [Skill] = []

    /// 已保存的 MCP 配置列表。
    private(set) var mcpConfigs: [MCPConfig] = []

    /// 单例。
    nonisolated(unsafe) static let shared = SkillMCPService()

    private init() {
        loadSkills()
        loadMCPConfigs()
    }

    // MARK: - 技能管理

    /**
     * 新增或更新技能。
     *
     * @param skill 技能定义
     * @author xiangwei
     */
    func saveSkill(_ skill: Skill) {
        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[index] = skill
        } else {
            skills.append(skill)
        }
        persistSkills()
    }

    /**
     * 删除技能。
     *
     * @param skill 待删除技能
     * @author xiangwei
     */
    func deleteSkill(_ skill: Skill) {
        skills.removeAll { $0.id == skill.id }
        persistSkills()
    }

    /**
     * 获取已启用的技能列表。
     *
     * @returns 已启用技能
     * @author xiangwei
     */
    func enabledSkills() -> [Skill] {
        skills.filter { $0.isEnabled }
    }

    private func loadSkills() {
        guard let data = defaults.data(forKey: skillsKey) else { return }
        skills = (try? decoder.decode([Skill].self, from: data)) ?? []
    }

    private func persistSkills() {
        guard let data = try? encoder.encode(skills) else { return }
        defaults.set(data, forKey: skillsKey)
    }

    // MARK: - MCP 配置管理

    /**
     * 新增或更新 MCP 配置。
     *
     * @param config MCP 配置
     * @author xiangwei
     */
    func saveMCPConfig(_ config: MCPConfig) {
        if let index = mcpConfigs.firstIndex(where: { $0.id == config.id }) {
            mcpConfigs[index] = config
        } else {
            mcpConfigs.append(config)
        }
        persistMCPConfigs()
    }

    /**
     * 删除 MCP 配置。
     *
     * @param config 待删除配置
     * @author xiangwei
     */
    func deleteMCPConfig(_ config: MCPConfig) {
        mcpConfigs.removeAll { $0.id == config.id }
        persistMCPConfigs()
    }

    /**
     * 获取已启用的 MCP 配置列表。
     *
     * @returns 已启用配置
     * @author xiangwei
     */
    func enabledMCPConfigs() -> [MCPConfig] {
        mcpConfigs.filter { $0.isEnabled }
    }

    private func loadMCPConfigs() {
        guard let data = defaults.data(forKey: mcpConfigsKey) else {
            // 首次启动，写入默认 MCP 配置
            mcpConfigs = Self.defaultMCPConfigs
            persistMCPConfigs()
            return
        }
        mcpConfigs = (try? decoder.decode([MCPConfig].self, from: data)) ?? []
    }

    /// 系统默认 MCP 配置。
    private static var defaultMCPConfigs: [MCPConfig] {
        [
            MCPConfig(
                name: "Exa AI",
                description: "Exa AI 网络搜索服务，为智能体提供实时信息检索能力",
                serverURL: "https://mcp.exa.ai/mcp",
                token: "",
                isEnabled: true
            ),
            MCPConfig(
                name: "Context7",
                description: "Context7 文档查询服务，为智能体提供最新库和框架文档",
                serverURL: "https://mcp.context7.com/mcp",
                token: "",
                isEnabled: true
            )
        ]
    }

    private func persistMCPConfigs() {
        guard let data = try? encoder.encode(mcpConfigs) else { return }
        defaults.set(data, forKey: mcpConfigsKey)
    }
}
