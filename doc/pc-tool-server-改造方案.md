# PC 端 Tool Server 改造方案

> 笔笔桌面应用（bibi）适配 iOS 端联动的 HTTP 工具服务器改造  
> 版本：v1.0 · 2026-07-29  
> 前置文档：`bibi-ios/doc/bibi-ios-详细设计.md` 第 8 章

---

## 1. 改造目标

在 PC 端 Electron 主进程内嵌入一个 HTTP Tool Server，将已有的 `toolRegistry` 工具能力通过 REST API 暴露给 iOS 端调用。包含：

- Bonjour 局域网设备广播与发现
- 配对码认证 + device token 签发/校验
- 工具列表动态导出（Zod schema -> JSON Schema）
- 工具执行路由（HTTP 请求 -> toolRegistry.execute）
- 已配对设备管理

**不涉及**：现有桌面端 Agent 功能变更、数据库 schema 变更（复用 settings 表）、UI 大改。

---

## 2. 现有架构分析（可复用部分）

### 2.1 已有且直接复用

| 模块 | 路径 | 复用方式 |
|------|------|----------|
| `toolRegistry` | `src/main/agent/tools/registry.ts` | 调用 `getToolInfos()` 导出工具列表，调用 `createTools()` 执行工具 |
| `skillRegistry` | `src/main/agent/skill-registry.ts` | `getEnabledSkills()` 获取已启用 Skill，过滤工具 |
| `user.service` | `src/main/services/user.service.ts` | `listUsers()` 返回用户列表给 iOS |
| `session.service` | `src/main/services/session.service.ts` | `runWithBoundUserId(userId, fn)` 绑定用户上下文 |
| `setting.service` | `src/main/services/setting.service.ts` | `getSetting/setSetting` 存储配对设备列表 |
| `agent-run-context` | `src/main/agent/agent-run-context.ts` | `runWithAgentContext()` 传递执行上下文 |

### 2.2 工具执行链路分析

现有桌面端工具执行链路：

```
orchestrator.processMessage()
  -> toolRegistry.createTools({ userId, conversationId, emit }, enabledSkillNames)
    -> wrapToolWithUser(registered, runContext)
      -> runWithBoundUserId(runContext.userId, () =>
           runWithAgentContext(runContext, () =>
             raw.execute(args)
           )
         )
```

**关键问题**：`createTools()` 需要一个 `AgentRunContext`（含 `userId`、`conversationId`、`emit`）。iOS HTTP 调用时没有 `conversationId` 和 `emit`（IPC 事件发射器）。

**解决方案**：tool-server 创建一个适配的 `AgentRunContext`：
- `userId`：从 HTTP 请求 body 的 `user_id` 字段获取
- `conversationId`：生成临时 UUID（iOS 工具调用不需要持久化对话到 PC 端）
- `emit`：空操作函数（`async () => {}`），iOS 端不需要 PC 端的流式事件

### 2.3 工具参数 schema 问题

`toolRegistry.getToolInfos()` 当前返回的 `parameters` 是空对象 `{}`：

```typescript
// registry.ts 第 98-104 行
return {
    name,
    description: raw.description ?? '',
    parameters: {}  // ← 空对象，iOS 无法获取参数定义
}
```

**原因**：`AgentToolInfo` 的 `parameters` 字段目前只用于系统提示词展示，不含完整 schema。

**解决方案**：增强 `getToolInfos()`，将 Zod `inputSchema` 转为 JSON Schema 返回。

---

## 3. 改造方案总览

```
bibi/src/main/
├── app/
│   └── bootstrap.ts                    -- 修改：启动时初始化 Tool Server
│
├── tool-server/                        -- 【新增】整个模块
│   ├── index.ts                        -- 服务入口（HTTP 启动 + Bonjour 注册）
│   ├── http-server.ts                  -- Express HTTP 服务器
│   ├── bonjour.ts                      -- Bonjour 广播注册
│   ├── pairing.ts                      -- 配对码生成 + device token 管理
│   ├── auth-middleware.ts              -- Bearer token 认证中间件
│   ├── tool-router.ts                  -- 工具列表导出 + 执行路由
│   ├── schema-serializer.ts            -- Zod schema -> JSON Schema 转换
│   ├── types.ts                        -- 请求/响应类型
│   └── routes/
│       ├── pair.routes.ts              -- POST /api/v1/pair
│       ├── ping.routes.ts              -- GET /api/v1/ping
│       ├── users.routes.ts             -- GET /api/v1/users
│       ├── tools.routes.ts             -- GET /api/v1/tools + POST /api/v1/tools/:name
│       └── devices.routes.ts           -- GET/DELETE /api/v1/devices
│
├── ipc/
│   └── index.ts                        -- 修改：注册 tool-server IPC（可选，用于 PC 端 UI 管理）
│
└── shared/                             -- 共享类型（如需要 IPC 传递）
```

