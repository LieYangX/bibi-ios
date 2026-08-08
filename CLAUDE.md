# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概况

bibi-ios（笔笔）是 AI 记账助手的 iOS 端。SwiftUI 应用（iOS 26.0+），SPM 包结构（无 xcodeproj）。依赖仅两个三方库：GRDB.swift（SQLite 持久化）和 modelcontextprotocol/swift-sdk（MCP 客户端）。LLM 使用 DeepSeek API，SSE 流式解析与 function calling 均为自实现。

仓库内 `AGENTS.md` 是同类代理指导文件（内容与本文件互补），设计文档在 `doc/` 下。

## 构建与运行（关键）

**源码在 Windows 编辑，WSL 中编译打包**，不能直接在 Windows 上构建。构建工具为 WSL 中的自定义 CLI `xtool`。所有操作在 Windows PowerShell 执行：

```powershell
.\dev.ps1            # 同步 + 构建（最常用）
.\dev.ps1 install    # 同步 + 构建 + 安装到 USB 真机
.\dev.ps1 dev        # 同步 + 构建 + 预览
.\dev.ps1 clean      # 清理 .build 缓存后构建
.\sync.ps1           # 双向同步；to-wsl 推送 / to-win 拉取，-DryRun 预览
```

- WSL 项目路径：`/home/lieyang/ios-project/bibi`，需设置 `USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015`
- `sync.ps1`、`.build`、`xtool/`、`Packages/` 不会被同步，在 WSL 中重新生成
- 项目没有测试目标，验证方式是构建 + 真机安装
- 构建日志/产物会通过 `to-win` 拉回 Windows

## 架构总览

服务依赖图（`bibiApp.swift` 的 `init()` 中完成全部依赖注入，无第三方 DI）：

```
bibiApp (入口，@main)
  ├── DatabaseManager        — GRDB 单例，原始 SQL 迁移（v1~v5）
  ├── ConnectionManager      — Bonjour 发现 + 配对认证 + 心跳，HTTP 走 authenticatedRequest()
  ├── SettingsStore          — UserDefaults + Keychain（API Key 存 Keychain）
  ├── ConversationManager    — 对话 CRUD（GRDB）
  ├── PcToolService          — PC 工具 HTTP 调用客户端（端口 19878）
  ├── LocalToolService       — 本地工具：时间/设备/位置/联系人/日历/健康/待办/定时任务等
  ├── MCPClient              — MCP 协议客户端（HTTP+SSE），工具合并进 PcToolDef 体系
  ├── UserManager            — 本地用户 + PC 远程用户
  ├── MemoryManager          — 智能体记忆（soul/user_profile/long_term 三类）
  ├── VoiceInputManager      — 语音输入
  ├── TaskSchedulerService   — 待办 + 定时任务（单例）
  ├── ProactiveMessageService — 主动消息调度（单例）
  └── AgentService           — LLM 对话核心，多轮 tool calling
        ├── LLMProvider      — DeepSeek SSE 流式请求
        └── ToolCallAccumulator — 流式 tool call 分片累积
```

### 关键设计点

