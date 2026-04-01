# CLI 模块 (cli/)

## 架构概览

CLI 模块是 Claude Code 的命令行交互层，负责 STDIO 通信、远程传输、子命令处理和输出渲染。整个架构分为四层：

```
StructuredIO (STDIN/stdout 协议)
    ├── RemoteIO (远程 Session Ingress 扩展)
    │       └── transports/ (WebSocket / SSE / Hybrid)
    │               ├── CCRClient (CCR v2 生命周期管理)
    │               ├── SerialBatchEventUploader (批量 POST + 重试)
    │               └── WorkerStateUploader (状态上传)
    │
handlers/ (子命令处理函数)
    ├── agents.ts     — claude agents
    ├── auth.ts       — claude setup-token / doctor / install
    ├── autoMode.ts   — claude auto-mode defaults / config / critique
    ├── mcp.tsx       — claude mcp *
    ├── plugins.ts    — claude plugin *
    └── util.tsx      — 共享 UI 渲染工具
    │
exit.ts / ndjsonSafeStringify.ts / update.ts (工具函数)
```

### 核心接口

| 类/函数 | 说明 |
|---------|------|
| `StructuredIO` | 通过 STDIO 读写 SDK 消息，管理 `can_use_tool` 权限协议 |
| `RemoteIO` | `StructuredIO` 的远程扩展，支持 WebSocket/SSE 传输，接入 CCR v2 |
| `ndjsonSafeStringify()` | 对 NDJSON 输出进行 U+2028/U+2029 转义，防止行分割器破坏 JSON |
| `getTransportForUrl()` | 根据 URL 协议和环境变量选择合适的传输层 |
| `cliError()` / `cliOk()` | 统一的 CLI 退出处理（错误码 1 / 0） |

### 传输层选择策略

| 条件 | 传输层 |
|------|--------|
| `CLAUDE_CODE_USE_CCR_V2=true` | `SSETransport` (SSE 读 + POST 写) |
| URL 为 `ws:`/`wss:` 且 `CLAUDE_CODE_POST_FOR_SESSION_INGRESS_V2=true` | `HybridTransport` |
| URL 为 `ws:`/`wss:`（默认） | `WebSocketTransport` |

---

## StructuredIO

**用途**: 通过 STDIO 读写 SDK 协议消息（`user` / `control_request` / `control_response` 等），管理工具权限请求的生命周期。

- **文件**: `cli/structuredIO.ts`
- **扩展**: `RemoteIO`（远程模式）

**核心属性**:
| 属性 | 类型 | 说明 |
|------|------|------|
| `structuredInput` | `AsyncGenerator<StdinMessage \| SDKMessage>` | 解析后的输入消息流 |
| `outbound` | `Stream<StdoutMessage>` | 输出消息队列（防止 `control_request` 抢占 `stream_events`） |
| `restoredWorkerState` | `Promise<SessionExternalMetadata \| null>` | CCR v2 恢复的工作状态 |

**权限协议流程** (`createCanUseTool`):
1. 调用 `hasPermissionsToUseTool()` 判断内置权限
2. 若为 `allow`/`deny` 直接返回
3. 若为 `ask`：并发执行 PermissionRequest Hooks 和 SDK `can_use_tool` 请求
4. `Promise.race()` 竞速，先响应者胜出；另一方被 Abort

**辅助方法**:
| 方法 | 说明 |
|------|------|
| `prependUserMessage(content)` | 在下一个输入消息前插入用户消息 |
| `injectControlResponse(response)` | 由 bridge 注入权限响应（来自 claude.ai） |
| `createHookCallback(callbackId)` | 创建 Hook 回调（转发给 SDK consumer） |
| `handleElicitation(...)` | 发送表单/URL elicitation 请求给 SDK host |
| `createSandboxAskCallback()` | 转发沙盒网络权限请求为 `can_use_tool` 协议 |

**内部机制**:
- 最多追踪 1000 个已解决的 `tool_use_id`，防止重复的 `control_response` 导致 API 400 错误
- `keep_alive` 和 `update_environment_variables` 消息在解析层被拦截，不向上传递

---

## RemoteIO

**用途**: `StructuredIO` 的远程实现，用于 SDK 模式和 Remote Control (CCR) 会话。通过 WebSocket/SSE 传输与云端 Session Ingress 通信。

