import Foundation

/**
 * 工具调用分片累积器
 *
 * DeepSeek 流式响应中，tool_calls 按 index 分片返回。
 * 此类负责按 index 累积 name 和 arguments，最终构建完整的 ToolCall 列表。
 *
 * @author xiangwei
 */
struct ToolCallAccumulator {
    /// 分片存储
    private var fragments: [Int: ToolCallFragment] = [:]

    /**
     * 单个工具调用分片
     * @author xiangwei
     */
    private struct ToolCallFragment {
        /// 工具调用 ID
        var id: String?

        /// 工具名
        var name: String?

        /// 参数 JSON 字符串
        var argumentsJSON: String = ""
    }

    /**
     * 追加一个分片
     *
     * @param index 工具调用索引
     * @param id 工具调用标识（可能为空）
     * @param name 工具名（可能为空）
     * @param arguments 参数 JSON 片段（可能为空）
     * @author xiangwei
     */
    mutating func append(index: Int, id: String?, name: String?, arguments: String?) {
        if fragments[index] == nil {
            fragments[index] = ToolCallFragment()
        }

        if let id {
            fragments[index]?.id = id
        }

        if let name = name {
            fragments[index]?.name = name
        }

        if let arguments = arguments {
            fragments[index]?.argumentsJSON += arguments
        }
    }

    /**
     * 构建完整的工具调用列表
     *
     * @returns 已解析的 ToolCall 数组
     * @author xiangwei
     */
    func buildToolCalls() -> [ToolCall] {
        fragments
            .sorted { $0.key < $1.key }
            .compactMap { _, fragment in
                guard let name = fragment.name else {
                    return nil
                }

                let args: [String: Any] = {
                    guard let data = fragment.argumentsJSON.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return [:]
                    }
                    return json
                }()

                return ToolCall(
                    id: fragment.id ?? UUID().uuidString,
                    name: name,
                    arguments: args
                )
            }
    }
}
