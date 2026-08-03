# bibi-ios AGENTS.md

> 笔笔 iOS 端 — AI 记账助手。编辑在 Windows，构建在 WSL。

## 项目概况

- **部署目标**: iOS 26.0+
- **UI 框架**: SwiftUI（声明式，对齐 Liquid Glass API）
- **状态管理**: `@Observable` macro（iOS 17+）
- **持久化**: GRDB.swift（SQLite，非 SwiftData）
- **密钥存储**: Keychain（API Key / 配对 Token）
- **LLM**: DeepSeek API（自实现 SSE 流式解析 + function calling）
- **PC 发现**: Bonjour（`_bibi-tools._tcp`，端口 19877）
- **PC 通信**: HTTP REST（端口 19878，Bearer token 认证）
- **依赖**: 仅 GRDB.swift 一个三方库，其他全部原生 API
- **构建工具**: `xtool`（自定义 CLI，在 WSL 中运行）

## 目录结构

```
Sources/bibi/
├── bibiApp.swift            # @main 入口，依赖注入
├── ContentView.swift        # 根视图，导航 + 工具面板
├── Components/              # 可复用 UI 组件（气泡、输入栏、状态栏等）
├── Views/                   # 完整页面（聊天、设置、对话列表等）
│   └── Components/          # 页面专属子组件（AnimatedBackground）
├── Models/                  # 数据模型（ChatMessage、AnyCodable 等）
├── Services/                # 业务逻辑层（AgentService、ConnectionManager 等）
├── Theme/                   # 品牌色 + 字体
├── Utils/                   # 工具扩展（Color.init(hex:) 等）
└── Resources/               # 资源文件（非代码，见根目录 Resources/）
```

## 开发与构建

### 构建流程（重要）

**源码在 Windows 编辑，WSL 中编译。** 不能直接在 Windows 上构建。

```powershell
# 同步 + 构建（最常用）
.\dev.ps1

# 同步 + 构建 + 安装到 USB 真机
.\dev.ps1 install

# 清理后构建
.\dev.ps1 clean
```

`dev.ps1` 自动完成：Windows → WSL rsync 同步 → WSL 中 `xtool build` → 产物回传。

### 环境要求

- WSL 中必须设置 `USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015`
- WSL 项目路径: `/home/lieyang/ios-project/bibi`
- `sync.ps1`、`.build`、`xtool/`、`Packages/` 不同步到 WSL
- API Key 通过设置页输入，存入 Keychain，不硬编码

## 架构设计

### 服务层依赖关系

```
bibiApp (入口)
  ├── DatabaseManager      — GRDB 单例，SQLite 持久化
  ├── ConnectionManager    — Bonjour 发现 + 配对认证 + 心跳
  ├── SettingsStore        — UserDefaults 键值存储
  ├── ConversationManager  — 对话 CRUD（GRDB）
  ├── PcToolService        — PC 工具 HTTP 调用客户端
  ├── LocalToolService     — 本地工具（计算器、日期等）
  ├── UserManager          — 本地用户 + PC 远程用户管理
  └── AgentService         — LLM 对话核心，多轮 tool calling
        ├── LLMProvider    — DeepSeek SSE 流式请求
        └── ToolCallAccumulator — 流式 tool call 分片累积
```

### 关键设计点

- **多轮 tool calling 循环**: `AgentService.sendMessage()` 内 `while !done` 循环，每次 tool_calls 后重新发起 LLM 请求，结果注入 messages 继续。
- **Tool call 分片累积**: DeepSeek 流式模式下 tool_calls 按 `index` 分片返回，`ToolCallAccumulator` 按 index 累积 `name` + `arguments` 后再构造成完整 `ToolCall`。
- **PC 连接非必需**: iOS 智能体可独立运行 LLM 对话，PC 连接后解锁记账工具。`ConnectionManager.state` 变化时 `PcToolService.reset()` 自动清理工具列表。
- **数据持久化用 GRDB**: 设计文档描述的是 SwiftData，但实际实现使用 GRDB.swift（`DatabaseManager` 单例，原始 SQL 迁移）。数据模型分两层：GRDB 的 Record 类型（`LocalUserRecord`、`ConversationRecord`）和 UI 层使用的 Model 类型（`LocalUser`、`Conversation`），通过 `toModel()` / `from()` 互相转换。
- **ChatMessage 是临时 UI 模型**: 对话消息在内存中用 `ChatMessage` 表示，持久化时转为 `ChatMessageRecord` 写入 GRDB。

