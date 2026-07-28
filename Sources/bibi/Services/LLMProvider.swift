import Foundation

final class LLMProvider {
    static func chat(
        model: String, apiKey: String,
        messages: [LLMMessage], tools: [[String: Any]]?, stream: Bool
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let (s, c) = AsyncThrowingStream<LLMStreamEvent, Error>.makeStream()

        // 在 Task 外将非 Sendable 的消息序列化为 Data
        let bodyData: Data
        do {
            var body: [String: Any] = ["model": model, "messages": messages.map { $0.toJSON() }, "stream": stream]
            if let tools, !tools.isEmpty { body["tools"] = tools.map { ["type": "function", "function": $0] } }
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch { c.finish(throwing: error); return s }

        let url = URL(string: "https://api.deepseek.com/chat/completions")!

        Task {
            do {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                req.httpBody = bodyData

                let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                    c.finish(throwing: LLMError.apiError("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")); return
                }

                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let json = String(line.dropFirst(6))
                    if json == "[DONE]" { c.yield(.finish(reason: "stop")); c.finish(); return }
                    guard let data = json.data(using: .utf8),
                          let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                          let choice = chunk.choices?.first else { continue }
                    if let t = choice.delta?.content, !t.isEmpty { c.yield(.chunk(t)) }
                    if let tcs = choice.delta?.toolCalls { for tc in tcs { c.yield(.toolCallDelta(index: tc.index, name: tc.function?.name, arguments: tc.function?.arguments)) } }
                    if let r = choice.finishReason { c.yield(.finish(reason: r)) }
                }
                c.finish()
            } catch { c.finish(throwing: error) }
        }
        return s
    }
}