---

## 4. 新增模块详细设计

### 4.1 HTTP Server（http-server.ts）

使用 Express（PC 端已有相关依赖生态），在 Electron 主进程内启动 HTTP 服务。

```typescript
// src/main/tool-server/http-server.ts
import express, { type Request, type Response, type NextFunction } from 'express'
import type { Server } from 'http'
import { authMiddleware } from './auth-middleware'
import { registerPairRoutes } from './routes/pair.routes'
import { registerPingRoutes } from './routes/ping.routes'
import { registerUsersRoutes } from './routes/users.routes'
import { registerToolsRoutes } from './routes/tools.routes'
import { registerDevicesRoutes } from './routes/devices.routes'
import { logger } from '../utils/logger'

const HTTP_PORT = 19878

let server: Server | null = null

/**
 * 启动 HTTP Tool Server
 *
 * @author xiangwei
 */
export function startHttpServer(): Promise<void> {
    return new Promise((resolve) => {
        const app = express()

        // JSON body 解析（限制 1MB 防止大请求体攻击）
        app.use(express.json({ limit: '1mb' }))

        // CORS：允许所有来源（局域网内 iOS 设备访问）
        app.use((req, res, next) => {
            res.header('Access-Control-Allow-Origin', '*')
            res.header('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
            res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
            if (req.method === 'OPTIONS') {
                res.sendStatus(204)
                return
            }
            next()
        })

        // 请求日志
        app.use((req, _res, next) => {
            logger.info('ToolServer', `${req.method} ${req.path}`, {
                ip: req.ip
            })
            next()
        })

        // /api/v1/pair 不需要认证
        registerPairRoutes(app)

        // 其余路由需要认证
        app.use('/api/v1', authMiddleware)
        registerPingRoutes(app)
        registerUsersRoutes(app)
        registerToolsRoutes(app)
        registerDevicesRoutes(app)

        // 统一错误处理
        app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
            logger.error('ToolServer', '请求处理异常', { error: err.message })
            res.status(500).json({
                success: false,
                error: { code: 'INTERNAL_ERROR', message: '服务器内部错误' }
            })
        })

        server = app.listen(HTTP_PORT, () => {
            logger.info('ToolServer', `HTTP Tool Server 已启动`, { port: HTTP_PORT })
            resolve()
        })
    })
}

/**
 * 停止 HTTP Tool Server
 *
 * @author xiangwei
 */
export function stopHttpServer(): Promise<void> {
    return new Promise((resolve) => {
        if (!server) {
            resolve()
            return
        }
        server.close(() => {
            server = null
            logger.info('ToolServer', 'HTTP Tool Server 已停止')
            resolve()
        })
    })
}
```

### 4.2 配对认证服务（pairing.ts）

配对码在 PC 端生成，5 分钟有效，一次性使用。device token 持久化到 settings 表。