- **文件**: `cli/remoteIO.ts`
- **继承**: `StructuredIO`
- **传输**: `WebSocketTransport` / `SSETransport` / `HybridTransport`（由 `getTransportForUrl()` 选择）

**构造流程**:
1. 初始化 `PassThrough` 输入流
2. 通过 `getTransportForUrl()` 创建传输层
3. 配置 CCR v2（若启用）：创建 `CCRClient`，注册事件写入器/读取器
4. 启动连接（`transport.connect()`）
5. Bridge 模式下设置 keep-alive 定时器（默认 120s，防止代理 GC 空闲连接）

**write() 行为**:
- 有 CCRClient 时优先走 `ccrClient.writeEvent()`
- 否则走 `transport.write()`
- Bridge 模式下 `control_request` 始终 echo 到 stdout；其他消息仅在 debug 模式 echo

**生命周期覆盖**:
| 方法 | 说明 |
|------|------|
| `flushInternalEvents()` | 刷新 CCR 内部事件到持久化存储 |
| `get internalEventsPending` | 返回待发送内部事件数量 |

---

## 传输层 (transports/)

### WebSocketTransport

**用途**: 基础的 WebSocket 双向传输，用于默认的远程会话。

- **文件**: `cli/transports/WebSocketTransport.ts`
- **协议**: `ws:` / `wss:`

**关键特性**:
- 自动重连（指数退避，10 分钟放弃）
- 心跳保活（默认 10s 服务器发送，45s 无响应认为死亡）
- 睡眠检测：断开时间超过 60s 认为机器从睡眠唤醒，重置重连预算
- mTLS / 代理支持

**永久失败 Close Codes**:
| Code | 含义 |
|------|------|
| `1002` | 协议错误（session 被回收） |
| `4001` | Session 过期 / 未找到 |
| `4003` | 未授权 |

---

### SSETransport

**用途**: Server-Sent Events 接收 + HTTP POST 发送，用于 CCR v2 模式。

- **文件**: `cli/transports/SSETransport.ts`
- **读取**: SSE 事件流（`/worker/events/stream`）
- **写入**: HTTP POST 批量事件

**SSE 帧解析**: `parseSSEFrames()` 增量解析 SSE 帧，支持 `event:` / `id:` / `data:` 字段。

---

### HybridTransport

**用途**: WebSocket 接收 + HTTP POST 批量发送，桥接 WS 的实时性和 POST 的可靠性。

- **文件**: `cli/transports/HybridTransport.ts`
- **继承**: `WebSocketTransport`
- **写入**: `SerialBatchEventUploader`（100ms 批量窗口，串行 POST，指数退避）

**写流程**:
```
write(stream_event)  →  100ms 缓冲窗口
write(other)         →  立即 flush 缓冲 + enqueue 自身
                           SerialBatchEventUploader.enqueue()
                              → 单个 HTTP POST
                              → 失败：重试 + 退避
                              → 队列满：背压阻塞
```

---

### SerialBatchEventUploader

**用途**: 串行批量上传器，带重试、背压和可选字节限制。

- **文件**: `cli/transports/SerialBatchEventUploader.ts`

**核心参数**:
| 参数 | 说明 |
|------|------|
| `maxBatchSize` | 每批最大条数 |
| `maxBatchBytes` | 每批最大字节数 |
| `maxQueueSize` | 队列上限（达到时 `enqueue()` 阻塞） |
| `maxConsecutiveFailures` | 连续失败多少次后丢弃该批（可选） |

**`RetryableError`**: 携带 `retryAfterMs` 的错误类型，用于服务器返回 429 时覆写退避时间。

---

### WorkerStateUploader

**用途**: 向 `/worker` 端点发送 session 状态和元数据的合并上传器。

- **文件**: `cli/transports/WorkerStateUploader.ts`

**特性**:
- 最多 1 个进行中 PUT + 1 个待处理 patch（自然有界，无背压）
- 新 patch 与 pending 合并（顶层 key 覆盖，内部元数据 RFC 7396 合并）
- 无限重试直到成功或 close

---

### CCRClient

**用途**: CCR (Cloud Control Plane Remote) v2 客户端，管理心跳、epoch、状态上报和事件持久化。