## UI 开发硬约束

### 必须使用原生组件

**写 UI 时只能使用 SwiftUI 原生组件。** 禁止引入第三方 UI 库。

如果原生组件无法直接实现需求，用现有原生组件组合实现，不要自绘底层控件。

### Liquid Glass 使用规则

Glass 是 iOS 26 **导航层**材质，不做内容层背景：

| 组件 | 材质 | 注意事项 |
|------|------|----------|
| ChatTopBar / InputBar / ConnectionBanner / 导航按钮 | `.glassEffect()` | 导航层，Glass 的本职 |
| 空状态引导按钮 / 设置页按钮 | `.buttonStyle(.glass)` 或 `.glassProminent` | 交互控件 |
| 用户消息气泡 | 纯色背景（`.userBubbleBackground`） | 内容层 |
| 助手消息气泡 / 工具卡片 / 思考指示器 | `.thinMaterial` 或 `.regularMaterial` | 内容层半透明 |
| 对话列表行 / 表单 | `List` 默认样式 | Form 中 `.glassEffect()` 无效 |

**关键禁忌**：
- `.clipped()` 会破坏玻璃效果 — 若玻璃元素在 ScrollView 内，用 `.overlay` 提出
- 多个玻璃元素必须共用一个 `GlassEffectContainer`，否则视觉不一致
- 暗色模式下 `.tint()` 饱和度翻倍，需要单独测试
- `.interactive()` 需要 A17 Pro+ 硬件，不支持时自动降级，不影响功能
- 内容层永远不要用 `.glassEffect()`

### 设计风格

- **品牌色**: 暖金 `#E9A91B`（`Color.brandGold`），用于标识和少频强调，不用于大面积背景
- **字体**: 通过 `Font.bibiXxx` 系列静态属性使用（定义在 `BibiTypography.swift`）
- **色彩**: 通过 `Color` 扩展使用语义化颜色（`BibiColor.swift` 和 `AppTheme.swift`）
- **形状**: 卡片圆角用 `BibiShape.contentCard`（ConcentricRectangle，最小 16pt）
- **动画**: 消息入场用 `.spring(response: 0.38, dampingFraction: 0.84)`，状态切换用 `.smooth(duration: 0.25)`
- **背景**: 使用 `AnimatedBackground`（MeshGradient），为玻璃导航提供采样层

## 代码规范

- **注释语言**: 一律使用中文
- **注释格式**: JavaDoc 风格，方法/类/重要字段必须包含注释，作者 `xiangwei`
- **注释位置**: 使用行注释（单独一行），禁止尾行注释
- **状态管理**: 服务层全部使用 `@Observable`，不要用 `@ObservableObject` / `@Published`
- **单例**: 使用 `nonisolated(unsafe) static let shared` 模式（`actor` 类型除外，其 `static let` 自带隔离，不需要 `nonisolated(unsafe)`）
- **文件头**: 不强制 import 声明，按需导入

## 注意事项

- 设计文档 `doc/bibi-ios-详细设计.md` 描述的是**目标设计**，部分细节与实际代码不一致（如 SwiftData vs GRDB），代码为最终真相
- `doc/ios26-liquid-glass.md` 是 Liquid Glass API 速查手册，使用玻璃效果前参考
- `.omo/` 目录用于 OpenCode 内部状态，不要手动修改或提交
- 所有 HTTP 请求通过 `ConnectionManager.authenticatedRequest()` 构建，自动携带 Bearer token
- 路径拼接用 `URL.appending(path:)`（iOS 16+），避免 `appendingPathComponent` 前导斜杠问题