```typescript
// src/main/tool-server/pairing.ts
import { randomUUID } from 'crypto'
import { getSetting, setSetting } from '../services/setting.service'
import { logger } from '../utils/logger'

const PAIRING_CODE_TTL_MS = 5 * 60 * 1000  // 5 分钟
const SETTING_KEY = 'paired_devices'

interface PairedDevice {
    token: string
    deviceName: string
    pairedAt: string
    lastSeenAt: string
}

interface PairingCodeEntry {
    code: string
    expiresAt: number
    used: boolean
}

let currentPairingCode: PairingCodeEntry | null = null

/**
 * 生成 6 位配对码
 * 同一时刻只有一个有效配对码，重复生成会覆盖旧的
 *
 * @returns 6 位数字配对码
 * @author xiangwei
 */
export function generatePairingCode(): string {
    const code = String(Math.floor(100000 + Math.random() * 900000))
    currentPairingCode = {
        code,
        expiresAt: Date.now() + PAIRING_CODE_TTL_MS,
        used: false
    }
    logger.info('ToolServer', '配对码已生成', { expiresIn: PAIRING_CODE_TTL_MS })
    return code
}

/**
 * 验证配对码并签发 device token
 * 配对码验证通过后立即标记为已使用，不可重复使用
 *
 * @param code 用户输入的配对码
 * @param deviceName iOS 设备名
 * @returns device token
 * @author xiangwei
 */
export async function verifyPairingCode(
    code: string,
    deviceName: string
): Promise<string> {
    if (!currentPairingCode) {
        throw new Error('未生成配对码，请先在 PC 端发起配对')
    }
    if (currentPairingCode.used) {
        throw new Error('配对码已使用，请重新生成')
    }
    if (Date.now() > currentPairingCode.expiresAt) {
        throw new Error('配对码已过期，请重新生成')
    }
    if (currentPairingCode.code !== code) {
        throw new Error('配对码错误')
    }

    // 标记已使用
    currentPairingCode.used = true

    // 签发 token
    const token = randomUUID()
    const device: PairedDevice = {
        token,
        deviceName,
        pairedAt: new Date().toISOString(),
        lastSeenAt: new Date().toISOString()
    }

    // 持久化到 settings 表
    const existing = (await getSetting<PairedDevice[]>(SETTING_KEY)) ?? []
    existing.push(device)
    await setSetting(SETTING_KEY, existing)

    logger.info('ToolServer', '设备配对成功', { deviceName, token: token.slice(0, 8) + '...' })
    return token
}

/**
 * 校验 device token 是否有效
 *
 * @param token 设备 token
 * @returns 是否有效
 * @author xiangwei
 */
export async function validateDeviceToken(token: string): Promise<boolean> {
    const devices = (await getSetting<PairedDevice[]>(SETTING_KEY)) ?? []
    const device = devices.find((d) => d.token === token)
    if (!device) return false

    // 更新最后活跃时间
    device.lastSeenAt = new Date().toISOString()
    await setSetting(SETTING_KEY, devices)
    return true
}

/**
 * 获取已配对设备列表
 *
 * @returns 已配对设备列表
 * @author xiangwei
 */
export async function listPairedDevices(): Promise<PairedDevice[]> {
    return (await getSetting<PairedDevice[]>(SETTING_KEY)) ?? []
}

/**
 * 撤销设备配对
 *
 * @param token 设备 token
 * @author xiangwei
 */
export async function revokeDevice(token: string): Promise<void> {
    const devices = (await getSetting<PairedDevice[]>(SETTING_KEY)) ?? []
    const filtered = devices.filter((d) => d.token !== token)
    await setSetting(SETTING_KEY, filtered)
    logger.info('ToolServer', '设备已撤销', { token: token.slice(0, 8) + '...' })
}
```

### 4.3 认证中间件（auth-middleware.ts）

```typescript
// src/main/tool-server/auth-middleware.ts
import type { Request, Response, NextFunction } from 'express'
import { validateDeviceToken } from './pairing'

/**
 * Bearer Token 认证中间件
 * /api/v1/pair 路由跳过认证
 *
 * @author xiangwei
 */
export async function authMiddleware(
    req: Request,
    res: Response,
    next: NextFunction
): Promise<void> {
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

### 4.4 Schema 序列化（schema-serializer.ts）

将 PC 端工具的 Zod `inputSchema` 转换为 JSON Schema，供 iOS 端构建 function calling 参数。

```typescript
// src/main/tool-server/schema-serializer.ts
import type { Tool } from 'ai'
import { zodToJsonSchema } from 'zod-to-json-schema'
import { logger } from '../utils/logger'

/**
 * 将 AI SDK Tool 的 Zod inputSchema 转为 JSON Schema
 *
 * @param tool AI SDK 工具对象
 * @returns JSON Schema 对象，转换失败时返回空 schema
 * @author xiangwei
 */
export function toolInputSchemaToJson(tool: Tool): Record<string, unknown> {
    try {
        // AI SDK 的 tool 对象有 inputSchema 属性（Zod schema）
        const rawTool = tool as Tool & { inputSchema?: unknown }
        if (!rawTool.inputSchema) {
            return { type: 'object', properties: {} }
        }

        // 使用 zod-to-json-schema 转换
        const jsonSchema = zodToJsonSchema(rawTool.inputSchema, {
            target: 'openAi',  // OpenAI 兼容格式（DeepSeek 也用此格式）
            $refStrategy: 'none'
        })

        // 移除 $schema 字段（LLM 不需要）
        const { $schema, ...cleanSchema } = jsonSchema as Record<string, unknown>
        return cleanSchema
    } catch (error) {
        logger.warn('ToolServer', 'Zod schema 转 JSON Schema 失败', { error })
        return { type: 'object', properties: {} }
    }
}
```

> **新增依赖**：`zod-to-json-schema`（npm 包，将 Zod schema 转为标准 JSON Schema）。

### 4.5 工具路由（tool-router.ts）

核心模块：导出工具列表 + 路由工具执行。

```typescript
// src/main/tool-server/tool-router.ts
import { randomUUID } from 'crypto'
import type { Tool } from 'ai'
import { toolRegistry } from '../agent/tools/registry'
import { skillRegistry } from '../agent/skill-registry'
import { runWithBoundUserId } from '../services/session.service'
import { runWithAgentContext, type AgentRunContext } from '../agent/agent-run-context'
import { toolInputSchemaToJson } from './schema-serializer'
import { logger } from '../utils/logger'
import { summarizeLogValue } from '../utils/log-sanitizer'