- **文件**: `cli/transports/ccrClient.ts`
- **启用条件**: `CLAUDE_CODE_USE_CCR_V2=true`

**核心功能**:
| 功能 | 说明 |
|------|------|
| 心跳 | 每 20s 发送 `heartbeat` 事件（服务器 TTL 60s） |
| Epoch 管理 | `reportEpochHeartbeat()` (409 响应触发 `handleEpochMismatch()`) |
| 状态上报 | `reportDelivery()` / `reportState()` / `reportMetadata()` |
| 事件持久化 | `writeInternalEvent()` → 批量 POST 到 Session Ingress |
| 状态恢复 | `readInternalEvents()` / `readSubagentInternalEvents()` |

**`StreamAccumulator`**: `text_delta` 事件在 100ms 窗口内合并为"截至目前的完整快照"，供断连后重新接入的客户端获取完整上下文。

**错误处理**: 401/403 连续 10 次且 token 未过期则退出（防止死循环）。

---

### getTransportForUrl()

**用途**: 根据 URL 协议和环境变量选择合适的传输层。

- **文件**: `cli/transports/transportUtils.ts`

---

## ndjsonSafeStringify

**用途**: 安全的单行 JSON 序列化，转义 U+2028 (LINE SEPARATOR) 和 U+2029 (PARAGRAPH SEPARATOR)。

- **文件**: `cli/ndjsonSafeStringify.ts`

**问题背景**: JavaScript 的 `\n` 分割在接收端会将 U+2028/U+2029 视为行终止符，导致 JSON 被截断。ES2019 `JSON.stringify` 已接受这些字符为合法 JSON，但老旧接收端仍按行语义分割。单字符正则替换性能优于两次全串扫描。

---

## 子命令处理器 (handlers/)

### agentsHandler

**用途**: 列出所有已配置的自定义代理（`claude agents`）。

- **文件**: `cli/handlers/agents.ts`

**输出分组**:
- `Built-in agents`
- `Agents from ~/.claude/agents.d/`
- `Project agents`

每个代理显示：类型 · 模型 · 内存大小。覆盖的代理显示 `(shadowed by ...)`。

---

### auth.ts

**用途**: OAuth 认证流程（`claude setup-token`）、医生诊断（`claude doctor`）和安装（`claude install`）。

- **文件**: `cli/handlers/auth.ts`

**authLogout()**: 清除 OAuth token 并登出。

**installOAuthTokens()**: 共享的后置认证逻辑——保存 tokens、获取 profile/roles、设置 API key。

---

### autoModeHandlers

**用途**: 自动模式分类规则管理（`claude auto-mode *`）。

- **文件**: `cli/handlers/autoMode.ts`

| 子命令 | 说明 |
|--------|------|
| `autoModeDefaultsHandler()` | 输出默认 allow/soft_deny/environment 规则 |
| `autoModeConfigHandler()` | 输出合并后的有效配置（用户配置优先于默认值） |
| `autoModeCritiqueHandler()` | AI 评审用户自定义规则的清晰度和完整性 |

**autoModeCritiqueHandler** 使用 `sideQuery()` 调用主循环模型，提示词包含完整 classifier system prompt + 用户规则 + 默认规则供对比。

---

### mcpHandlers

**用途**: MCP (Model Context Protocol) 服务器管理（`claude mcp *`）。

- **文件**: `cli/handlers/mcp.tsx`

| 子命令 | 说明 |
|--------|------|
| `mcpServeHandler()` | 启动 MCP 服务器 |
| `mcpAddJsonHandler()` | 从 JSON 配置添加 MCP 服务器 |
| `mcpAddFromDesktopHandler()` | 从桌面客户端添加 MCP 服务器 |
| `mcpRemoveHandler()` | 移除 MCP 服务器 |
| `mcpListHandler()` | 列出已配置的 MCP 服务器 |
| `mcpGetHandler()` | 获取 MCP 服务器配置 |
| `mcpResetChoicesHandler()` | 重置 MCP 服务器选项 |

---

### pluginHandlers

**用途**: 插件和插件市场管理（`claude plugin *`）。

- **文件**: `cli/handlers/plugins.ts`

