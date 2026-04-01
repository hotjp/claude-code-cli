# Entrypoints 模块 (entrypoints/)

## 架构概览

Entrypoints 模块是 Claude Code CLI 的多入口点集合，定义了 CLI、Agent SDK 和 MCP Server 三种运行模式的启动路径。各入口共享类型定义，并通过 `feature()` 特性门控实现条件编译（构建时裁剪未使用的路径）。

```typescript
cli.tsx (CLI 入口)
  ├── --version / -v          → 直接输出版本号，零模块加载
  ├── --dump-system-prompt    → 输出渲染后的系统提示
  ├── --claude-in-chrome-mcp   → Chrome MCP 服务器
  ├── --chrome-native-host     → Chrome 原生主机
  ├── --computer-use-mcp       → Computer Use MCP 服务器
  ├── --daemon-worker=<kind>   → Daemon worker 进程
  ├── remote-control / rc     → Bridge 远程控制模式
  ├── daemon [subcommand]      → 长运行 Supervisor
  ├── ps/logs/attach/kill     → 会话管理
  ├── new/list/reply          → 模板任务
  ├── environment-runner       → BYOC 环境运行器
  ├── self-hosted-runner       → 自托管运行器
  └── (default)               → 完整 CLI (main.tsx)

mcp.ts (MCP Server 入口)
  └── startMCPServer()        → 基于 @modelcontextprotocol/sdk 的 STDIO 服务器

init.ts (初始化模块)
  └── init()                  → 配置、特权、遥测、代理、OAuth 等初始化
  └── initializeTelemetryAfterTrust() → 信任后的遥测初始化

agentSdkTypes.ts (Agent SDK 入口)
  └── query() / unstable_v2_*() → SDK API
  └── getSessionMessages() / listSessions() / forkSession() → 会话管理
  └── watchScheduledTasks() / connectRemoteControl() → 守护进程原语
```

### 核心接口

- **`startMCPServer(cwd, debug, verbose)`** — 启动 STDIO 传输的 MCP 服务器，处理 ListTools/CallTool 请求
- **`init(): Promise<void>`** — CLI 初始化主函数，memoized 防止重复执行
- **`initializeTelemetryAfterTrust(): void`** — 信任对话框接受后初始化遥测系统
- **`query(params)`** — V1 SDK 主查询 API（内部抛出 "not implemented"）
- **`unstable_v2_createSession(options)`** — V2 API，创建持久会话
- **`unstable_v2_prompt(message, options)`** — V2 API，单次便捷查询

---

## cli.tsx — CLI 引导入口

### 职责

CLI 的最外层引导程序，在加载完整 CLI 之前处理所有特殊标志和快速路径。所有导入均为动态导入，以最小化快速路径的模块评估开销。

### 核心逻辑

1. **版本号快速路径** (`--version` / `-v` / `-V`)：零模块加载，直接输出 `MACRO.VERSION`
2. **系统提示转储** (`--dump-system-prompt`)：用于提示敏感度评估
3. **Chrome 集成**：`--claude-in-chrome-mcp` / `--chrome-native-host` / `--computer-use-mcp`
4. **Daemon Worker**：`--daemon-worker=<kind>`（内部，supervisor 派生）
5. **远程控制 Bridge**：`remote-control` / `rc` / `remote` / `sync` / `bridge`
6. **Daemon Supervisor**：`daemon [subcommand]`
7. **会话管理**：`ps` / `logs` / `attach` / `kill` / `--bg` / `--background`
8. **模板任务**：`new` / `list` / `reply`
9. **环境运行器**：`environment-runner` / `self-hosted-runner`
10. **Tmux Worktree**：`--tmux` + `--worktree` 组合

### 环境变量处理

| 变量 | 说明 |
|------|------|
| `COREPACK_ENABLE_AUTO_PIN=0` | 禁用 corepack 自动固定 |
| `NODE_OPTIONS=--max-old-space-size=8192` | CCR 环境下增大堆内存（容器 16GB） |
| `CLAUDE_CODE_SIMPLE=1` | `--bare` 标志时设置，简化 CLI 行为 |

### Ablation 基线

通过 `feature('ABLATION_BASELINE')` 构建标志，当 `CLAUDE_CODE_ABLATION_BASELINE` 环境变量存在时，自动禁用以下特性：
- `CLAUDE_CODE_SIMPLE`
- `CLAUDE_CODE_DISABLE_THINKING`
- `DISABLE_INTERLEAVED_THINKING`
- `DISABLE_COMPACT`
- `DISABLE_AUTO_COMPACT`
- `CLAUDE_CODE_DISABLE_AUTO_MEMORY`
- `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS`