interface ToolInfo {
    name: string
    description: string
    parameters: Record<string, unknown>
}

/**
 * 导出所有已启用工具的元信息（含 JSON Schema 参数定义）
 *
 * @returns 工具信息列表
 * @author xiangwei
 */
export function exportToolInfos(): ToolInfo[] {
    const enabledSkills = skillRegistry.getEnabledSkills()
    const enabledSkillNames = new Set(enabledSkills.map((s) => s.meta.name))

    // 获取所有已注册工具
    const registeredTools = (toolRegistry as unknown as {
        registeredTools: Array<{ name: string; group: string; tool: Tool }>
    }).registeredTools

    // 按 Skill 启停状态过滤
    const filtered = registeredTools.filter((r) => enabledSkillNames.has(r.group))

    return filtered.map(({ name, tool }) => ({
        name,
        description: (tool as Tool & { description?: string }).description ?? '',
        parameters: toolInputSchemaToJson(tool)
    }))
}

/**
 * 执行指定工具
 *
 * @param toolName 工具名
 * @param args 参数（含 user_id）
 * @returns 工具执行结果
 * @author xiangwei
 */
export async function executeTool(
    toolName: string,
    args: Record<string, unknown>
): Promise<unknown> {
    const { user_id: userId, ...toolArgs } = args

    if (!userId || typeof userId !== 'string') {
        throw new Error('缺少 user_id 参数')
    }

    // 构建适配的 AgentRunContext
    // iOS 工具调用不需要 conversationId 和 emit（无流式事件推送）
    const runContext: AgentRunContext = {
        userId,
        conversationId: randomUUID(),
        emit: async () => {}  // 空操作，iOS 不接收 PC 端事件
    }

    // 获取已启用工具
    const enabledSkills = skillRegistry.getEnabledSkills()
    const enabledSkillNames = new Set(enabledSkills.map((s) => s.meta.name))
    const tools = toolRegistry.createTools(runContext, enabledSkillNames)

    const tool = tools[toolName]
    if (!tool) {
        throw new Error(`工具 "${toolName}" 不存在或未启用`)
    }

    const startedAt = Date.now()
    logger.info('ToolServer', '工具调用开始', {
        toolName,
        arguments: summarizeLogValue(toolArgs)
    })

    try {
        // 工具执行已在 createTools -> wrapToolWithUser 中绑定了 userId 和 context
        // 这里直接调用 execute 即可
        const rawTool = tool as Tool & {
            execute: (input: Record<string, unknown>) => Promise<unknown>
        }
        const result = await rawTool.execute(toolArgs)

        logger.info('ToolServer', '工具调用完成', {
            toolName,
            durationMs: Date.now() - startedAt,
            result: summarizeLogValue(result)
        })

        return result
    } catch (error) {
        logger.error('ToolServer', '工具调用失败', {
            toolName,
            durationMs: Date.now() - startedAt,
            error
        })
        throw error
    }
}
```

### 4.6 路由注册

#### 配对路由（pair.routes.ts）

```typescript
// src/main/tool-server/routes/pair.routes.ts
import type { Express } from 'express'
import { verifyPairingCode } from '../pairing'

interface PairRequest {
    code: string
    deviceName: string
}