- **多轮 tool calling 循环**：`AgentService.sendMessage()` 内 `while !done` 循环，上限 8 轮（`maximumToolCallRounds`），每次 tool_calls 执行后把结果注入 messages 重新请求 LLM。
- **Tool call 分片累积**：DeepSeek 流式下 tool_calls 按 `index` 分片返回，`ToolCallAccumulator` 按 index 累积 `name` + `arguments` 后再构造完整 `ToolCall`。
- **三类工具统一为 `PcToolDef`**：PC 工具（PcToolService）、本地工具（LocalToolService）、MCP 工具（MCPClient）都映射为 `PcToolDef`，由 `AgentService` 按名字分发执行。
- **PC 连接非必需**：iOS 端可独立跑 LLM 对话，PC 连接后解锁记账工具。`ConnectionManager.state` 变化时 `PcToolService.reset()` 自动清理工具列表。
- **GRDB Record / Model 双层模型**：持久化用 `XxxRecord`（GRDB 类型，蛇形字段映射），UI 层用 `Xxx` 模型，通过 `toModel()` / `from()` 转换。`ChatMessage` 是内存临时模型，持久化转 `ChatMessageRecord`。
- **定时任务是智能体驱动**：`TaskSchedulerService` 前台每 60 秒检查到期任务，通过 `AgentService.sendProactiveMessage(reason:)` 把触发原因交给 AI 决策，AI 用 `manage_todo` / `manage_scheduled_task` 工具配合处理——不是系统通知。重复任务按 daily/weekly/weekdays 规则计算下一次触发。
- **主动消息**：`ProactiveMessageService` 依据 `scenePhase` 前后台状态触发，依赖注入到 AgentService。
- **记忆**：`memory_item` 表按 owner_id + category 索引；`AgentService` 里 `handleRememberInstruction` 拦截"记住…"指令写入记忆，会话结束时提取摘要入库。
- **崩溃追踪**：`CrashBreadcrumbStore` 在关键操作（工具调用）前写面包屑，启动时 `consumePending()` 检测上次中断并记录到 AppLogger。

### 数据库迁移

`DatabaseManager.open()` 内注册 v1~v5 迁移：v1 基础表（local_user/conversation/chat_message_record/app_setting）、v2 agent_log、v3 reasoning_content 列、v4 memory_item、v5 todo_item + scheduled_task（含索引）。新增表或列必须追加新版本迁移，不要改旧迁移。

## UI 开发硬约束

- **只用 SwiftUI 原生组件**，禁止第三方 UI 库；无法直接实现时用原生组件组合。
- **Liquid Glass（iOS 26）只用于导航层**，不做内容层背景：
  - 导航类（ChatTopBar/InputBar/ConnectionBanner/导航按钮）用 `.glassEffect()`
  - 用户消息气泡用纯色 `.userBubbleBackground`；助手气泡/工具卡片/思考指示器用 `.thinMaterial`/`.regularMaterial`
  - 内容层永远不要用 `.glassEffect()`；多个玻璃元素共用一个 `GlassEffectContainer`；`.clipped()` 会破坏玻璃效果，ScrollView 内用 `.overlay` 提出
- **品牌色**：暖金 `#E9A91B`（`Color.brandGold`），只用于标识和少频强调，不铺大面积背景
- **字体/颜色/圆角**：`Font.bibiXxx`（BibiTypography.swift）、语义化 `Color` 扩展（BibiColor.swift / AppTheme.swift）、`BibiShape.contentCard`
- **动画**：消息入场 `.spring(response: 0.38, dampingFraction: 0.84)`，状态切换 `.smooth(duration: 0.25)`
- 背景用 `AnimatedBackground`（MeshGradient），为玻璃导航提供采样层

## 代码规范

- 注释一律中文，JavaDoc 风格（方法/类/重要字段），作者 `xiangwei`；行注释单独占行，禁止尾行注释
- 服务层一律 `@Observable`，不用 `@ObservableObject` / `@Published`
- 单例模式：`nonisolated(unsafe) static let shared`（actor 类型的 `static let` 自带隔离，无需 `nonisolated(unsafe)`，如 `TaskSchedulerService.shared` / `ProactiveMessageService.shared` 是 `@MainActor` 类）
- 路径拼接用 `URL.appending(path:)`（iOS 16+），避免 `appendingPathComponent` 前导斜杠问题
- 所有 HTTP 请求通过 `ConnectionManager.authenticatedRequest()` 构建，自动携带 Bearer token

## 注意事项

- `doc/bibi-ios-详细设计.md` 描述的是**目标设计**，部分细节与代码不一致（如设计稿是 SwiftData，实现是 GRDB；依赖数也不止一个三方库），**代码是最终真相**
- `doc/ios26-liquid-glass.md` 是 Liquid Glass API 速查手册，写玻璃效果前先查
- `.omo/` 是 OpenCode 内部状态目录，不要手动修改或提交
- API Key 通过设置页输入存 Keychain，不硬编码；后台任务需要 Keychain 可访问性迁移（`KeychainHelper.migrateAccessibilityIfNeeded()`，应用启动时调用）
