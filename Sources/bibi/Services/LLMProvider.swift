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
     * @returns 流式事件序列
     */
    static func chat(
        model: String,
        apiKey: String,
        messages: [LLMMessage],
        tools: [[String: Any]]?,
        stream: Bool,
        traceId: String
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let (streamSequence, continuation) = AsyncThrowingStream<LLMStreamEvent, Error>.makeStream()

        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let error = LLMError.apiError("未配置 DeepSeek API Key，请先在设置中填写")
            continuation.finish(throwing: error)
            return streamSequence
        }

        let bodyData: Data
        do {
            var body: [String: Any] = [
                "model": model,
                "messages": messages.map { $0.toJSON() },
                "stream": stream
            ]
            if let tools, !tools.isEmpty {
                body["tools"] = tools.map { ["type": "function", "function": $0] }
            }
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            continuation.finish(throwing: error)
            return streamSequence
        }
        let messageCount = messages.count

        Task {
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
                        if !didReceiveFinishReason {
                            continuation.yield(.finish(reason: "stop"))
                        }
                        break
                    }

                    guard let data = json.data(using: .utf8) else { continue }

                    do {
                        let chunk = try JSONDecoder().decode(StreamChunk.self, from: data)
                        guard let choice = chunk.choices?.first else { continue }

                        if let text = choice.delta?.content, !text.isEmpty {
                            continuation.yield(.chunk(text))
                        }

                        if let toolCalls = choice.delta?.toolCalls {
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
                continuation.finish()
            } catch {
                await AppLogger.shared.log(
                    .error,
                    category: "llm",
                    message: error.localizedDescription,
                    traceId: traceId
                )
                continuation.finish(throwing: error)
            }
        }

        return streamSequence
    }

    /**
     * 读取错误响应正文。
     *
     * @param bytes 响应字节流
     * @returns 限长后的响应文本
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
 */
private struct DeepSeekErrorResponse: Decodable {
    /// 错误内容。
    let error: DeepSeekErrorBody
}

/**
 * DeepSeek 错误详情。
 */
private struct DeepSeekErrorBody: Decodable {
    /// 错误说明。
    let message: String
}