export function registerPairRoutes(app: Express): void {
    app.post('/api/v1/pair', async (req, res) => {
        try {
            const { code, deviceName } = req.body as PairRequest
            if (!code || !deviceName) {
                res.status(400).json({
                    success: false,
                    error: { code: 'INVALID_PARAMS', message: '缺少 code 或 deviceName' }
                })
                return
            }

            const token = await verifyPairingCode(code, deviceName)
            res.json({
                success: true,
                data: { token, deviceName }
            })
        } catch (error) {
            res.status(400).json({
                success: false,
                error: {
                    code: 'PAIRING_FAILED',
                    message: error instanceof Error ? error.message : '配对失败'
                }
            })
        }
    })
}
```

#### 工具路由（tools.routes.ts）

```typescript
// src/main/tool-server/routes/tools.routes.ts
import type { Express } from 'express'
import { exportToolInfos, executeTool } from '../tool-router'

export function registerToolsRoutes(app: Express): void {
    // 获取工具列表
    app.get('/api/v1/tools', (_req, res) => {
        try {
            const tools = exportToolInfos()
            res.json({ success: true, data: tools })
        } catch (error) {
            res.status(500).json({
                success: false,
                error: {
                    code: 'TOOL_LIST_ERROR',
                    message: error instanceof Error ? error.message : '获取工具列表失败'
                }
            })
        }
    })

    // 执行指定工具
    app.post('/api/v1/tools/:toolName', async (req, res) => {
        try {
            const { toolName } = req.params
            const args = req.body as Record<string, unknown>

            const result = await executeTool(toolName, args)
            res.json({ success: true, data: result })
        } catch (error) {
            res.status(400).json({
                success: false,
                error: {
                    code: 'TOOL_EXECUTION_ERROR',
                    message: error instanceof Error ? error.message : '工具执行失败'
                }
            })
        }
    })
}
```

#### 用户路由（users.routes.ts）

```typescript
// src/main/tool-server/routes/users.routes.ts
import type { Express } from 'express'
import { listUsers } from '../../services/user.service'

export function registerUsersRoutes(app: Express): void {
    app.get('/api/v1/users', async (_req, res) => {
        try {
            const users = await listUsers()
            res.json({ success: true, data: users })
        } catch (error) {
            res.status(500).json({
                success: false,
                error: {
                    code: 'USER_LIST_ERROR',
                    message: '获取用户列表失败'
                }
            })
        }
    })
}
```

#### Ping 路由（ping.routes.ts）

```typescript
// src/main/tool-server/routes/ping.routes.ts
import type { Express } from 'express'
import { getPersistedCurrentUserId } from '../../services/session.service'

export function registerPingRoutes(app: Express): void {
    app.get('/api/v1/ping', async (_req, res) => {
        const userId = await getPersistedCurrentUserId()
        res.json({
            success: true,
            data: {
                status: 'ok',
                currentUser: userId,
                timestamp: Date.now()
            }
        })
    })
}
```

#### 设备管理路由（devices.routes.ts）

```typescript
// src/main/tool-server/routes/devices.routes.ts
import type { Express } from 'express'
import { listPairedDevices, revokeDevice } from '../pairing'

export function registerDevicesRoutes(app: Express): void {
    // 已配对设备列表
    app.get('/api/v1/devices', async (_req, res) => {
        const devices = await listPairedDevices()
        res.json({ success: true, data: devices })
    })

    // 撤销设备
    app.delete('/api/v1/devices/:token', async (req, res) => {
        const { token } = req.params
        await revokeDevice(token)
        res.json({ success: true, data: null })
    })
}
```

### 4.7 Bonjour 广播（bonjour.ts）

使用 `bonjour-service` 包在局域网广播 PC 端服务。

```typescript
// src/main/tool-server/bonjour.ts
import Bonjour from 'bonjour-service'
import { getPersistedCurrentUserId } from '../services/session.service'
import { getUser } from '../services/user.service'
import { logger } from '../utils/logger'

const BONJOUR_PORT = 19877
const SERVICE_TYPE = 'bibi-tools'
const PROTOCOL_VERSION = '1'

let bonjour: Bonjour | null = null
let publishedService: ReturnType<Bonjour['publish']> | null = null

/**
 * 启动 Bonjour 广播
 * 在局域网内广播 _bibi-tools._tcp 服务，iOS 端通过 NetServiceBrowser 发现
 *
 * @author xiangwei
 */
export async function startBonjourBroadcast(): Promise<void> {
    bonjour = new Bonjour()

    // 获取当前用户名用于 TXT 记录
    const userId = await getPersistedCurrentUserId()
    let userName = 'unknown'
    if (userId) {
        const user = await getUser(userId)
        userName = user?.name ?? 'unknown'
    }

    publishedService = bonjour.publish({
        name: `bibi-${userName}`,
        type: SERVICE_TYPE,
        protocol: 'tcp',
        port: BONJOUR_PORT,
        txt: {
            version: PROTOCOL_VERSION,
            user: userName,
            http_port: '19878'
        }
    })

    logger.info('ToolServer', 'Bonjour 广播已启动', {
        serviceName: `bibi-${userName}`,
        port: BONJOUR_PORT,
        user: userName
    })
}