---

## mcp.ts — MCP Server 实现

### 职责

将 Claude Code CLI 作为 MCP (Model Context Protocol) 服务器运行，通过 STDIO 传输通信，符合 @modelcontextprotocol/sdk 标准。

### 核心函数

**`startMCPServer(cwd, debug, verbose)`**

使用 `StdioServerTransport` 创建 MCP 服务器，注册两个请求处理器：

#### ListTools 处理器

返回所有可用工具的列表（通过 `getTools()` 获取），每个工具包含：
- `name` / `description`（通过 `tool.prompt()` 动态生成）
- `inputSchema`（Zod → JSON Schema 转换）
- `outputSchema`（仅当根类型为 `object` 时返回，跳过 `anyOf`/`oneOf`）

#### CallTool 处理器

1. 查找工具（`findToolByName`）
2. 调用 `isEnabled()` 检查工具是否可用
3. 调用 `validateInput?.()` 校验输入（可选）
4. 调用 `tool.call()` 执行工具
5. 错误处理：捕获异常，通过 `getErrorParts()` 提取错误文本，返回 `{ isError: true }` 的 `CallToolResult`

### 文件状态缓存

使用 LRU 缓存（`createFileStateCacheWithSizeLimit`，默认 100 文件 / 25MB）防止 MCP 服务器操作时无限内存增长。

### 工具调用上下文

```typescript
toolUseContext: ToolUseContext = {
  abortController: createAbortController(),
  options: {
    commands: MCP_COMMANDS,      // 仅含 review 命令
    tools,                        // 当前工具列表
    mainLoopModel: getMainLoopModel(),
    thinkingConfig: { type: 'disabled' },
    mcpClients: [],               // 不重新暴露 MCP 工具
    mcpResources: {},
    isNonInteractiveSession: true,
    debug, verbose,
    agentDefinitions: { activeAgents: [], allAgents: [] },
  },
  getAppState: () => getDefaultAppState(),
  setAppState: () => {},
  messages: [],
  readFileState: readFileStateCache,
  setInProgressToolUseIDs: () => {},
  setResponseLength: () => {},
  updateFileHistoryState: () => {},
  updateAttributionState: () => {},
}
```

### 导出的 MCP 命令

目前仅支持 `review` 命令（通过 `MCP_COMMANDS` 常量暴露）。

---

## init.ts — 初始化模块

### 职责

CLI 的核心初始化逻辑，包括配置系统、环境变量、遥测、代理、OAuth 等。所有初始化步骤均有性能探针（`profileCheckpoint`）标记。

### `init(): Promise<void>`

Memoized 初始化主函数，步骤如下：

1. **配置启用** — `enableConfigs()`，解析 settings.json
2. **安全环境变量** — `applySafeConfigEnvironmentVariables()`（信任对话框前）
3. **CA 证书** — `applyExtraCACertsFromConfig()`（TLS 首次握手前）
4. **优雅关闭** — `setupGracefulShutdown()`
5. **1P 事件日志初始化** — 动态导入 1P 事件日志模块
6. **OAuth 账户信息** — `populateOAuthAccountInfoIfNeeded()`
7. **JetBrains IDE 检测** — `initJetBrainsDetection()`
8. **GitHub 仓库检测** — `detectCurrentRepository()`
9. **远程托管/策略限制** — 条件初始化 `RemoteManagedSettings` / `PolicyLimits` 加载 Promise
10. **首次启动时间** — `recordFirstStartTime()`
11. **mTLS 配置** — `configureGlobalMTLS()`
12. **全局代理/证书** — `configureGlobalAgents()`
13. **API 预连接** — `preconnectAnthropicApi()`（重叠 TCP+TLS 握手）
14. **上游代理 (CCR)** — `initUpstreamProxy()`（仅 CCR 模式）
15. **Git-Bash (Windows)** — `setShellIfWindows()`
16. **LSP 清理注册** — `registerCleanup(shutdownLspServerManager)`
17. **团队清理注册** — `registerCleanup(cleanupSessionTeams)`
18. **Scratchpad 目录** — 条件创建

### 错误处理

- **`ConfigParseError`**：非交互式模式下输出错误到 stderr 并退出；交互式模式下显示 `InvalidConfigDialog`
- **其他错误**：重新抛出

### `initializeTelemetryAfterTrust(): void`

在信任对话框接受后调用。对于远程托管设置用户，等待设置加载后再初始化遥测；对于其他用户立即初始化。包含 beta tracing 的急切初始化路径。

