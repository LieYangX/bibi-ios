# 笔笔 iOS 端 - 详细技术设计

> 版本：v3.0  
> 状态：详细设计（修订）  
> 日期：2026-07-29

---

## 目录

1. [iOS 端技术选型](#1-ios-端技术选型)
2. [智能体功能设计](#2-智能体功能设计)
3. [数据持久化设计](#3-数据持久化设计)
4. [PC 联动与认证设计](#4-pc-联动与认证设计)
5. [UI 排版与交互设计](#5-ui-排版与交互设计)
6. [关键流程图](#6-关键流程图)
7. [文件清单汇总](#7-文件清单汇总)
8. [PC 端接口规范](#8-pc-端接口规范)

---

## 1. iOS 端技术选型

### 1.1 技术栈总览

| 层级 | 选型 | 版本要求 | 说明 |
|------|------|---------|------|
| UI 框架 | SwiftUI | iOS 26+ | 声明式 UI，对齐 Liquid Glass API |
| 架构模式 | MVVM + Service Layer | - | 视图层薄，逻辑抽入 Service |
| 状态管理 | `@Observable` macro | iOS 17+ | 全局单例 + 按需注入 |
| LLM 集成 | DeepSeek API + 自实现 SSE | - | 流式对话 + function calling |
| 数据持久化 | `SwiftData` | iOS 17+ | 对话历史、消息、本地用户、设置项 |
| 密钥存储 | `Keychain` | 原生 | API Key 等敏感信息 |
| 设备发现 | `NetServiceBrowser` | 原生 | Bonjour/mDNS 零配置发现 |
| HTTP 请求 | `URLSession` + async/await | 原生 | 调用 PC 端工具 REST API |
| 图表 | `Swift Charts` | iOS 16+ | 结构化数据渲染 |
| 语音输入 | `SpeechAnalyzer` + `DictationTranscriber` | iOS 26 | 系统级语音识别，完全本地，无时长限制 |
| 音频播放 | `AVAudioPlayer` | 原生 | TTS 语音播报 |
| 动画 | SwiftUI 原生动画 + `MeshGradient` | iOS 18+ | 背景动效、过渡动画 |
| 国际化 | 内置 `zh-Hans` | 原生 | 仅支持简体中文 |

### 1.2 选型理由与替代方案对比

#### LLM 集成：自实现 DeepSeek SSE

调研了 iOS 26 Foundation Models 框架（`LanguageModelSession` + `Tool` 协议），它原生支持 streaming 和 tool calling，但默认绑定 Apple on-device 模型（3B 参数）。通过 `LanguageModel` 协议可接入第三方模型，但适配器工程量大且 on-device 模型在复杂工具调用场景下能力待验证。

| 方案 | 优势 | 劣势 | 结论 |
|------|------|------|------|
| **自实现 DeepSeek SSE** | 模型能力强（PC 端已验证）、不依赖 Apple Intelligence 硬件、与 PC 端调用方式对齐 | 需自行解析 SSE 和 tool call 分片 | ✅ 第一期选用 |
| Foundation Models + SystemLanguageModel | 原生 tool calling、零成本、零延迟 | 3B 模型能力有限、需 A17 Pro+ 设备 | ❌ 未来可选增强 |
| Foundation Models + LanguageModel 协议适配 DeepSeek | 统一 API、原生 tool calling | 适配器工程量大、协议内部细节复杂 | ❌ 中期规划 |

> **通信模式**：iOS 智能体自主运行 LLM 对话，仅当需要查询/操作记账数据时，通过 HTTP 调用 PC 端的工具 API。无需 WebSocket 长连接。

#### 状态管理：@Observable vs ObservableObject

| 方案 | 优势 | 劣势 | 结论 |
|------|------|------|------|
| **@Observable (iOS 17+)** | 简洁、属性级订阅、无需 `objectWillChange` | 最低 iOS 17 | ✅ 选用 |
| ObservableObject | 兼容更早版本 | 冗余模板代码 | ❌ 目标 iOS 26+ 无需 |

#### 数据持久化：SwiftData

iOS 端使用 SwiftData 数据库存储对话历史、消息、本地用户和设置项。不再使用 UserDefaults 存储结构化数据。

| 存储位置 | 用途 |
|----------|------|
| SwiftData | 对话、消息、本地用户、PC 连接记录、设置项 |
| Keychain | DeepSeek API Key、PC 配对 token |
| UserDefaults | 仅存少量非结构化偏好（如上次选中的对话 ID） |

### 1.3 目标部署版本

| 环境 | 版本 |
|------|------|
| 最低部署目标 | iOS 26.0 |
| 适配设备 | 所有支持 iOS 26 的设备（Liquid Glass 和 SpeechAnalyzer 为系统级能力，旧设备静默降级） |

> Liquid Glass 的 `.interactive()` 模式需要 Apple Intelligence 硬件支持（A17 Pro+），不支持时自动降级为标准玻璃效果，不影响功能。

### 1.4 不需要引入的第三方依赖

```
❌ GRDB.swift / SQLite.swift    -> SwiftData 已满足需求
❌ CoreData                     -> SwiftData 更现代
❌ Alamofire / Moya             -> URLSession 足够
❌ Kingfisher / SDWebImage      -> 无图片加载需求
❌ Firebase / API 客户端        -> 无后端服务
❌ Realm                        -> 过度设计
```

---

## 2. 智能体功能设计

### 2.1 架构概览

iOS 端运行自己的 LLM 对话流程，通过自实现 SSE 流式解析和 tool calling 驱动对话。PC 端作为可选的记账工具后端。

```
┌──────────────────────────────────────────────────────────────────┐
│                        iOS 端（自有智能体）                         │
│                                                                  │
│  ┌─────────────┐   ┌──────────────────┐   ┌──────────────────┐  │
│  │ AgentService │──▶│  LLMProvider     │──▶│  SSE 流式解析    │  │
│  │ (对话管理)   │   │ (DeepSeek API)   │   │  + tool call 累积│  │
│  └──────┬──────┘   └──────────────────┘   └──────────────────┘  │
│         │                                                        │
│         │  ┌──────────────────────────────────────────────┐     │
│         │  │ 多轮对话循环 (while !done)                     │     │
│         │  │  1. 发起流式 LLM 请求                          │     │
│         │  │  2. 收集 chunk + 累积 tool_call 分片           │     │
│         │  │  3. finish_reason=tool_calls -> 执行工具       │     │
│         │  │  4. 工具结果加入 messages -> 继续下一轮        │     │
│         │  │  5. finish_reason=stop -> done                │     │
│         │  └──────────────────────────────────────────────┘     │
│         │                                                        │
│         ▼ 需要 PC 记账数据时（可选，PC 已连接）                     │
│  ┌──────────────────┐                                            │
│  │  PcToolService   │── HTTP + Auth ──▶ PC Tool Server          │
│  │  (工具调用客户端) │◀────────── JSON Response                   │
│  └──────────────────┘                                            │
│         │                                                        │
│         ▼                                                        │
│  ┌──────────────────┐                                            │
│  │ ConnectionManager│  (Bonjour 发现 + 配对认证 + 心跳)           │
│  └──────────────────┘                                            │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐                      │
│  │ UserManager      │  │ ConversationMgr  │                      │
│  │ (本地用户管理)    │  │ (SwiftData 持久化)│                      │
│  └──────────────────┘  └──────────────────┘                      │
└──────────────────────────────────────────────────────────────────┘
          ↕ Bonjour 发现 + 配对认证 + HTTP 工具调用
          ▼
┌──────────────────────────────────────────────────────────────────┐
│                     PC 端（记账工具服务器）                         │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Tool Server (HTTP REST API) -- 待实现前置依赖             │   │
│  │  - POST /api/v1/pair          -> 配对码验证 + 签发 token   │   │
│  │  - GET  /api/v1/ping          -> 健康检查                  │   │
│  │  - GET  /api/v1/users         -> user.service              │   │
│  │  - GET  /api/v1/tools         -> toolRegistry.getToolInfos│   │
│  │  - POST /api/v1/tools/<name>  -> 动态路由到工具 execute    │   │
│  └──────────────────────────────────────────────────────────┘   │
│         ↕ 直接调用已有 Agent 工具注册中心                          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  已有: toolRegistry / skillRegistry / orchestrator        │   │
│  │  + service 层: transaction / account / category /         │   │
│  │    budget / statistics / user / session ...               │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

> **核心设计**：iOS 智能体是主功能，不依赖 PC 也能进行 LLM 对话。PC 连接后解锁记账工具能力（查询流水、记账等），是可选增强。

### 2.2 核心消息处理流

iOS 智能体自主完成整个对话周期，采用**多轮对话循环**处理 tool calling：

```
用户提问 "我这个月花了多少钱？"
  │
  ▼
① AgentService.sendMessage()
  ├─ 追加用户消息到 messages[]
  ├─ isProcessing = true
  └─ 进入多轮对话循环
  │
  ▼
② while !done:  发起流式 LLM 请求 (DeepSeek API)
   ├─ 构建 LLMRequest（system prompt + 历史 messages + tools 定义）
   └─ LLMProvider.chat() 返回 AsyncThrowingStream<LLMStreamEvent, Error>
  │
  ▼
③ 遍历流式事件：
   ├─ .chunk(text)  -> 逐块追加到当前 assistant 消息，UI 实时更新
   ├─ .toolCallDelta(index, name?, arguments?) -> 按 index 累积分片
   └─ .finish(reason) -> 判断后续操作
  │
  ▼
④ finish_reason == "tool_calls":
   ├─ 将累积完整的 tool_call 列表加入 messages
   ├─ UI 显示工具卡片（进行中）
   ├─ 逐个执行 PC 工具（HTTP 调用 PcToolService）
   ├─ 工具结果加入 messages（role: tool, content: result JSON）
   ├─ UI 更新工具卡片为完成
   └─ continue 循环 -> 回到 ② 发起下一轮 LLM 请求
  │
  ▼
⑤ finish_reason == "stop":
   ├─ done = true
   └─ isProcessing = false
  │
  ▼
⑥ 持久化对话消息到 SwiftData
```

> **关键修正**：不再使用虚构的 `stream.injectToolResult()`。tool calling 的多轮对话通过**重新发起 LLM 请求**实现--每次工具执行完毕后，把 tool_call 和 tool_result 作为 messages 带入下一轮请求。

### 2.3 连接管理器（ConnectionManager）

PC 端暴露 Bonjour 广播 + HTTP Tool API（含配对认证）：

| 端口 | 服务类型 | 说明 |
|------|---------|------|
| `19877` | Bonjour 广播 | `_bibi-tools._tcp`，用于设备发现 |
| `19878` | HTTP Tool API | 记账工具 REST 端点（含配对认证） |

#### 状态机

```
┌──────────┐  发现 PC   ┌─────────┐  配对成功    ┌───────────┐
│searching │ ────────► │  found  │ ──────────► │ connected │
└──────────┘           └─────────┘             └─────┬─────┘
     ▲                                                │
     │◄────── 心跳失败 / token 失效 ──────────────────│
     │                                                │
     │                                          ┌─────▼─────┐
     └──────────────────────────────────────────│disconnected│
                                               └───────────┘
```

> 连接成功 = Bonjour 发现 + 配对认证通过 + HTTP 健康检查通过。

#### 核心接口

```swift
/// PC 设备信息
struct PCDevice: Identifiable, Hashable {
    let id: String             // Bonjour 服务名
    let name: String           // 设备显示名
    let hostName: String       // IP 地址
    let port: Int              // HTTP API 端口 (19878)
    let bonjourPort: Int       // Bonjour 广播端口 (19877)
    let currentUser: String?   // PC 端当前用户名
    let version: String?       // 协议版本
}

@Observable
final class ConnectionManager {
    private(set) var state: ConnectionState = .searching
    private(set) var discoveredPCs: [PCDevice] = []
    private(set) var connectedPC: PCDevice?
    
    /// 当前配对 token（从 Keychain 读取 / 写入）
    private(set) var authToken: String?
    
    /// Bonjour 发现
    func startSearching()
    func stopSearching()
    
    /// 连接 PC：配对码认证 -> HTTP 健康检查 -> 持久化 token
    /// - Parameters:
    ///   - pc: 目标 PC 设备
    ///   - pairingCode: PC 端显示的 6 位配对码
    func connect(to pc: PCDevice, pairingCode: String) async throws
    
    /// 使用已保存的 token 自动重连（无需配对码）
    func reconnect(to pc: PCDevice) async throws
    
    /// 断开连接
    func disconnect()
    
    /// 心跳检测（每 15 秒 ping + 工具调用失败时即时检测）
    func startHealthCheck()
    func stopHealthCheck()
    
    /// PC 的 HTTP base URL
    var baseURL: URL? {
        connectedPC.map { URL(string: "http://\($0.hostName):\($0.port)")! }
    }
    
    /// 构建带认证 header 的 URLRequest
    func authenticatedRequest(path: String, method: String = "GET") throws -> URLRequest {
        guard let baseURL else { throw PcError.notConnected }
        guard let authToken else { throw PcError.notAuthenticated }
        
        // 使用 appending(path:) 避免 appendingPathComponent 的前导斜杠问题
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}
```

#### Bonjour 发现

```swift
final class BonjourDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    
    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: "_bibi-tools._tcp", inDomain: "local.")
    }
    
    func netServiceDidResolveAddress(_ service: NetService) {
        guard let hostName = service.hostName else { return }
        let txt = service.txtRecordData().flatMap { NetService.dictionary(fromTXTRecord: $0) }
        let pc = PCDevice(
            id: service.name,
            name: service.name.replacingOccurrences(of: "bibi-", with: ""),
            hostName: hostName,
            port: 19878,
            bonjourPort: service.port,
            currentUser: txt?["user"].flatMap { String(data: $0, encoding: .utf8) },
            version: txt?["version"].flatMap { String(data: $0, encoding: .utf8) }
        )
        discoveredPCs.append(pc)
    }
}
```

### 2.4 PC 工具服务（PcToolService）

iOS 端调用 PC 记账能力的核心模块。通过配对认证后的 HTTP 请求调用 PC 端工具。

#### 工具定义（从 PC 端动态获取）

PC 端已有的 `toolRegistry.getToolInfos()` 返回 `AgentToolInfo` 结构，iOS 端通过 `GET /api/v1/tools` 获取并转为 LLM function calling schema。

```swift
/// PC 端工具元信息（对应 PC 端 AgentToolInfo 结构）
struct PcToolDef: Identifiable, Codable {
    let name: String
    let description: String
    let parameters: PcToolParameters
    
    var id: String { name }
    
    /// 转为 DeepSeek function calling 的 JSON Schema
    func toFunctionSchema() -> [String: Any] {
        [
            "name": name,
            "description": description,
            "parameters": parameters.toJSONSchema()
        ]
    }
}

/// 工具参数定义（PC 端 Zod schema 的 JSON 序列化形式）
struct PcToolParameters: Codable {
    /// JSON Schema 格式的参数定义（PC 端 Zod 转 JSON Schema）
    let schema: [String: AnyCodable]
    
    func toJSONSchema() -> [String: Any] {
        schema.mapValues { $0.value }
    }
}

/// 工具执行结果（PC 端返回的 JSON）
struct PcToolResult: Codable {
    let success: Bool
    let data: AnyCodable?
    let error: PcToolError?
}

struct PcToolError: Codable {
    let code: String
    let message: String
}
```

> **类型修正**：`PcToolResult.data` 使用 `AnyCodable`（一个自定义的 `Codable` 包装类型，可编码任意 JSON 值），不再是 `AnyDecodable?` 当字典用的矛盾写法。工具结果转为 `[String: Any]` 时通过 `AnyCodable.value` 显式提取。

#### 工具调用服务（PcToolService）

```swift
@Observable
final class PcToolService {
    /// 当前连接管理器（注入）
    private let connection: ConnectionManager
    
    /// 动态获取的工具列表
    private(set) var availableTools: [PcToolDef] = []
    
    init(connection: ConnectionManager) {
        self.connection = connection
    }
    
    /// 从 PC 端动态获取可用工具列表
    /// GET /api/v1/tools -> { success, data: [PcToolDef] }
    func loadTools() async throws {
        let request = try connection.authenticatedRequest(path: "api/v1/tools")
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ToolListResponse.self, from: data)
        guard response.success, let tools = response.data else {
            throw PcError.toolFailed(response.error?.message ?? "加载工具列表失败")
        }
        availableTools = tools
    }
    
    /// 调用 PC 端的记账工具
    /// - Parameters:
    ///   - toolName: 工具名（如 "query_transactions"）
    ///   - args: 参数字典（包含 user_id）
    /// - Returns: 工具执行结果
    func execute(toolName: String, args: [String: Any]) async throws -> PcToolResult {
        var request = try connection.authenticatedRequest(
            path: "api/v1/tools/\(toolName)",
            method: "POST"
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: args)
        request.timeoutInterval = 30
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let result = try JSONDecoder().decode(PcToolResult.self, from: data)
        return result
    }
    
    /// 健康检查
    func ping() async -> Bool {
        guard let request = try? connection.authenticatedRequest(path: "api/v1/ping") else {
            return false
        }
        guard let (_, httpResp) = try? await URLSession.shared.data(for: request),
              let httpResponse = httpResp as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }
    
    /// 断线时清理（公共方法，供 AgentService 调用）
    func reset() {
        availableTools = []
    }
}

// MARK: - 响应类型

struct ToolListResponse: Decodable {
    let success: Bool
    let data: [PcToolDef]?
    let error: PcToolError?
}

enum PcError: Error, LocalizedError {
    case notConnected
    case notAuthenticated
    case toolFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notConnected: return "未连接到 PC"
        case .notAuthenticated: return "PC 认证失效，请重新配对"
        case .toolFailed(let msg): return "工具执行失败: \(msg)"
        }
    }
}
```

> **修正点**：
> 1. `baseURL` 不再在 `PcToolService` 中重复维护，统一由 `ConnectionManager.authenticatedRequest()` 构建，消除跨类访问 `private var baseURL` 的问题。
> 2. 路径拼接改用 `URL.appending(path:)`（iOS 16+），避免 `appendingPathComponent` 前导斜杠问题。
> 3. `reset()` 是公共方法，`AgentService` 通过它清理状态，不直接赋值 private 属性。
> 4. 所有 HTTP 请求自动携带 `Authorization: Bearer <token>` header。

### 2.5 iOS 自有智能体（AgentService）

iOS 端运行自己的 LLM 对话流程，通过自实现的 SSE 流式解析和 tool calling 多轮循环集成 PC 记账能力。

```swift
@Observable
final class AgentService {
    // 子服务（依赖注入）
    let connection: ConnectionManager
    let conversations: ConversationManager
    let users: UserManager
    let pcTools: PcToolService
    
    // LLM 配置
    private let model = "deepseek-v4-flash"
    
    // 当前对话
    private(set) var messages: [ChatMessage] = []
    private(set) var isProcessing = false
    
    init(connection: ConnectionManager, conversations: ConversationManager,
         users: UserManager, pcTools: PcToolService) {
        self.connection = connection
        self.conversations = conversations
        self.users = users
        self.pcTools = pcTools
    }
    
    // ---- 初始化 ----
    
    func initialize() {
        connection.startSearching()
    }
    
    // ---- 连接 PC 后 ----
    
    func onConnected(to pc: PCDevice) async {
        async let loadUsers: () = users.loadUsers(from: pc)
        async let loadTools: () = pcTools.loadTools()
        _ = await (loadUsers, loadTools)
    }
    
    // ---- 对话（多轮 tool calling 循环）----
    
    /// 发送消息--iOS 端自主调用 LLM，多轮 tool calling 循环
    func sendMessage(_ text: String) async {
        guard let userId = users.currentLocalUser?.pcUserId ?? users.selectedRemoteUser?.id else {
            appendSystemMessage("请先选择用户")
            return
        }
        
        messages.append(.user(text))
        isProcessing = true
        
        // 构建 LLM 上下文消息（会随 tool calling 循环增长）
        var llmMessages = buildLLMMessages(pcConnected: connection.state == .connected)
        let pcConnected = connection.state == .connected
        let toolsAvailable = pcConnected && !pcTools.availableTools.isEmpty
        
        do {
            // 多轮对话循环
            var done = false
            while !done {
                let stream = LLMProvider.chat(
                    model: model,
                    apiKey: KeychainHelper.shared.readAPIKey() ?? "",
                    messages: llmMessages,
                    tools: toolsAvailable ? pcTools.availableTools.map { $0.toFunctionSchema() } : nil,
                    stream: true
                )
                
                var assistantContent = ""
                var toolCallAccumulator = ToolCallAccumulator()
                var finishReason: String?
                
                for try await event in stream {
                    switch event {
                    case .chunk(let text):
                        assistantContent += text
                        updateStreamingAssistant(text)
                        
                    case .toolCallDelta(let index, let name, let arguments):
                        toolCallAccumulator.append(index: index, name: name, arguments: arguments)
                        
                    case .finish(let reason):
                        finishReason = reason
                    }
                }
                
                // 将 assistant 消息加入 LLM 上下文
                llmMessages.append(.assistant(assistantContent))
                
                if finishReason == "tool_calls" {
                    // 处理 tool calls
                    let toolCalls = toolCallAccumulator.buildToolCalls()
                    
                    // 将 tool_calls 加入 LLM 上下文（assistant 消息的 tool_calls 字段）
                    llmMessages.append(.assistantToolCalls(content: assistantContent, toolCalls: toolCalls))
                    
                    for toolCall in toolCalls {
                        // UI 显示工具卡片（进行中）
                        let toolCallMsg = ChatMessage.toolCall(name: toolCall.name, args: toolCall.arguments)
                        messages.append(toolCallMsg)
                        
                        // 再次确认连接状态
                        guard connection.state == .connected else {
                            let failMsg = ChatMessage.toolResult(
                                name: toolCall.name,
                                summary: "PC 已断开连接，无法执行工具"
                            )
                            messages.append(failMsg)
                            llmMessages.append(.tool(
                                toolCallId: toolCall.id,
                                content: "{\"error\": \"PC disconnected\"}"
                            ))
                            continue
                        }
                        
                        // 执行 PC 工具
                        var args = toolCall.arguments
                        args["user_id"] = userId
                        
                        let result = try await pcTools.execute(toolName: toolCall.name, args: args)
                        
                        let summary = result.success
                            ? "\(toolCall.name) 执行成功"
                            : "\(toolCall.name) 执行失败: \(result.error?.message ?? "")"
                        let resultMsg = ChatMessage.toolResult(name: toolCall.name, summary: summary)
                        messages.append(resultMsg)
                        
                        // 工具结果加入 LLM 上下文（role: tool）
                        let resultJSON = String(data: try JSONSerialization.data(
                            withJSONObject: result.data?.value as Any
                        ), encoding: .utf8) ?? "{}"
                        llmMessages.append(.tool(toolCallId: toolCall.id, content: resultJSON))
                    }
                    // 继续循环 -> 发起下一轮 LLM 请求
                } else {
                    // finish_reason == "stop" -> 对话完成
                    done = true
                }
            }
            
            isProcessing = false
            
            // 持久化消息到 SwiftData
            await conversations.saveMessages(messages, for: users.currentLocalUser?.id)
            
        } catch {
            appendSystemMessage(error.localizedDescription)
            isProcessing = false
        }
    }
    
    /// 构建 LLM 消息数组（含系统提示，根据 PC 连接状态自适应）
    private func buildLLMMessages(pcConnected: Bool) -> [LLMMessage] {
        let systemPrompt: String
        let tools = pcConnected ? pcTools.availableTools : []
        
        if pcConnected {
            systemPrompt = """
                你是「小笔」-- 笔笔记账的 AI 助手，运行在 iOS 端。
                当前已连接到 PC 记账服务，你可以查询和操作记账数据。
                
                当用户询问财务数据时，使用 PC 记账工具查询。
                工具执行结果会返回 JSON 数据，用中文总结给用户。
                金额以元为单位展示，例如 128000 分 = ¥1,280.00。
                不要编造数据，只基于工具返回的结果回答。
                
                可用的记账工具已注入到你的 function calling 中。
                """
        } else {
            systemPrompt = """
                你是「小笔」-- 笔笔记账的 AI 助手，运行在 iOS 端。
                当前未连接到 PC 记账服务。
                
                用户如果想查询记账数据或执行记账操作，请告知用户：
                「PC 记账服务未连接。请确保电脑端笔笔已打开，且与手机在同一 WiFi 下。」
                
                你可以回答一般性问题，但无法访问任何记账数据。
                """
        }
        
        var result: [LLMMessage] = [.system(systemPrompt)]
        if let userName = users.currentLocalUser?.displayName {
            result.append(.system("当前操作用户: \(userName)"))
        }
        result += messages.map { $0.toLLMMessage() }
        return result
    }
    
    /// 流式更新助手消息
    private func updateStreamingAssistant(_ text: String) {
        // 追加到最后一条 assistant 消息，或创建新的
    }
    
    /// PC 断线时自动清理工具注入
    func onDisconnected() {
        pcTools.reset()
        connection.disconnect()
    }
    
    private func appendSystemMessage(_ text: String) {
        messages.append(.system(text))
    }
}
```

> **修正点**：
> 1. 删除虚构的 `stream.injectToolResult()`，改用真实的多轮对话循环（`while !done`）。
> 2. API Key 从 Keychain 读取（`KeychainHelper`），不存 UserDefaults。
> 3. `args` 类型统一为 `[String: Any]`，`toolCall.arguments` 也是 `[String: Any]`，消除类型矛盾。
> 4. `onDisconnected()` 调用 `pcTools.reset()` 公共方法，不直接访问 private 属性。

### 2.6 用户管理器（UserManager）

iOS 端有**本地用户体系**（SwiftData 持久化），可关联到 PC 端用户。用户切换不丢失对话历史（对话按本地用户隔离）。

```swift
/// 本地用户（SwiftData 模型）
@Model
final class LocalUser {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var avatarColor: String        // 品牌色 hex
    var createdAt: Date
    var lastActiveAt: Date
    
    // PC 关联（连接 PC 后可绑定）
    var pcUserId: String?          // 关联的 PC 端用户 ID
    var pcDeviceId: String?        // 关联的 PC 设备 ID
    
    @Relationship(deleteRule: .cascade) 
    var conversations: [Conversation] = []
    
    init(displayName: String, avatarColor: String = "#F7BA1E") {
        self.id = UUID()
        self.displayName = displayName
        self.avatarColor = avatarColor
        self.createdAt = Date()
        self.lastActiveAt = Date()
    }
}

/// PC 端用户（从 GET /api/v1/users 获取）
struct RemoteUser: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let color: String
    
    var initial: String { String(name.prefix(1)) }
    var uiColor: Color { Color(hex: color.trimmingCharacters(in: CharacterSet(charactersIn: "#"))) }
}

@Observable
final class UserManager {
    /// 本地用户列表（SwiftData 查询）
    private(set) var localUsers: [LocalUser] = []
    
    /// 当前登录的本地用户
    private(set) var currentLocalUser: LocalUser?
    
    /// PC 端用户列表（连接 PC 后加载）
    private(set) var remoteUsers: [RemoteUser] = []
    
    private(set) var loading = false
    private(set) var error: String?
    
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        Task { await loadLocalUsers() }
    }
    
    /// 加载本地用户列表
    func loadLocalUsers() async {
        let descriptor = FetchDescriptor<LocalUser>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        localUsers = (try? modelContext.fetch(descriptor)) ?? []
        
        // 恢复上次活跃用户
        if let lastUserId = UserDefaults.standard.string(forKey: "last_local_user_id"),
           let user = localUsers.first(where: { $0.id.uuidString == lastUserId }) {
            currentLocalUser = user
        }
    }
    
    /// 新增本地用户（登录）
    func createLocalUser(name: String) async {
        let user = LocalUser(displayName: name)
        modelContext.insert(user)
        try? modelContext.save()
        localUsers.append(user)
        await switchUser(user)
    }
    
    /// 切换本地用户
    func switchUser(_ user: LocalUser) async {
        currentLocalUser = user
        user.lastActiveAt = Date()
        try? modelContext.save()
        UserDefaults.standard.set(user.id.uuidString, forKey: "last_local_user_id")
    }
    
    /// 将本地用户关联到 PC 端用户
    func bindToRemoteUser(_ remoteUser: RemoteUser) {
        currentLocalUser?.pcUserId = remoteUser.id
        try? modelContext.save()
    }
    
    /// 从 PC 端加载远程用户列表
    func loadUsers(from pc: PCDevice) async {
        loading = true
        defer { loading = false }
        
        do {
            let request = try connection.authenticatedRequest(path: "api/v1/users")
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(UsersResponse.self, from: data)
            if response.success {
                remoteUsers = response.data ?? []
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct UsersResponse: Decodable {
    let success: Bool
    let data: [RemoteUser]?
    let error: PcToolError?
}
```

> **设计要点**：
> - iOS 端有独立的本地用户体系，不依赖 PC 也能使用智能体对话。
> - 连接 PC 后，可将本地用户关联到 PC 端用户（`pcUserId`），后续工具调用携带该 ID。
> - 对话按本地用户隔离（见 3.1 数据库设计）。

### 2.7 对话管理器（ConversationManager）

对话和消息使用 SwiftData 持久化，按本地用户隔离。

```swift
/// 对话（SwiftData 模型）
@Model
final class Conversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messageCount: Int
    
    // 归属用户（隔离边界）
    var ownerId: UUID
    
    @Relationship(deleteRule: .cascade)
    var messages: [ChatMessageRecord] = []
    
    init(title: String = "新对话", ownerId: UUID) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.messageCount = 0
        self.ownerId = ownerId
    }
}

/// 消息记录（SwiftData 模型）
@Model
final class ChatMessageRecord {
    @Attribute(.unique) var id: UUID
    var role: String          // user / assistant / tool / system
    var content: String       // 文本内容（markdown）
    var timestamp: Date
    
    // 工具调用相关
    var toolName: String?
    var toolArgsJSON: String?       // JSON 序列化的参数
    var toolStatus: String?         // inProgress / succeeded / failed
    var toolSummary: String?
    
    var conversation: Conversation?
    
    init(role: String, content: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

@Observable
final class ConversationManager {
    private(set) var conversations: [Conversation] = []
    private(set) var currentConversationId: UUID?
    
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// 加载指定用户的对话列表
    func loadConversations(for userId: UUID) {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.ownerId == userId },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        conversations = (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func createConversation(title: String = "新对话", ownerId: UUID) -> Conversation {
        let conversation = Conversation(title: title, ownerId: ownerId)
        modelContext.insert(conversation)
        try? modelContext.save()
        conversations.insert(conversation, at: 0)
        currentConversationId = conversation.id
        return conversation
    }
    
    func deleteConversation(id: UUID) {
        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        modelContext.delete(conversation)
        try? modelContext.save()
        conversations.removeAll { $0.id == id }
    }
    
    func renameConversation(id: UUID, title: String) {
        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        conversation.title = title
        conversation.updatedAt = Date()
        try? modelContext.save()
    }
    
    func switchConversation(id: UUID) {
        currentConversationId = id
    }
    
    /// 保存消息到 SwiftData
    func saveMessages(_ messages: [ChatMessage], for userId: UUID?) async {
        guard let userId, let convId = currentConversationId,
              let conversation = conversations.first(where: { $0.id == convId }) else { return }
        
        for msg in messages {
            let record = ChatMessageRecord(role: msg.role.rawValue, content: msg.text)
            record.toolName = msg.toolName
            record.toolArgsJSON = msg.toolArgs.flatMap { 
                try? JSONSerialization.data(withJSONObject: $0).flatMap { 
                    String(data: $0, encoding: .utf8) 
                } 
            }
            record.toolStatus = msg.toolStatus?.rawValue
            record.toolSummary = msg.toolSummary
            record.conversation = conversation
            modelContext.insert(record)
        }
        
        conversation.messageCount += messages.count
        conversation.updatedAt = Date()
        try? modelContext.save()
    }
}
```

### 2.8 消息模型

```swift
enum MessageRole: String {
    case user, assistant, toolCall, toolResult, system
}

struct ChatMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    var text: String               // 文本内容（markdown）
    let timestamp: Date
    var isStreaming: Bool
    
    // 工具调用
    var toolName: String?
    var toolArgs: [String: Any]?   // 仅 UI 展示用，LLM 交互用 ToolCall 结构
    var toolStatus: ToolCallStatus?
    
    // 工具结果摘要（用于 UI 展示）
    var toolSummary: String?
    
    init(id: UUID = UUID(), role: MessageRole, text: String, 
         timestamp: Date = Date(), isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
    
    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, text: text)
    }
    static func assistant(_ text: String) -> ChatMessage {
        ChatMessage(role: .assistant, text: text, isStreaming: true)
    }
    static func system(_ text: String) -> ChatMessage {
        ChatMessage(role: .system, text: text)
    }
    static func toolCall(name: String, args: [String: Any]) -> ChatMessage {
        var msg = ChatMessage(role: .toolCall, text: "")
        msg.toolName = name
        msg.toolArgs = args
        msg.toolStatus = .inProgress
        return msg
    }
    static func toolResult(name: String, summary: String) -> ChatMessage {
        var msg = ChatMessage(role: .toolResult, text: "")
        msg.toolName = name
        msg.toolSummary = summary
        return msg
    }
}

enum ToolCallStatus: String {
    case inProgress
    case succeeded
    case failed
}
```

### 2.9 LLM 集成方案

#### 流式事件类型

```swift
/// LLM 流式事件
enum LLMStreamEvent {
    case chunk(String)                                    // 文本片段
    case toolCallDelta(index: Int, name: String?, arguments: String?)  // tool call 分片
    case finish(reason: String?)                          // 结束
}
```

#### Tool Call 分片累积器

DeepSeek（兼容 OpenAI 格式）在流式模式下，`tool_calls` 是**分片返回**的：第一个 chunk 给 `index` + `function.name`，后续多个 chunk 只给 `function.arguments` 的片段。必须按 `index` 累积拼接。

```swift
/// 工具调用分片累积器
struct ToolCallAccumulator {
    private var fragments: [Int: ToolCallFragment] = [:]
    
    private struct ToolCallFragment {
        var id: String?
        var name: String?
        var argumentsJSON: String = ""
    }
    
    /// 追加一个分片
    mutating func append(index: Int, name: String?, arguments: String?) {
        if fragments[index] == nil {
            fragments[index] = ToolCallFragment()
        }
        if let name {
            fragments[index]?.name = name
        }
        if let arguments {
            fragments[index]?.argumentsJSON += arguments
        }
    }
    
    /// 构建完整的 tool call 列表
    func buildToolCalls() -> [ToolCall] {
        fragments.sorted { $0.key < $1.key }.compactMap { _, fragment in
            guard let name = fragment.name else { return nil }
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

/// 完整的工具调用
struct ToolCall {
    let id: String
    let name: String
    let arguments: [String: Any]
}
```

#### LLM 消息类型

```swift
/// LLM 消息（用于构建 DeepSeek API 请求体）
enum LLMMessage {
    case system(String)
    case user(String)
    case assistant(String)
    case assistantToolCalls(content: String, toolCalls: [ToolCall])
    case tool(toolCallId: String, content: String)
    
    /// 转为 DeepSeek API 的 JSON 字典
    func toJSON() -> [String: Any] {
        switch self {
        case .system(let text):
            return ["role": "system", "content": text]
        case .user(let text):
            return ["role": "user", "content": text]
        case .assistant(let text):
            return ["role": "assistant", "content": text]
        case .assistantToolCalls(let content, let toolCalls):
            return [
                "role": "assistant",
                "content": content.isEmpty ? nil : content,
                "tool_calls": toolCalls.map { tc in
                    [
                        "id": tc.id,
                        "type": "function",
                        "function": [
                            "name": tc.name,
                            "arguments": (try? String(data: JSONSerialization.data(
                                withJSONObject: tc.arguments
                            ), encoding: .utf8)) ?? "{}"
                        ]
                    ] as [String: Any]
                }
            ] as [String: Any]
        case .tool(let toolCallId, let content):
            return ["role": "tool", "tool_call_id": toolCallId, "content": content]
        }
    }
}
```

#### DeepSeek API 流式调用（SSE 解析）

```swift
/// LLM 流式请求提供者
final class LLMProvider {
    /// 发起流式 LLM 对话
    /// - Parameters:
    ///   - model: 模型名（如 "deepseek-v4-flash"）
    ///   - apiKey: DeepSeek API Key
    ///   - messages: 消息数组（含 system prompt 和历史）
    ///   - tools: function calling 工具定义（JSON Schema 数组），nil 表示不启用工具
    ///   - stream: 是否流式
    /// - Returns: 流式事件 AsyncSequence
    static func chat(
        model: String,
        apiKey: String,
        messages: [LLMMessage],
        tools: [[String: Any]]?,
        stream: Bool
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let url = URL(string: "https://api.deepseek.com/chat/completions")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                
                var body: [String: Any] = [
                    "model": model,
                    "messages": messages.map { $0.toJSON() },
                    "stream": true
                ]
                if let tools, !tools.isEmpty {
                    body["tools"] = tools.map { ["type": "function", "function": $0] }
                }
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                
                // SSE 流式解析
                let (bytes, response) = try await URLSession.shared.bytes(for: req)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    continuation.finish(throwing: LLMError.apiError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"))
                    return
                }
                
                for try await line in bytes.lines {
                    // 解析 SSE: data: {...}
                    guard line.hasPrefix("data: ") else { continue }
                    let jsonString = String(line.dropFirst(6))
                    if jsonString == "[DONE]" {
                        continuation.yield(.finish(reason: "stop"))
                        continuation.finish()
                        return
                    }
                    
                    guard let data = jsonString.data(using: .utf8),
                          let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                          let choice = chunk.choices?.first else { continue }
                    
                    // 文本片段
                    if let text = choice.delta?.content, !text.isEmpty {
                        continuation.yield(.chunk(text))
                    }
                    
                    // tool call 分片（按 index 累积）
                    if let toolCalls = choice.delta?.toolCalls {
                        for tc in toolCalls {
                            continuation.yield(.toolCallDelta(
                                index: tc.index,
                                name: tc.function?.name,
                                arguments: tc.function?.arguments
                            ))
                        }
                    }
                    
                    // 结束信号
                    if let finishReason = choice.finishReason {
                        continuation.yield(.finish(reason: finishReason))
                    }
                }
                
                continuation.finish()
            }
        }
    }
}

// MARK: - SSE 响应类型

struct StreamChunk: Decodable {
    let choices: [StreamChoice]?
}

struct StreamChoice: Decodable {
    let delta: StreamDelta?
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

struct StreamDelta: Decodable {
    let content: String?
    let toolCalls: [StreamToolCall]?
    
    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

struct StreamToolCall: Decodable {
    let index: Int
    let function: StreamToolFunction?
}

struct StreamToolFunction: Decodable {
    let name: String?
    let arguments: String?
}

enum LLMError: Error, LocalizedError {
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "LLM 调用失败: \(msg)"
        }
    }
}
```

> **修正点**：
> 1. 正确实现 tool_call 分片累积（`ToolCallAccumulator` 按 `index` 累积 `name` 和 `arguments`）。
> 2. 多轮对话循环在 `AgentService.sendMessage()` 中用 `while !done` 实现，不再依赖虚构的 `injectToolResult`。
> 3. `LLMProvider.chat` 的 `apiKey` 作为参数显式传入，不再是未定义的闭包变量。
> 4. 处理 SSE 的 `[DONE]` 标记和 HTTP 状态码校验。

---

## 3. 数据持久化设计

### 3.1 SwiftData 模型概览

```
┌─────────────────┐     ┌─────────────────────┐     ┌──────────────────────┐
│   LocalUser     │     │   Conversation      │     │  ChatMessageRecord   │
│─────────────────│     │─────────────────────│     │──────────────────────│
│ id: UUID        │◄───►│ id: UUID            │◄───►│ id: UUID             │
│ displayName     │  1:N│ title: String       │  1:N│ role: String         │
│ avatarColor     │     │ createdAt: Date     │     │ content: String      │
│ createdAt       │     │ updatedAt: Date     │     │ timestamp: Date      │
│ lastActiveAt    │     │ messageCount: Int   │     │ toolName: String?    │
│ pcUserId: String│     │ ownerId: UUID       │     │ toolArgsJSON: String?│
│ pcDeviceId: Str │     └─────────────────────┘     │ toolStatus: String?  │
└─────────────────┘                                 │ toolSummary: String? │
                                                    └──────────────────────┘

┌─────────────────────┐
│   AppSetting        │
│─────────────────────│
│ key: String         │
│ value: String       │
│ updatedAt: Date     │
└─────────────────────┘
```

### 3.2 用户隔离规则

| 维度 | 规则 |
|------|------|
| 对话数据 | `Conversation.ownerId` = `LocalUser.id`，查询时按 ownerId 过滤 |
| 消息数据 | 通过 Conversation 的 cascade 关系自动隔离 |
| PC 用户绑定 | `LocalUser.pcUserId` 关联 PC 端用户，工具调用携带此 ID |
| 切换用户 | 加载新用户的对话列表，当前对话切换不丢失 |
| 删除用户 | 级联删除其所有对话和消息 |

### 3.3 设置项存储

```swift
@Model
final class AppSetting {
    @Attribute(.unique) var key: String
    var value: String
    var updatedAt: Date
    
    init(key: String, value: String) {
        self.key = key
        self.value = value
        self.updatedAt = Date()
    }
}

/// 设置项 Key 枚举
enum SettingKey: String {
    case defaultMode = "default_mode"           // 快速 / 专家
    case autoReconnect = "auto_reconnect"       // 自动重连
    case theme = "theme"                        // 跟随系统 / 浅色 / 深色
    case lastPcDeviceId = "last_pc_device_id"   // 上次连接的 PC
}

class SettingsStore {
    private let modelContext: ModelContext
    
    func get(_ key: SettingKey) -> String? {
        let descriptor = FetchDescriptor<AppSetting>(
            predicate: #Predicate { $0.key == key.rawValue }
        )
        return (try? modelContext.fetch(descriptor))?.first?.value
    }
    
    func set(_ key: SettingKey, value: String) {
        let existing = get(key)
        if let existing {
            // 更新
        } else {
            modelContext.insert(AppSetting(key: key.rawValue, value: value))
        }
        try? modelContext.save()
    }
}
```

### 3.4 Keychain 密钥存储

```swift
/// Keychain 辅助工具（存储 API Key 和配对 token）
final class KeychainHelper {
    static let shared = KeychainHelper()
    
    private let service = "com.bibi.ios"
    
    enum KeychainKey: String {
        case deepseekApiKey = "deepseek_api_key"
        case pcPairingToken = "pc_pairing_token"
    }
    
    func readAPIKey() -> String? {
        read(key: .deepseekApiKey)
    }
    
    func saveAPIKey(_ value: String) {
        save(key: .deepseekApiKey, value: value)
    }
    
    func readPairingToken() -> String? {
        read(key: .pcPairingToken)
    }
    
    func savePairingToken(_ value: String) {
        save(key: .pcPairingToken, value: value)
    }
    
    private func save(key: KeychainKey, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }
    
    private func read(key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        SecItemCopyMatching(query as CFDictionary, &item)
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

---

## 4. PC 联动与认证设计

### 4.1 配对认证流程

PC 端首次被 iOS 发现后，需要**配对码认证**才能建立连接。配对成功后签发 device token，后续请求携带此 token。

```
┌──────────┐                            ┌──────────┐
│  iOS 端  │                            │  PC 端   │
└────┬─────┘                            └────┬─────┘
     │  ① Bonjour 发现 PC                    │
     │◄─────────────────────────────────────│
     │                                      │
     │  ② 用户在 PC 端看到 6 位配对码         │
     │     iOS 端输入配对码                   │
     │                                      │
     │  ③ POST /api/v1/pair                  │
     │     { code: "123456", deviceName }    │
     │──────────────────────────────────────►│
     │                                      │  验证配对码
     │                                      │  生成 device token
     │  ④ { token: "xxx", expiresIn: 0 }     │
     │◄──────────────────────────────────────│
     │                                      │
     │  ⑤ token 存入 Keychain                │
     │                                      │
     │  ⑥ GET /api/v1/ping                   │
     │     Authorization: Bearer xxx         │
     │──────────────────────────────────────►│
     │                                      │  验证 token
     │  ⑦ 200 OK                            │
     │◄──────────────────────────────────────│
     │                                      │
     │  ⑧ connected -- 后续所有请求携带 token │
     │                                      │
```

### 4.2 认证规则

| 规则 | 说明 |
|------|------|
| 配对码有效期 | PC 端生成后 5 分钟内有效，一次性使用 |
| 配对码来源 | PC 端设置页显示，用户手动输入到 iOS 端 |
| Token 存储 | iOS 端存 Keychain，PC 端存内存 + 持久化 |
| Token 验证 | 每次请求 PC 端校验 `Authorization: Bearer <token>` |
| Token 失效 | PC 端重启后 token 仍然有效（持久化），除非用户主动撤销 |
| 无 HTTPS | 局域网内 HTTP 明文传输，认证靠 device token |
| 设备撤销 | PC 端设置页可查看已配对设备列表并撤销 |

### 4.3 心跳与断线检测

| 策略 | 说明 |
|------|------|
| 定时心跳 | 每 15 秒发一次 `GET /api/v1/ping` |
| 即时检测 | 工具调用失败时立即触发 ping 检测 |
| 断线处理 | ping 失败 -> state = .disconnected -> 清空工具列表 -> 指数退避重连 |
| Token 失效 | 收到 401 响应 -> 提示用户重新配对 |

### 4.4 状态恢复

| 场景 | 恢复行为 |
|------|---------|
| App 进入后台再返回 | 工具列表保留缓存，ping 检测连接是否仍然有效 |
| App 被杀死重启 | 从 Keychain 读取 token，自动尝试重连上次的 PC |
| 网络切换 | 连接中断，自动重新搜索同 WiFi PC |
| PC 端关闭 | ping 失败 -> disconnected -> 自动重连 |
| Token 被撤销 | 401 响应 -> 提示重新配对 |

---

## 5. UI 排版与交互设计

### 5.1 页面结构与导航

```
┌─────────────────────────────────────────────────────────────┐
│  LaunchScreen (启动页)                                       │
│     ↓ 选择/创建本地用户                                       │
├─────────────────────────────────────────────────────────────┤
│  ContentView (根视图)                                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  TabView                                                ││
│  │                                                         ││
│  │  Tab 0: AgentChatView (主聊天)                           ││
│  │  Tab 1: ToolsView (记账工具--连接 PC 后动态加载)           ││
│  │  Tab 2: SettingsView (设置--用户/连接/API Key/主题)       ││
│  │                                                         ││
│  │  全局悬浮: ConnectionBanner (连接状态横幅)                ││
│  │            + ConversationList Sheet (从聊天页呼出)        ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### 5.2 Glass 使用规范

根据 `ios26-liquid-glass.md` 的原则：**Liquid Glass 是导航层材质，不做内容层背景**。

| 组件 | 是否用 Glass | 材质选择 | 理由 |
|------|-------------|----------|------|
| TabBar / Toolbar | ✅ 用 | `.glassEffect()` | 导航层，Glass 的本职 |
| InputBar | ✅ 用 | `.glassEffect()` | 导航层输入控件 |
| ConnectionBanner | ✅ 用 | `.glassEffect()` | 导航层状态条 |
| 空状态英雄区按钮 | ✅ 用 | `.buttonStyle(.glassProminent)` | 引导操作 |
| 用户消息气泡 | ❌ 不用 | 暖金纯色背景 | 内容层 |
| 助手消息气泡 | ❌ 不用 | `.thinMaterial` | 内容层 |
| 工具调用卡片 | ❌ 不用 | `.regularMaterial` | 内容层卡片 |
| 工具结果卡片 | ❌ 不用 | `.thinMaterial` | 内容层 |

### 5.3 页面详细设计

#### 5.3.1 AgentChatView - 主聊天页

**布局结构：**

```
┌─────────────────────────────────────────────────────────┐
│  ConnectionBanner (可折叠, glassEffect)                  │
│  [● 已连接 xxx 的 PC]  [历史对话 ▸]                      │  ← 40pt
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │  空对话英雄区 (仅首次或无消息时显示)               │    │
│  │                                                 │    │
│  │           ┌──────────────┐                      │    │
│  │           │  小笔 Logo    │                      │    │
│  │           └──────────────┘                      │    │
│  │                                                 │    │
│  │         你好，{用户名}                           │    │
│  │     我是小笔，已连接到 xxx 的 PC                   │    │
│  │                                                 │    │
│  │      ┌──────┐            ┌──────┐              │    │
│  │      │ 快速 │            │ 专家 │              │    │
│  │      └──────┘            └──────┘              │    │
│  │      (glassProminent 按钮)                      │    │
│  │                                                 │    │
│  │  试试这样问我：                                  │    │
│  │  ┌────────────────────────────────────────┐     │    │
│  │  │ 我这个月花了多少钱？                     │     │    │
│  │  │ 我的总资产有多少？                       │     │    │
│  │  │ 上个月支出最多的是哪类？                  │     │    │
│  │  └────────────────────────────────────────┘     │    │
│  └─────────────────────────────────────────────────┘    │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │  消息流 (有消息时)                                │    │
│  │                                                 │    │
│  │  用户消息 (右对齐, 暖金纯色背景)                    │    │
│  │  助手消息 (左对齐, thinMaterial 背景)              │    │
│  │  工具卡片 (左对齐, regularMaterial, 带边框)        │    │
│  └─────────────────────────────────────────────────┘    │
│                                                         │
├─────────────────────────────────────────────────────────┤
│  InputBar (glassEffect)                                  │
│  [语音]  [给小笔发消息....                    ] [发送]  │  ← 56pt
└─────────────────────────────────────────────────────────┘
```

**交互细节：**

| 交互 | 行为 |
|------|------|
| 点击输入框 | 自动聚焦，弹出键盘 |
| 输入文字 + 点击发送 | 添加用户消息气泡 -> 滚动到底部 -> 显示 thinking 动画 |
| 长按用户/助手消息 | 弹出菜单：复制文本 |
| 点击工具调用卡片 | 展开/折叠参数详情（带动画） |
| 点击「历史对话」 | 从底部弹出 ConversationListView Sheet |
| 语音输入 | 长按语音按钮，SpeechAnalyzer 实时转写，松开发送 |
| 动画 | 消息入场：`.transition(.opacity.combined(with: .move(edge: .bottom)))` |
| Haptic | 发送消息时轻触反馈 `.light()`，工具完成时 `.medium()` |

#### 5.3.2 SettingsView - 设置页

设置页包含：本地用户管理、PC 连接管理、智能体配置、主题。

```
┌──────────────────────────────────────────────────────────────┐
│  设置                                                        │
├──────────────────────────────────────────────────────────────┤
│  ┌── 用户 ───────────────────────────────────────────────┐   │
│  │                                                        │   │
│  │  当前用户: 张三 (暖金色圆点)                             │   │
│  │  已关联 PC 用户: lieyang                                │   │
│  │                                                        │   │
│  │  本地用户列表:                                          │   │
│  │  ● 张三 (当前)                                         │   │
│  │  ○ 李四                                               │   │
│  │  [+ 新增用户]                                          │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌── PC 连接 ────────────────────────────────────────────┐   │
│  │                                                        │   │
│  │  ● 已连接到: lieyang 的 PC                              │   │
│  │  [断开连接]                                             │   │
│  │                                                        │   │
│  │  可用设备:                                              │   │
│  │  ○ lieyang-PC (192.168.1.100)   [配对连接]            │   │
│  │  ○ bibi-PC2 (192.168.1.101)     [配对连接]            │   │
│  │                                                        │   │
│  │  已配对设备:                                            │   │
│  │  ● lieyang-PC                          [撤销]         │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌── 智能体 ─────────────────────────────────────────────┐   │
│  │  API Key: [················] [保存]                    │   │
│  │  默认模式: [快速 ▼]                                     │   │
│  │  自动重连: [开启]                                       │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌── 主题 ───────────────────────────────────────────────┐   │
│  │  ○ 跟随系统    ○ 浅色    ○ 深色                        │   │
│  └────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

**交互细节：**

| 交互 | 行为 |
|------|------|
| 新增用户 | 弹出输入框，创建本地用户并切换 |
| 点击配对连接 | 弹出配对码输入框，验证后建立连接 |
| 切换用户 | 加载该用户的对话列表 |
| API Key 保存 | 存入 Keychain |
| 撤销设备 | 从 PC 端移除设备授权 |

#### 5.3.3 组件详细设计

**MessageBubble - 聊天气泡**

三种角色，三种样式（均不用 glassEffect）：

| 类型 | 对齐 | 背景 | 文字 |
|------|------|------|------|
| 用户消息 | 右对齐 | 暖金纯色 | 白色 |
| 助手消息 | 左对齐 | `.thinMaterial` | 品牌色 |
| 工具卡片 | 左对齐 | `.regularMaterial` + 边框 | 品牌色标题 |

**ThinkingIndicator - 思考动画**

```
┌──────────────────────────────────────────┐
│      ● ● ●                              │  ← 三个脉动圆点（品牌色）
│      小笔正在思考...                       │
└──────────────────────────────────────────┘
```

- 使用 `.pulse` 动画：每个圆点 0.6s 周期，相位差 0.2s
- 接收到第一个 `chunk` 时自动移除

**InputBar - 输入工具栏**

| 元素 | 行为 |
|------|------|
| 文本输入框 | 自动增长（1-5 行），回车发送 |
| 语音按钮 | 长按启动 SpeechAnalyzer 语音识别，松开发送 |
| 发送按钮 | 禁用态（无文字或 isProcessing 时灰色），可点击时高亮品牌色 |
| 动画 | 发送按钮在 isProcessing 时替换为停止按钮 |

**语音输入实现（SpeechAnalyzer + DictationTranscriber）**

```swift
import Speech

@Observable
final class VoiceInputManager {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    
    /// 检查语音识别是否可用
    func checkAvailability() async -> Bool {
        guard let locale = await DictationTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "zh-CN")
        ) else { return false }
        return true
    }
    
    /// 请求语音识别权限
    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    /// 开始语音识别（长按语音按钮时调用）
    func startRecognition() async throws -> AsyncStream<String> {
        let locale = await DictationTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "zh-CN")
        ) ?? Locale(identifier: "zh-CN")
        
        let transcriber = DictationTranscriber(locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        
        self.analyzer = analyzer
        self.transcriber = transcriber
        
        // 启动音频输入（AVAudioEngine）
        let audioStream = startAudioCapture()
        try await analyzer.start(inputSequence: audioStream)
        
        // 返回实时转写流
        return AsyncStream { continuation in
            Task {
                for try await result in transcriber.results {
                    continuation.yield(result.text.description)
                    if result.isFinal {
                        continuation.finish()
                    }
                }
            }
        }
    }
    
    /// 停止语音识别（松开按钮时调用）
    func stopRecognition() {
        analyzer?.finish()
    }
}
```

> **Info.plist 必须配置的权限键：**
> - `NSSpeechRecognitionUsageDescription`: "小笔需要语音识别权限来听懂你的语音指令"
> - `NSMicrophoneUsageDescription`: "小笔需要麦克风权限来接收你的语音输入"

### 5.4 动画与过渡

| 场景 | 动画 | 实现 |
|------|------|------|
| 消息入场 | 从底部滑入 + 淡入 | `.transition(.move(edge: .bottom).combined(with: .opacity))` |
| 工具卡片展开 | 参数区域垂直展开 | `withAnimation(.snappy)` 控制高度 |
| 连接状态变化 | 横幅滑入/滑出 | `.transition(.move(edge: .top).combined(with: .opacity))` |
| 思考指示器 | 三点脉动 | `phaseAnimator` 或 TimelineView |
| 流式文本 | 逐字显现 | ScrollViewReader 自动跟随 |
| 背景动画 | MeshGradient 缓慢流动 | TimelineView + 正弦波驱动网格点 |

### 5.5 响应式适配

| 场景 | 处理 |
|------|------|
| 键盘弹出 | 输入区跟随键盘上移，消息列表自动滚动到最新 |
| 动态岛 | 连接状态显示在 Dynamic Island |
| 后台运行 | HTTP 短连接，无后台保活需求 |
| 深色/浅色模式 | 所有颜色自适应 |
| iPad 横屏 | Split View 支持（聊天 + 工具列表并排）NavigationSplitView |
| VoiceOver | 所有交互元素标注 accessibilityLabel |

---

## 6. 关键流程图

### 6.1 发送消息完整流程（多轮 tool calling）

```
用户输入文字 -> 点击发送
  │
  ▼
① AgentService.sendMessage()
   ├─ 追加用户消息到 messages[] -> UI 立即显示气泡
   └─ isProcessing = true
  │
  ▼
② while !done:  构建 LLM 请求
   ├─ 系统提示词（小笔角色 + 可用 PC 工具定义）
   ├─ 对话历史（messages -> LLMMessage[]）
   └─ 当前用户 ID
  │
  ▼
③ LLMProvider.chat() - 发起流式对话（DeepSeek API SSE）
   │
   ├─ [chunk] "您这个月一共…"        -> UI 逐字显示助手消息
   ├─ [chunk] "支出 ¥4,280…"        -> UI 继续追加
   ├─ [toolCallDelta] index=0, name="query_transactions"
   ├─ [toolCallDelta] index=0, arguments='{"start'
   ├─ [toolCallDelta] index=0, arguments='_date":"2026-07"}'
   ├─ [finish] reason="tool_calls"   -> 累积完整的 tool call
   │  │
   │  ▼
   │  PcToolService.execute("query_transactions", args)
   │  ├─ POST http://pc:19878/api/v1/tools/query_transactions
   │  ├─ Authorization: Bearer <token>
   │  ├─ Body: {user_id, start_date, end_date}
   │  └─ Response: {"success": true, "data": {"total": 32, ...}}
   │  │
   │  ▼
   │  ├─ UI 更新工具卡片 -> 完成（查到 32 笔）
   │  └─ 工具结果加入 llmMessages（role: tool）
   │
   │  continue 循环 -> 回到 ② 发起下一轮 LLM 请求
   │
   ├─ [chunk] "比上月减少了 12%"     -> UI 继续追加
   └─ [finish] reason="stop"        -> done = true
  │
  ▼
④ 持久化消息到 SwiftData
   └─ isProcessing = false
```

### 6.2 首次配对连接流程

```
App 启动
  │
  ▼
① 检查 Keychain: 是否有已保存的 token + 上次 PC 信息
   ├─ 有 -> 直接 ping HTTP 端口（带 token）
   │       ├─ 200 -> 显示已连接
   │       └─ 401 -> token 失效，提示重新配对
   │       └─ 超时 -> 开始 Bonjour 搜索
   └─ 无 -> 开始 Bonjour 搜索
  │
  ▼
② Bonjour 搜索 _bibi-tools._tcp 服务
   ├─ 发现 1 台 -> 提示用户输入配对码
   └─ 发现多台 -> 显示列表让用户选择 + 输入配对码
  │
  ▼
③ POST /api/v1/pair { code, deviceName }
   ├─ 200 -> 获取 device token -> 存入 Keychain
   └─ 400 -> 配对码错误，重新输入
  │
  ▼
④ HTTP 健康检查 -> GET /api/v1/ping（带 token）
   ├─ 200 -> state = .connected
   └─ 401 -> token 无效，回到 ②
  │
  ▼
⑤ 并发加载（HTTP，带 token）：
   ├─ GET /api/v1/users           -> remoteUsers
   └─ GET /api/v1/tools           -> availableTools
  │
  ▼
⑥ 绑定本地用户到 PC 用户（如已配置）
   │
   ▼
⑦ 进入 AgentChatView，横幅显示连接状态
```

### 6.3 用户切换流程

```
用户在设置页点击选择「李四」
  │
  ▼
① UserManager.switchUser(李四)
   ├─ 更新 currentLocalUser
   ├─ 更新 lastActiveAt
   └─ 持久化到 SwiftData + UserDefaults
  │
  ▼
② ConversationManager.loadConversations(for: 李四.id)
   ├─ 加载李四的对话列表
   └─ UI 更新对话列表
  │
  ▼
③ 后续聊天：
   ├─ 构建 LLM 请求时使用李四关联的 pcUserId
   └─ PcToolService 调用携带李四的 pcUserId
  │
  ▼
④ 切换完成（对话历史不丢失，按用户隔离）
```

### 6.4 断线重连流程

```
PC 心跳检测失败（HTTP ping 超时或 401）
  │
  ▼
① ConnectionManager 检测到 -> state = .disconnected
  │
  ▼
② UI 更新 ConnectionBanner 显示断线状态
  │
  ▼
③ PcToolService.reset() 清空工具列表
  │
  ▼
④ 指数退避重连（1s, 2s, 4s, 8s, 16s, 30s 上限）
   ├─ 用已保存的 token 重新 ping
   ├─ 200 -> connected -> 重新加载用户和工具
   ├─ 401 -> token 失效 -> 提示重新配对
   └─ 超时 -> 继续退避或 Bonjour 重新搜索
```

---

## 7. 文件清单汇总

```
Sources/bibi/
├── bibiApp.swift                    -- 入口：初始化 ModelContainer + AgentService + ThemeManager
├── ContentView.swift                -- TabView 根视图（聊天/工具/设置）
│
├── Models/
│   ├── ChatMessage.swift            -- 消息模型、MessageRole、ToolCallStatus
│   ├── ConnectionState.swift        -- 连接状态枚举 + PCDevice 模型
│   ├── LocalUser.swift              -- SwiftData 本地用户模型
│   ├── Conversation.swift           -- SwiftData 对话模型
│   ├── ChatMessageRecord.swift      -- SwiftData 消息记录模型
│   ├── AppSetting.swift             -- SwiftData 设置项模型
│   ├── RemoteUser.swift             -- PC 端用户模型
│   ├── PcToolDef.swift              -- PC 工具定义 + 参数 schema
│   ├── LLMTypes.swift               -- LLM 消息/请求/流式事件类型
│   └── AnyCodable.swift             -- 通用 JSON Codable 包装类型
│
├── Services/
│   ├── AgentService.swift           -- 智能体核心：LLM 对话 + 多轮 tool calling 循环
│   ├── ConnectionManager.swift      -- Bonjour 发现 + 配对认证 + 心跳
│   ├── PcToolService.swift          -- PC 记账工具 HTTP 调用客户端
│   ├── LLMProvider.swift            -- DeepSeek API SSE 流式解析 + tool call 累积
│   ├── ToolCallAccumulator.swift    -- tool call 分片累积器
│   ├── ConversationManager.swift    -- 对话列表管理 + SwiftData 持久化
│   ├── UserManager.swift            -- 本地用户管理 + PC 用户关联
│   ├── SettingsStore.swift          -- 设置项存取（SwiftData）
│   ├── KeychainHelper.swift         -- Keychain 密钥/Token 存储
│   └── VoiceInputManager.swift      -- SpeechAnalyzer 语音输入
│
├── Views/
│   ├── AgentChatView.swift          -- 主聊天页
│   ├── ConversationListView.swift   -- 历史对话列表 Sheet
│   ├── ToolsView.swift              -- PC 记账工具浏览页
│   ├── PairingView.swift            -- PC 配对码输入页
│   └── SettingsView.swift           -- 设置页
│
├── Components/
│   ├── MessageBubble.swift          -- 消息气泡（用户/助手/工具/系统）
│   ├── ToolCallCard.swift           -- 工具调用卡片
│   ├── ThinkingIndicator.swift      -- 思考动画指示器
│   ├── StreamingText.swift          -- 流式文本逐字渲染组件
│   ├── EmptyHeroView.swift          -- 空对话英雄区
│   ├── InputBar.swift               -- 输入工具栏（文本框 + 发送 + 语音）
│   ├── ConnectionBanner.swift       -- 连接状态横幅
│   ├── UserPickerSection.swift      -- 用户选择器列表
│   ├── UserAvatarView.swift         -- 用户头像
│   └── ToolRow.swift                -- 工具描述行
│
├── Theme/
│   ├── BibiColor.swift              -- 暖金色主题颜色
│   └── BibiTypography.swift         -- 字体与排版常量
│
└── Utils/
    ├── Formatters.swift             -- 金额/日期格式化
    └── Extensions.swift             -- Color(hex:) 等扩展
```

---

## 8. PC 端接口规范

PC 端作为记账工具服务器，通过 HTTP REST API 暴露能力。

> **前置依赖**：PC 端 `tool-server` 模块尚未实现，是 iOS 端联动的**前置开发依赖**。PC 端代码位于 `C:\Users\lieyang\open-worker\bibi`，已有完整的 `toolRegistry`、`skillRegistry`、service 层，tool-server 只需在其上新增 HTTP 路由层。

### 8.1 基础设施

| 项目 | 值 |
|------|------|
| Bonjour 服务类型 | `_bibi-tools._tcp` |
| Bonjour TXT | `version=1`, `user={当前用户名}` |
| Bonjour 端口 | `19877` |
| HTTP 端口 | `19878` |
| 服务框架 | Express 或 node:http（PC 端 Electron 主进程内） |
| 认证方式 | Bearer Token（配对码签发的 device token） |
| 传输加密 | 无（局域网 HTTP 明文） |

### 8.2 端点一览

| 方法 | 端点 | 认证 | 说明 |
|------|------|------|------|
| POST | `/api/v1/pair` | 无 | 配对码验证，签发 device token |
| GET | `/api/v1/ping` | Bearer | 健康检查 |
| GET | `/api/v1/users` | Bearer | 获取用户列表（对应 `user.service.listUsers()`） |
| GET | `/api/v1/tools` | Bearer | 动态获取工具列表（对应 `toolRegistry.getToolInfos()`） |
| POST | `/api/v1/tools/<tool-name>` | Bearer | 执行指定工具（路由到 `toolRegistry` 的 execute） |
| GET | `/api/v1/devices` | Bearer | 已配对设备列表 |
| DELETE | `/api/v1/devices/<id>` | Bearer | 撤销设备授权 |

### 8.3 配对认证

#### POST /api/v1/pair

请求：
```json
{
    "code": "123456",
    "deviceName": "lieyang-iPhone"
}
```

响应（成功）：
```json
{
    "success": true,
    "data": {
        "token": "device-uuid-xxx",
        "deviceName": "lieyang-iPhone"
    }
}
```

响应（失败）：
```json
{
    "success": false,
    "error": {
        "code": "INVALID_PAIRING_CODE",
        "message": "配对码错误或已过期"
    }
}
```

### 8.4 工具列表（对齐 PC 端 AgentToolInfo）

iOS 端通过 `GET /api/v1/tools` 获取 PC 端 `toolRegistry.getToolInfos()` 的结果。

PC 端 `AgentToolInfo` 结构：

```typescript
interface AgentToolInfo {
    name: string          // 工具名（如 "queryTransactions"）
    description: string   // 工具描述
    parameters: Record<string, unknown>  // 参数 schema（JSON Schema）
}
```

响应：
```json
{
    "success": true,
    "data": [
        {
            "name": "queryTransactions",
            "description": "按日期范围、类型、分类等条件查询流水记录",
            "parameters": {
                "type": "object",
                "properties": {
                    "start_date": { "type": "string", "description": "开始日期 YYYY-MM-DD" },
                    "end_date": { "type": "string", "description": "结束日期 YYYY-MM-DD" },
                    "type": { "type": "string", "description": "expense/income/transfer/all" },
                    "category_id": { "type": "string", "description": "分类 ID" }
                },
                "required": []
            }
        },
        {
            "name": "queryMonthlySummary",
            "description": "获取指定月份的收支汇总",
            "parameters": {
                "type": "object",
                "properties": {
                    "year": { "type": "number", "description": "年份" },
                    "month": { "type": "number", "description": "月份 1-12" }
                },
                "required": ["year", "month"]
            }
        }
    ]
}
```

> 工具列表对应 PC 端已注册的 5 个工具组：`data-query`、`calculator`、`analysis`、`transaction-write`、`user-todo`。PC 端新增工具时只需在 `toolRegistry` 注册，iOS 端下次 `loadTools()` 自动感知。

### 8.5 工具执行

#### POST /api/v1/tools/<tool-name>

请求：
```json
POST /api/v1/tools/queryTransactions
Authorization: Bearer <device-token>
Content-Type: application/json

{
    "user_id": "uuid-xxx",
    "start_date": "2026-07-01",
    "end_date": "2026-07-29",
    "type": "expense"
}
```

PC 端处理逻辑：
1. 校验 Bearer token
2. 从 `toolRegistry` 查找对应工具
3. 用 `runWithBoundUserId(user_id)` 绑定用户上下文
4. 调用工具的 `execute(args)` 方法
5. 返回结果

响应（成功）：
```json
{
    "success": true,
    "data": {
        "total_count": 32,
        "total_cents": 428000,
        "items": [
            {"id": "txn-1", "amount_cents": 3500, "category_name": "餐饮", "date": "2026-07-28"}
        ]
    }
}
```

响应（失败）：
```json
{
    "success": false,
    "error": {
        "code": "TOOL_EXECUTION_ERROR",
        "message": "用户不存在"
    }
}
```

### 8.6 PC 端新增文件

```
bibi/src/main/tool-server/
├── index.ts                        -- 服务入口（Express 启动 + Bonjour 注册）
├── routes.ts                       -- 路由定义
├── pairing.ts                      -- 配对码生成 + device token 签发/校验
├── handlers.ts                     -- 各端点处理函数（调用 toolRegistry）
├── middleware.ts                   -- 认证中间件 + 错误处理 + 参数校验
└── types.ts                        -- 请求/响应类型

bibi/src/main/app/
└── index.ts                        -- 修改：启动时初始化 Tool Server
```

> PC 端不需要新增数据库表、不需要变更现有 Agent 服务。Tool Server 直接调用已有的 `toolRegistry.createTools()` + `toolRegistry.getToolInfos()`，以及 `user.service`、`session.service`。

### 8.7 认证中间件示例

```typescript
// bibi/src/main/tool-server/middleware.ts
import type { Request, Response, NextFunction } from 'express'
import { validateDeviceToken } from './pairing'

export async function authMiddleware(
    req: Request,
    res: Response,
    next: NextFunction
): Promise<void> {
    // /api/v1/pair 不需要认证
    if (req.path === '/api/v1/pair') {
        next()
        return
    }

    const authHeader = req.headers.authorization
    if (!authHeader?.startsWith('Bearer ')) {
        res.status(401).json({
            success: false,
            error: { code: 'UNAUTHORIZED', message: '缺少认证信息' }
        })
        return
    }

    const token = authHeader.slice(7)
    const isValid = await validateDeviceToken(token)
    if (!isValid) {
        res.status(401).json({
            success: false,
            error: { code: 'TOKEN_INVALID', message: '认证已失效，请重新配对' }
        })
        return
    }

    next()
}
```

---

## 附录：Foundation Models 框架调研结论

iOS 26 Foundation Models 框架原生支持 streaming 和 tool calling（`Tool` 协议 + `@Generable`），但存在以下限制：

1. 默认绑定 Apple on-device 模型（3B 参数），在复杂工具调用场景下能力待验证
2. 需要 Apple Intelligence 硬件（A17 Pro+），非所有 iOS 26 设备都支持
3. 通过 `LanguageModel` 协议可接入 DeepSeek，但适配器工程量大

第一期选择自实现 DeepSeek SSE + tool calling，保留未来统一到 Foundation Models 框架的路径。当 Apple Intelligence 可用时，可选用 on-device 模型处理轻量任务（如闲聊），减少 API 成本。