/**
 * 停止 Bonjour 广播
 *
 * @author xiangwei
 */
export function stopBonjourBroadcast(): void {
    if (publishedService) {
        publishedService.stop()
        publishedService = null
    }
    if (bonjour) {
        bonjour.destroy()
        bonjour = null
    }
    logger.info('ToolServer', 'Bonjour 广播已停止')
}
```

> **注意**：Bonjour 广播端口（19877）与 HTTP API 端口（19878）不同。Bonjour 仅用于服务发现，iOS 端发现后通过 HTTP 端口通信。TXT 记录中额外携带 `http_port` 字段。

### 4.8 服务入口（index.ts）

```typescript
// src/main/tool-server/index.ts
import { startHttpServer, stopHttpServer } from './http-server'
import { startBonjourBroadcast, stopBonjourBroadcast } from './bonjour'
import { logger } from '../utils/logger'

let started = false

/**
 * 启动 Tool Server（HTTP + Bonjour）
 *
 * @author xiangwei
 */
export async function startToolServer(): Promise<void> {
    if (started) {
        logger.warn('ToolServer', 'Tool Server 已在运行，跳过启动')
        return
    }

    try {
        await startHttpServer()
        await startBonjourBroadcast()
        started = true
        logger.info('ToolServer', 'Tool Server 启动完成')
    } catch (error) {
        logger.error('ToolServer', 'Tool Server 启动失败', { error })
        throw error
    }
}

/**
 * 停止 Tool Server
 *
 * @author xiangwei
 */
export async function stopToolServer(): Promise<void> {
    if (!started) return
    await stopHttpServer()
    stopBonjourBroadcast()
    started = false
    logger.info('ToolServer', 'Tool Server 已停止')
}
```

---

## 5. 启动流程变更

### 5.1 修改 bootstrap.ts

在 `initializeApplication()` 中，`registerIpcHandlers()` 之后根据设置开关决定是否启动 Tool Server：

```typescript
// src/main/app/bootstrap.ts 修改

// 新增 import
import { startToolServer, stopToolServer } from '../tool-server'
import { getSetting } from '../services/setting.service'

// initializeApplication() 函数内，registerIpcHandlers() 之后添加：

    registerIpcHandlers()

    // 根据设置开关决定是否启动 Tool Server（供 iOS 端联动）
    // 默认关闭，用户需在设置中主动开启
    const toolServerEnabled = (await getSetting<boolean>('tool_server_enabled')) ?? false
    if (toolServerEnabled) {
        try {
            await startToolServer()
        } catch (error: unknown) {
            // Tool Server 启动失败不阻断应用启动，用户仍可使用桌面端功能
            logger.warn('Bootstrap', 'Tool Server 启动失败（不阻断应用）', {
                error: getErrorMessage(error)
            })
        }
    } else {
        logger.info('Bootstrap', 'Tool Server 未启用（设置中已关闭）')
    }

// before-quit 事件中添加：
    app.on('before-quit', () => {
        logger.info('Bootstrap', '应用即将退出')
        destroyTray()
        wechatChannelService.stopAll()
        resetModel()
        void stopToolServer()  // 新增：停止 Tool Server（如已启动）
        closeDatabase()
    })
```

> **设计决策**：
> - Tool Server 默认关闭，用户需在设置页主动开启。
> - 开关状态持久化到 `settings` 表（key: `tool_server_enabled`）。
> - Tool Server 启动失败不阻断应用启动，桌面端功能不受影响。
> - 运行时切换开关：开启时调用 `startToolServer()`，关闭时调用 `stopToolServer()`，无需重启应用。

---

## 6. 数据库变更

**不需要新增表**。所有配置存储在已有的 `settings` 表中：

| key | value 格式 | 说明 |
|-----|-----------|------|
| `tool_server_enabled` | `true` / `false` | Tool Server 开关，默认 `false` |
| `paired_devices` | `[{...}, {...}]` | 已配对设备列表 JSON 数组 |

```
settings 表:
  key: "tool_server_enabled"
  value: "true"

  key: "paired_devices"
  value: '[{"token":"uuid","deviceName":"lieyang-iPhone","pairedAt":"...","lastSeenAt":"..."}]'
