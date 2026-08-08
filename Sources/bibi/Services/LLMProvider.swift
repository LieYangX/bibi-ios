import Foundation

/**
 * 大语言模型流式请求服务。
 *
 * @author xiangwei
 */
final class LLMProvider {
    /// 单次请求超时时间。
    private static let requestTimeout: TimeInterval = 60

    /**
     * 发起大语言模型流式对话。
     *
     * @param model 模型名称
     * @param apiKey 接口密钥
     * @param messages 对话消息
     * @param tools 工具定义
     * @param stream 是否启用流式响应
     * @param traceId 调用链标识
     * @param roundIndex 多轮对话轮次（从 1 开始）
     * @param thinkingEnabled 是否启用思考模式（默认开启）
     * @param reasoningEffort 思考强度（low / high / max，默认 high）
     * @param responseFormat 响应格式（如 ["type": "json_object"]），nil 表示不限制
     * @returns 流式事件序列
     * @author xiangwei
     */
    static func chat(
        model: String,
        apiKey: String,
        messages: [LLMMessage],
        tools: [[String: Any]]?,
        stream: Bool,
        traceId: String,
        roundIndex: Int = 0,
        thinkingEnabled: Bool = true,
        reasoningEffort: String = "high",
        responseFormat: [String: Any]? = nil
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let (streamSequence, continuation) = AsyncThrowingStream<LLMStreamEvent, Error>.makeStream()

        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let error = LLMError.apiError("未配置 DeepSeek API Key，请先在设置中填写")
            continuation.finish(throwing: error)
            return streamSequence
        }

        let bodyData: Data
        let requestJSON: String
        do {
            var body: [String: Any] = [
                "model": model,
                "messages": messages.map { $0.toJSON() },
                "stream": stream,
                "thinking": ["type": thinkingEnabled ? "enabled" : "disabled"],
                "reasoning_effort": reasoningEffort
            ]
            if let tools, !tools.isEmpty {
                body["tools"] = tools.map { ["type": "function", "function": $0] }
            }
            if let responseFormat, !responseFormat.isEmpty {
                body["response_format"] = responseFormat
            }
            bodyData = try JSONSerialization.data(withJSONObject: body)
            requestJSON = String(data: bodyData, encoding: .utf8) ?? "{}"
        } catch {
            continuation.finish(throwing: error)
            return streamSequence
        }
        let messageCount = messages.count
        let startTime = Date()

        Task {
            var responseChunks: [String] = []
            var lastError: String?
            await AppLogger.shared.log(
                .info,
                category: "llm",
                message: "开始请求 DeepSeek 流式接口",
                traceId: traceId,
                metadata: ["model": model, "message_count": "\(messageCount)"]
            )

            do {
                var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
                request.httpMethod = "POST"
                request.timeoutInterval = requestTimeout
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.httpBody = bodyData

                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw LLMError.apiError("服务未返回有效的 HTTP 响应")
                }

                guard httpResponse.statusCode == 200 else {
                    let responseText = try await readErrorBody(from: bytes)
                    let message = apiErrorMessage(from: responseText, statusCode: httpResponse.statusCode)
                    throw LLMError.apiError(message)
                }

                var didReceiveFinishReason = false
                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let json = String(line.dropFirst(6))

                    if json == "[DONE]" {
                        responseChunks.append(json)
                        if !didReceiveFinishReason {
                            continuation.yield(.finish(reason: "stop"))
                        }
                        break
                    }

                    guard let data = json.data(using: .utf8) else { continue }

                    do {
                        let chunk = try JSONDecoder().decode(StreamChunk.self, from: data)
                        guard let choice = chunk.choices?.first else { continue }

                        // 思考模式：推理内容先行输出，与 content 互斥
                        if let reasoning = choice.delta?.reasoningContent, !reasoning.isEmpty {
                            responseChunks.append(json)
                            continuation.yield(.reasoning(reasoning))
                        }

                        if let text = choice.delta?.content, !text.isEmpty {
                            continuation.yield(.chunk(text))
                            responseChunks.append(json)
                        }

                        if let toolCalls = choice.delta?.toolCalls {
                            responseChunks.append(json)
                            for toolCall in toolCalls {
                                continuation.yield(.toolCallDelta(
                                    index: toolCall.index,
                                    id: toolCall.id,
                                    name: toolCall.function?.name,
                                    arguments: toolCall.function?.arguments
                                ))
                            }
                        }

                        if let finishReason = choice.finishReason {
                            didReceiveFinishReason = true
                            continuation.yield(.finish(reason: finishReason))
                        }
                    } catch {
                        await AppLogger.shared.log(
                            .warning,
                            category: "llm",
                            message: "忽略无法解析的流式响应分片",
                            traceId: traceId,
                            metadata: ["payload_length": "\(data.count)"]
                        )
                    }
                }