### `doInitializeTelemetry(): Promise<void>`

内部遥测初始化函数，使用 `initializeTelemetry`（从 `instrumentation.ts` 动态导入）创建 OTLP meter、计数器等。

---

## agentSdkTypes.ts — Agent SDK 主入口

### 职责

Agent SDK 的公共 API 入口，重新导出以下模块的类型和函数：
- `sdk/coreTypes.ts` — 通用可序列化类型（消息、配置）
- `sdk/controlTypes.ts` — 控制协议类型（SDK 构建者使用）
- `sdk/settingsTypes.generated.ts` — 从 settings JSON Schema 生成的类型
- `sdk/toolTypes.ts` — 工具类型

### V2 SDK API（不稳定）

| 函数 | 说明 |
|------|------|
| `unstable_v2_createSession(options)` | 创建持久会话 |
| `unstable_v2_resumeSession(sessionId, options)` | 恢复已有会话 |
| `unstable_v2_prompt(message, options)` | 单次便捷查询 |

### V1 SDK API

| 函数 | 说明 |
|------|------|
| `query(params)` | 主查询 API |
| `tool(name, description, inputSchema, handler)` | 工具定义工厂 |
| `createSdkMcpServer(options)` | 创建内嵌 MCP 服务器 |
| `AbortError` | 中止错误类 |

### 会话管理 API

| 函数 | 说明 |
|------|------|
| `getSessionMessages(sessionId, options?)` | 读取会话消息 |
| `listSessions(options?)` | 列出所有会话 |
| `getSessionInfo(sessionId, options?)` | 获取单个会话元数据 |
| `renameSession(sessionId, title, options?)` | 重命名会话 |
| `tagSession(sessionId, tag, options?)` | 为会话添加标签 |
| `forkSession(sessionId, options?)` | 分叉会话到新分支 |

### 守护进程原语（内部）

| 函数 | 说明 |
|------|------|
| `watchScheduledTasks(opts)` | 监视 scheduled_tasks.json 并产生触发事件 |
| `buildMissedTaskNotification(missed)` | 格式化错过的定时任务提示 |
| `connectRemoteControl(opts)` | 保持 claude.ai 远程控制 bridge 连接 |

---

## sandboxTypes.ts — 沙箱配置类型

### 职责

沙箱配置类型的单一真实来源，定义网络、文件系统和全局设置 Schema，供 SDK 和设置验证共同导入。

### Schema 层次

```typescript
SandboxSettingsSchema
├── enabled
├── failIfUnavailable
├── autoAllowBashIfSandboxed
├── allowUnsandboxedCommands
├── network: SandboxNetworkConfigSchema
│   ├── allowedDomains
│   ├── allowManagedDomainsOnly
│   ├── allowUnixSockets / allowAllUnixSockets
│   ├── allowLocalBinding
│   ├── httpProxyPort / socksProxyPort
├── filesystem: SandboxFilesystemConfigSchema
│   ├── allowWrite / denyWrite / denyRead / allowRead
│   └── allowManagedReadPathsOnly
├── ignoreViolations
├── enableWeakerNestedSandbox
├── enableWeakerNetworkIsolation
├── excludedCommands
└── ripgrep (custom ripgrep 配置)
```

### 关键类型

| 类型 | 说明 |
|------|------|
| `SandboxSettings` | 完整沙箱设置 |
| `SandboxNetworkConfig` | 网络配置（域名、代理、Unix socket） |
| `SandboxFilesystemConfig` | 文件系统配置（读写权限） |
| `SandboxIgnoreViolations` | 忽略违规记录 |

---

## sdk/controlSchemas.ts — 控制协议 Schema

### 职责

定义 SDK 实现（Python SDK 等）与 CLI 之间的控制协议 Schema，用于 JSON-RPC 通信。

### 控制请求类型

| Subtype | 说明 |
|---------|------|
| `initialize` | 初始化 SDK 会话（hooks、MCP 服务器、代理配置） |
| `interrupt` | 中断当前运行的对话轮次 |
| `can_use_tool` | 请求工具使用权限 |
| `set_permission_mode` | 设置权限模式 |
| `set_model` | 设置模型 |
| `set_max_thinking_tokens` | 设置最大思考 token |
| `mcp_status` | 请求 MCP 服务器状态 |
| `get_context_usage` | 请求上下文窗口使用明细 |
| `rewind_files` | 回退文件更改 |
| `cancel_async_message` | 取消异步用户消息 |
| `seed_read_state` | 种子化 readFileState 缓存 |
| `hook_callback` | 传递 hook 回调 |
| `mcp_message` | 发送 JSON-RPC 消息到 MCP 服务器 |
| `mcp_set_servers` | 替换动态管理的 MCP 服务器 |
| `reload_plugins` | 重新加载插件 |
| `mcp_reconnect` | 重连 MCP 服务器 |
| `mcp_toggle` | 启用/禁用 MCP 服务器 |
| `stop_task` | 停止运行中的任务 |
| `apply_flag_settings` | 合并特性标志设置 |
| `get_settings` | 返回有效合并设置 |
| `elicitation` | 请求 SDK 消费者处理 MCP 征询 |