```

---

## 7. 新增依赖

| 包名 | 用途 | 类型 |
|------|------|------|
| `express` | HTTP 服务器框架 | dependencies |
| `@types/express` | Express 类型定义 | devDependencies |
| `bonjour-service` | Bonjour/mDNS 局域网广播 | dependencies |
| `zod-to-json-schema` | Zod schema 转 JSON Schema | dependencies |

安装命令：

```bash
npm install express bonjour-service zod-to-json-schema
npm install -D @types/express
```

---

## 8. PC 端 UI 集成

在桌面端设置页新增「移动设备联动」板块。开关控制 Tool Server 的启停，是第一阶段的必须功能。

### 8.1 UI 布局

```
设置 -> 移动设备联动
  ├── 允许移动设备连接: [开关]             ← 核心开关，控制 Tool Server 启停
  │
  │  （开关关闭时以下内容隐藏或灰显）
  │
  ├── 服务状态: 🟢 运行中  端口 19878     ← 开关开启后显示
  ├── [生成配对码]  -> 显示 6 位码 + 倒计时（5 分钟）
  ├── 已配对设备:
  │   ├── lieyang-iPhone  (2026-07-29 配对)  [撤销]
  │   └── （暂无设备）
  └── 提示: 开启后，同一 WiFi 下的 iOS 设备可连接本机记账数据
```

### 8.2 开关行为

| 开关状态 | 行为 |
|----------|------|
| 关闭 -> 开启 | 调用 `startToolServer()` 启动 HTTP + Bonjour，持久化 `tool_server_enabled = true` |
| 开启 -> 关闭 | 调用 `stopToolServer()` 停止 HTTP + Bonjour，持久化 `tool_server_enabled = false`，已配对设备列表保留 |
| 应用启动 | 读取 `tool_server_enabled`，为 `true` 时自动启动 Tool Server |

### 8.3 IPC 通道实现

```typescript
// src/main/ipc/tool-server.ipc.ts
import { registerIpcHandler } from './handle-ipc'
import { z } from 'zod'
import { getSetting, setSetting } from '../services/setting.service'
import { startToolServer, stopToolServer } from '../tool-server'
import { generatePairingCode, listPairedDevices, revokeDevice } from '../tool-server/pairing'
import { logger } from '../utils/logger'

export function registerToolServerIpc(): void {
    // 获取开关状态
    registerIpcHandler('tool-server:get-status', z.tuple([]), '获取状态失败', async () => {
        const enabled = (await getSetting<boolean>('tool_server_enabled')) ?? false
        return { enabled }
    })

    // 切换开关
    registerIpcHandler(
        'tool-server:toggle',
        z.tuple([z.boolean()]),
        '切换失败',
        async (_event, enable) => {
            const current = (await getSetting<boolean>('tool_server_enabled')) ?? false
            if (enable === current) return { enabled: enable }

            if (enable) {
                await startToolServer()
            } else {
                await stopToolServer()
            }
            await setSetting('tool_server_enabled', enable)
            logger.info('ToolServer', '开关已切换', { enabled: enable })
            return { enabled: enable }
        }
    )

    // 生成配对码
    registerIpcHandler('tool-server:generate-code', z.tuple([]), '生成配对码失败', () => {
        const code = generatePairingCode()
        return { code, expiresIn: 300 }
    })

    // 已配对设备列表
    registerIpcHandler('tool-server:list-devices', z.tuple([]), '获取设备列表失败', () => {
        return listPairedDevices()
    })

    // 撤销设备
    registerIpcHandler(
        'tool-server:revoke-device',
        z.tuple([z.string()]),
        '撤销设备失败',
        async (_event, token) => {
            await revokeDevice(token)
            return null
        }
    )
}
```

### 8.4 IPC 注册

在 `src/main/ipc/index.ts` 中添加注册：

```typescript
// src/main/ipc/index.ts 修改

import { registerToolServerIpc } from './tool-server.ipc'

export function registerIpcHandlers(): void {
    // ... 现有注册 ...
    registerToolServerIpc()  // 新增
}
```

### 8.5 渲染端 API 声明

```typescript
// src/shared/types/electron-api.ts 追加