                await AppLogger.shared.log(
                    .info,
                    category: "llm",
                    message: "DeepSeek 流式响应结束",
                    traceId: traceId
                )

                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                saveAgentLog(
                    traceId: traceId,
                    model: model,
                    roundIndex: roundIndex,
                    status: .success,
                    requestJSON: requestJSON,
                    responseJSON: "[\n" + responseChunks.joined(separator: ",\n") + "\n]",
                    durationMS: duration,
                    errorMessage: nil
                )

                continuation.finish()
            } catch {
                lastError = error.localizedDescription

                await AppLogger.shared.log(
                    .error,
                    category: "llm",
                    message: error.localizedDescription,
                    traceId: traceId
                )

                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                saveAgentLog(
                    traceId: traceId,
                    model: model,
                    roundIndex: roundIndex,
                    status: .error,
                    requestJSON: requestJSON,
                    responseJSON: "[\n" + responseChunks.joined(separator: ",\n") + "\n]",
                    durationMS: duration,
                    errorMessage: lastError
                )

                continuation.finish(throwing: error)
            }
        }

        return streamSequence
    }

    /**
     * 保存智能体请求日志。
     *
     * @author xiangwei
     */
    private static func saveAgentLog(
        traceId: String,
        model: String,
        roundIndex: Int,
        status: AgentLogStatus,
        requestJSON: String,
        responseJSON: String,
        durationMS: Int,
        errorMessage: String?
    ) {
        let entry = AgentLogEntry(
            id: UUID(),
            traceId: traceId,
            timestamp: Date(),
            model: model,
            roundIndex: roundIndex,
            status: status,
            requestJSON: requestJSON,
            responseJSON: responseJSON,
            durationMS: durationMS,
            errorMessage: errorMessage
        )
        AgentLogger.shared.save(entry)
    }

    /**
     * 读取错误响应正文。
     *
     * @param bytes 响应字节流
     * @returns 限长后的响应文本
     * @author xiangwei
     */
    private static func readErrorBody(from bytes: URLSession.AsyncBytes) async throws -> String {
        var result = ""
        for try await line in bytes.lines {
            result += line
            if result.count >= 2_000 {
                break
            }
        }
        return String(result.prefix(2_000))
    }

    /**
     * 提取接口错误信息。
     *
     * @param responseText 响应正文
     * @param statusCode HTTP 状态码
     * @returns 可展示的错误信息
     * @author xiangwei
     */
    private static func apiErrorMessage(from responseText: String, statusCode: Int) -> String {
        guard let data = responseText.data(using: .utf8),
              let response = try? JSONDecoder().decode(DeepSeekErrorResponse.self, from: data) else {
            return "HTTP \(statusCode)"
        }
        return "HTTP \(statusCode): \(response.error.message)"
    }
}

/**
 * DeepSeek 错误响应。
 *
 * @author xiangwei
 */
private struct DeepSeekErrorResponse: Decodable {
    /// 错误内容。
    let error: DeepSeekErrorBody
}

/**
 * DeepSeek 错误详情。
 *
 * @author xiangwei
 */
private struct DeepSeekErrorBody: Decodable {
    /// 错误说明。
    let message: String
}