### 控制响应类型

- `ControlResponseSchema` — 成功响应 (`{ subtype: 'success', request_id, response }`)
- `ControlErrorResponseSchema` — 错误响应 (`{ subtype: 'error', request_id, error, pending_permission_requests? }`)

---

## sdk/coreSchemas.ts — SDK 核心 Schema

### 职责

SDK 数据类型的 Zod Schema 单一真实来源，TypeScript 类型通过 `scripts/generate-sdk-types.ts` 从这些 Schema 生成。

### 主要 Schema 分类

| 类别 | Schema |
|------|--------|
| **使用量** | `ModelUsageSchema` |
| **输出格式** | `OutputFormatSchema`, `JsonSchemaOutputFormatSchema` |
| **配置** | `PermissionModeSchema`, `ThinkingConfigSchema` |
| **MCP 服务器** | `McpStdioServerConfigSchema`, `McpSSEServerConfigSchema`, `McpHttpServerConfigSchema`, `McpServerStatusSchema` |
| **权限** | `PermissionUpdateSchema`, `PermissionResultSchema`, `PermissionBehaviorSchema` |
| **Hooks** | `HookEventSchema`, `HookInputSchema`, `HookJSONOutputSchema`（24 种事件类型） |
| **会话管理** | `SDKSessionInfoSchema`, `SDKUserMessageSchema`, `SDKAssistantMessageSchema` |
| **代理定义** | `AgentDefinitionSchema` |

### Hook 事件类型

```typescript
PreToolUse, PostToolUse, PostToolUseFailure,
Notification, UserPromptSubmit, SessionStart, SessionEnd,
Stop, StopFailure, SubagentStart, SubagentStop,
PreCompact, PostCompact, PermissionRequest, PermissionDenied,
Setup, TeammateIdle, TaskCreated, TaskCompleted,
Elicitation, ElicitationResult, ConfigChange,
WorktreeCreate, WorktreeRemove, InstructionsLoaded,
CwdChanged, FileChanged
```

---

## sdk/coreTypes.ts — SDK 核心类型

### 职责

重新导出生成的核心类型，提供 `HOOK_EVENTS` 和 `EXIT_REASONS` 常量数组供运行时使用。

### 导出常量

```typescript
const HOOK_EVENTS = [
  'PreToolUse', 'PostToolUse', 'PostToolUseFailure',
  'Notification', 'UserPromptSubmit', 'SessionStart', 'SessionEnd',
  'Stop', 'StopFailure', 'SubagentStart', 'SubagentStop',
  'PreCompact', 'PostCompact', 'PermissionRequest', 'PermissionDenied',
  'Setup', 'TeammateIdle', 'TaskCreated', 'TaskCompleted',
  'Elicitation', 'ElicitationResult', 'ConfigChange',
  'WorktreeCreate', 'WorktreeRemove', 'InstructionsLoaded',
  'CwdChanged', 'FileChanged',
] as const

const EXIT_REASONS = [
  'clear', 'resume', 'logout', 'prompt_input_exit',
  'other', 'bypass_permissions_disabled',
] as const
```

---

## 文件索引

| 文件 | 职责 |
|------|------|
| `agentSdkTypes.ts` | Agent SDK 公共 API 主入口，重新导出核心/运行时/控制类型 |
| `cli.tsx` | CLI 引导入口，处理所有特殊标志的快速路径 |
| `init.ts` | CLI 初始化逻辑（配置、遥测、代理、OAuth） |
| `mcp.ts` | MCP Server STDIO 实现（基于 @modelcontextprotocol/sdk） |
| `sandboxTypes.ts` | 沙箱配置 Schema 和类型（网络、文件系统、设置） |
| `sdk/controlSchemas.ts` | 控制协议 Zod Schema（MCP/SDK 构建者使用） |
| `sdk/coreSchemas.ts` | SDK 核心 Zod Schema（生成 TypeScript 类型） |
| `sdk/coreTypes.ts` | 重新导出生成的核心类型和常量 |