interface ToolServerAPI {
    getStatus: () => Promise<IpcResult<{ enabled: boolean }>>
    toggle: (enable: boolean) => Promise<IpcResult<{ enabled: boolean }>>
    generateCode: () => Promise<IpcResult<{ code: string; expiresIn: number }>>
    listDevices: () => Promise<IpcResult<PairedDevice[]>>
    revokeDevice: (token: string) => Promise<IpcResult>
}
```

---

## 9. 实现路线图

### 第一阶段：核心服务 + 设置开关（4 天）

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| 1 | 安装依赖 | package.json |
| 2 | 实现 HTTP Server 骨架 | tool-server/http-server.ts |
| 3 | 实现配对认证 | tool-server/pairing.ts + auth-middleware.ts |
| 4 | 实现 Schema 序列化 | tool-server/schema-serializer.ts |
| 5 | 实现工具路由 | tool-server/tool-router.ts + routes/ |
| 6 | 实现 Bonjour 广播 | tool-server/bonjour.ts |
| 7 | 修改启动流程（含开关检查） | app/bootstrap.ts |
| 8 | 实现 Tool Server IPC（开关 + 配对码 + 设备管理） | ipc/tool-server.ipc.ts |
| 9 | 设置页 UI（开关 + 配对码 + 设备列表） | renderer/ |
| 10 | 联调测试 | 手动 curl + iOS 端对接 |

### 第二阶段：体验优化（后续迭代）

| 步骤 | 任务 | 涉及文件 |
|------|------|----------|
| 11 | 配对码 QR 码展示（扫码替代手动输入） | renderer/ |
| 12 | 设备连接通知（系统通知） | main/ |
| 13 | 工具调用日志面板 | renderer/ |

### 验收标准

- [ ] 设置中「移动设备联动」开关默认关闭
- [ ] 开启开关后 Tool Server 启动，iOS 端能通过 Bonjour 发现 PC
- [ ] 关闭开关后 Tool Server 停止，iOS 端无法发现 PC
- [ ] 运行时切换开关无需重启应用
- [ ] iOS 端输入配对码后，获取到 device token
- [ ] iOS 端能获取工具列表（含 JSON Schema 参数定义）
- [ ] iOS 端能执行工具（如 `queryTransactions`）并获取结果
- [ ] 未认证请求返回 401
- [ ] PC 端重启后开关状态和 token 仍然有效
- [ ] Tool Server 启动失败不影响桌面端正常使用

---

## 10. 安全注意事项

| 风险 | 缓解措施 |
|------|----------|
| 局域网内未授权调用 | 所有非配对端点需要 Bearer token |
| 配对码暴力破解 | 5 分钟过期 + 一次性使用 + 生成后需用户主动触发 |
| 大请求体攻击 | Express body 限制 1MB |
| 工具执行越权 | `user_id` 从请求 body 获取，通过 `runWithBoundUserId` 绑定，工具内部通过 `getCurrentUserId()` 读取，LLM 无法伪造 |
| 设备伪造 | device token 为 UUID，配对时绑定 deviceName |

---

## 附录：工具名对照表

PC 端工具名采用驼峰命名（如 `queryTransactions`），iOS 端 function calling 使用相同名称。工具名对应关系：

| 工具组 | 工具名 | 中文名 | 对应 Service |
|--------|--------|--------|-------------|
| data-query | queryTransactions | 流水查询 | transaction.service |
| data-query | queryRecentTransactions | 最近流水 | transaction.service |
| data-query | queryAccountBalance | 账户余额 | account.service |
| data-query | queryMonthlySummary | 月度汇总 | statistics.service |
| data-query | queryYearlySummary | 年度汇总 | statistics.service |
| data-query | queryCategorySummary | 分类统计 | statistics.service |
| data-query | queryBudgetProgress | 预算进度 | budget.service |
| calculator | evaluate | 表达式计算 | mathjs |
| calculator | summarize | 数据汇总 | - |
| calculator | compareValues | 数值对比 | - |
| calculator | convertCentsToYuan | 单位换算 | - |
| analysis | analyzeTrend | 趋势分析 | statistics.service |
| analysis | detectAnomalies | 异常检测 | transaction.service |
| analysis | comparePeriods | 周期对比 | statistics.service |
| transaction-write | createTransaction | 记账 | transaction.service |
| transaction-write | deleteTransaction | 删除流水 | transaction.service |
| transaction-write | queryAllAccounts | 账户列表 | account.service |
| transaction-write | queryAllCategories | 分类列表 | category.service |
| user-todo | createUserTodo | 创建待办 | todo.service |
| user-todo | deleteUserTodo | 删除待办 | todo.service |
| user-todo | queryUserTodos | 查询待办 | todo.service |
| user-todo | updateUserTodo | 修改待办 | todo.service |