| 子命令 | 说明 |
|--------|------|
| `pluginInstallHandler()` | 安装插件 |
| `pluginUninstallHandler()` | 卸载插件 |
| `pluginDisableHandler()` / `pluginEnableHandler()` | 禁用/启用插件 |
| `pluginUpdateHandler()` | 更新插件 |
| `pluginValidateHandler()` | 验证插件配置 |
| `marketplaceListHandler()` | 列出市场 |
| `marketplaceAddHandler()` | 添加市场源 |
| `marketplaceUpdateHandler()` | 更新/刷新市场缓存 |
| `marketplaceRemoveHandler()` | 移除市场 |

**核心逻辑**:
- 加载插件通过 `loadAllPlugins()`，区分内置 / 禁用 / 会话级
- MCP 服务器通过 `loadPluginMcpServers()` 按需加载
- 所有处理函数使用 `cliError()` / `cliOk()` 统一退出

---

### util.tsx

**用途**: 共享 UI 渲染工具和 OAuth Token 引导处理器。

- **文件**: `cli/handlers/util.tsx`

**核心函数**:
| 函数 | 说明 |
|------|------|
| `setupTokenHandler` | 引导用户完成 1 年有效期 OAuth Token 的创建。若已配置 API Key 环境变量，显示警告。 |
| `DoctorWithPlugins` | 懒加载 `Doctor` 组件，挂载 MCP/插件后渲染诊断界面。 |
| `installHandler` | 调用原生安装程序。 |

---

## 工具函数

### exit.ts

**用途**: 集中化的 CLI 退出点，消除散落在各 handler 中的 `console.error + process.exit` 重复代码。

- **文件**: `cli/exit.ts`

```typescript
cliError(msg?: string): never  // stderr + exit(1)
cliOk(msg?: string): never     // stdout + exit(0)
```

**`: never` 返回类型**: TypeScript 控制流收窄，`return cliError(...)` 后的代码访问被收窄为 `never` 的值。测试通过 spy `process.exit` 和 `console.error` / `process.stdout.write` 实现无副作用测试。

---

### update.ts

**用途**: `claude update` 命令实现，检测并执行就地更新。

- **文件**: `cli/update.ts`

**更新策略**（按安装类型）:
| 安装类型 | 更新方式 |
|---------|---------|
| `native` | `installLatestNative()` |
| `npm-local` | `installOrUpdateClaudePackage()` |
| `npm-global` | `installGlobalPackage()` |
| `package-manager` | 提示用户使用 homebrew / winget / apk 等 |
| `development` | 拒绝更新 |

**诊断检查**: `getDoctorDiagnostic()` 检测多安装冲突、配置/现实不匹配、lock contention 等问题。

---

## CLI 模块索引

| 文件 | 用途 |
|------|------|
| `cli/exit.ts` | CLI 退出工具函数（`cliError` / `cliOk`） |
| `cli/ndjsonSafeStringify.ts` | NDJSON 安全序列化（转义 U+2028/U+2029） |
| `cli/remoteIO.ts` | 远程 Session Ingress 通信层 |
| `cli/structuredIO.ts` | StructuredIO 核心类（SDK 消息协议） |
| `cli/update.ts` | `claude update` 命令实现 |
| `cli/handlers/agents.ts` | `claude agents` 子命令 |
| `cli/handlers/auth.ts` | `claude setup-token / doctor / install` |
| `cli/handlers/autoMode.ts` | `claude auto-mode defaults / config / critique` |
| `cli/handlers/mcp.tsx` | `claude mcp *` 子命令 |
| `cli/handlers/plugins.ts` | `claude plugin *` 子命令 |
| `cli/handlers/util.tsx` | `authLogout` / OAuth Token 管理 |
| `cli/transports/HybridTransport.ts` | HybridTransport (WS 读 + POST 写) |
| `cli/transports/SSETransport.ts` | SSETransport (SSE 读 + POST 写) |
| `cli/transports/SerialBatchEventUploader.ts` | 批量 POST 上传器（重试 + 背压） |
| `cli/transports/WebSocketTransport.ts` | WebSocket 传输层（默认） |
| `cli/transports/WorkerStateUploader.ts` | Session 状态合并上传器 |
| `cli/transports/ccrClient.ts` | CCR v2 生命周期客户端 |
| `cli/transports/transportUtils.ts` | 传输层选择工具（`getTransportForUrl`） |
