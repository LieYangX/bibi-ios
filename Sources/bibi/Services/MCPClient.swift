import Foundation
import MCP

/**
 * MCP 协议客户端。
 *
 * 基于官方 MCP Swift SDK 实现，支持 HTTP+SSE 传输。
 *
 * @author xiangwei
 */
@MainActor
@Observable
final class MCPClient {
    static let shared = MCPClient()

    private var connections: [UUID: Client] = [:]
    private var toolCache: [String: (tool: PcToolDef, configId: UUID)] = [:]
    private(set) var serverStatuses: [UUID: MCPServerStatus] = [:]

    private var toolToConfig: [String: UUID] {
        var m: [String: UUID] = [:]; for (k, v) in toolCache { m[k] = v.configId }; return m
    }

    private init() {}

    // MARK: - Public

    func loadTools(from configs: [MCPConfig]) async -> [PcToolDef] {
        toolCache.removeAll()
        for (_, client) in connections { await client.disconnect() }
        connections.removeAll()

        var tools: [PcToolDef] = []
        var statuses: [UUID: MCPServerStatus] = [:]

        for c in configs where c.isEnabled {
            guard let url = URL(string: c.serverURL), !c.serverURL.isEmpty else {
                statuses[c.id] = MCPServerStatus(isConnected: false, toolCount: 0, error: "无效地址"); continue
            }
            do {
                let client = Client(name: "bibi-ios", version: "1.0.0")
                let transport = makeTransport(url: url, token: c.token)
                try await client.connect(transport: transport)

                let (sdkTools, _) = try await client.listTools()
                connections[c.id] = client

                let mapped = sdkTools.map { toPcToolDef($0) }
                for t in mapped { toolCache[t.name] = (tool: t, configId: c.id); tools.append(t) }
                statuses[c.id] = MCPServerStatus(isConnected: true, toolCount: mapped.count, error: nil)
            } catch {
                statuses[c.id] = MCPServerStatus(isConnected: false, toolCount: 0, error: error.localizedDescription)
            }
        }
        serverStatuses = statuses
        return tools
    }

    func canExecute(toolName: String) -> Bool { toolCache[toolName] != nil }

    func execute(toolName: String, args: [String: Any]) async throws -> PcToolResult {
        guard let cid = toolToConfig[toolName], let client = connections[cid] else {
            throw MCPError.toolNotFound(toolName)
        }
        let mcpArgs = args.mapValues { MCP.Value.string("\($0)") }
        let (content, isError) = try await client.callTool(name: toolName, arguments: mcpArgs)

        let texts: [String] = content.compactMap {
            if case .text(let t, _, _) = $0 { return t }; return nil
        }
        return PcToolResult(success: !(isError ?? false), data: AnyCodable(texts.joined(separator: "\n").nilIfEmpty ?? "完成"), error: nil)
    }

    // MARK: - Internal

    private func makeTransport(url: URL, token: String) -> HTTPClientTransport {
        HTTPClientTransport(
            endpoint: url,
            streaming: true,
            requestModifier: { @Sendable req in
                var copy = req
                if !token.isEmpty { copy.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                return copy
            }
        )
    }

    private func toPcToolDef(_ tool: MCP.Tool) -> PcToolDef {
        let schema = encodeValueAsDict(tool.inputSchema)
        return PcToolDef(name: tool.name, description: tool.description ?? "", parameters: PcToolParameters(schema: schema))
    }

    /// MCP.Value → [String: AnyCodable]
    private func encodeValueAsDict(_ value: MCP.Value) -> [String: AnyCodable] {
        guard let data = try? JSONEncoder().encode(value),
              let dict = try? JSONDecoder().decode([String: AnyCodable].self, from: data) else { return [:] }
        return dict
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

struct MCPServerStatus: Equatable { var isConnected: Bool; var toolCount: Int; var error: String? }

enum MCPError: Error, LocalizedError {
    case toolNotFound(String), invalidResponse, httpError(Int, String)
    var errorDescription: String? {
        switch self { case .toolNotFound(let n): "未找到: \(n)"; case .invalidResponse: "响应无效"; case .httpError(_, let m): m }
    }
}
