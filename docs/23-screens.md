# Screens 模块 (screens/)

提供 CLI 与远程 Claude Code 实例之间的 P2P 直连通信能力。包含两个子模块：

- `createDirectConnectSession.ts` — 通过 HTTP 向服务器发起会话创建请求
- `directConnectManager.ts` — 管理 WebSocket 长连接，处理消息路由与权限请求
- `types.ts` — 共享类型定义

---

## 核心类型 (types.ts)

### ServerConfig

启动直连服务器时的配置项。

| 字段 | 类型 | 说明 |
|------|------|------|
| `port` | `number` | 监听端口 |
| `host` | `string` | 监听地址 |
| `authToken` | `string` | 认证令牌 |
| `unix?` | `string` | Unix socket 路径（可选） |
| `idleTimeoutMs?` | `number` | 空闲超时（毫秒），仅适用于 detached 会话，0 = 永不超时 |
| `maxSessions?` | `number` | 最大并发会话数 |
| `workspace?` | `string` | 默认工作目录 |

### SessionState

会话生命周期状态枚举：

```typescript
type SessionState = 'starting' | 'running' | 'detached' | 'stopping' | 'stopped'
```

### SessionInfo

运行中会话的元信息。

```typescript
type SessionInfo = {
  id: string
  status: SessionState
  createdAt: number
  workDir: string
  process: ChildProcess | null
  sessionKey?: string
}
```

### SessionIndex / SessionIndexEntry

会话索引，用于在服务器重启后恢复会话。持久化到 `~/.claude/server-sessions.json`。

```typescript
type SessionIndexEntry = {
  sessionId: string
  transcriptSessionId: string
  cwd: string
  permissionMode?: string
  createdAt: number
  lastActiveAt: number
}
type SessionIndex = Record<string, SessionIndexEntry>
```

---

## 会话创建 (createDirectConnectSession.ts)

### DirectConnectError

```typescript
class DirectConnectError extends Error
```

当连接服务器、创建会话或解析响应失败时抛出。

### createDirectConnectSession

```typescript
async function createDirectConnectSession({
  serverUrl,
  authToken,
  cwd,
  dangerouslySkipPermissions,
}: {
  serverUrl: string
  authToken?: string
  cwd: string
  dangerouslySkipPermissions?: boolean
}): Promise<{ config: DirectConnectConfig; workDir?: string }>
```

**工作流程**：

1. 向 `${serverUrl}/sessions` 发起 `POST` 请求，携带 `cwd` 和可选的 `dangerously_skip_permissions` 标记
2. 验证 HTTP 响应码是否为 2xx
3. 用 Zod schema 解析响应体，提取 `session_id` 和 `ws_url`
4. 返回 `DirectConnectConfig`，其中包含 `serverUrl`、`sessionId`、`wsUrl`、`authToken`

**返回数据**：

```typescript
{
  config: DirectConnectConfig  // 用于初始化 WebSocket 连接
  workDir?: string            // 服务器分配的工作目录
}
```

---

## WebSocket 连接管理 (directConnectManager.ts)

### DirectConnectConfig

传给 `DirectConnectSessionManager` 的连接配置：

```typescript
type DirectConnectConfig = {
  serverUrl: string
  sessionId: string
  wsUrl: string
  authToken?: string
}
```

### DirectConnectCallbacks

事件回调集合：

```typescript
type DirectConnectCallbacks = {
  onMessage: (message: SDKMessage) => void
  onPermissionRequest: (
    request: SDKControlPermissionRequest,
    requestId: string,
  ) => void
  onPermissionCancelled?: (requestId: string, toolUseId: string | undefined) => void
  onConnected?: () => void
  onDisconnected?: () => void
  onError?: (error: Error) => void
}
```

### DirectConnectSessionManager

WebSocket 长连接管理器。

#### constructor

```typescript
constructor(config: DirectConnectConfig, callbacks: DirectConnectCallbacks)
```

#### connect()

```typescript
connect(): void
```

建立 WebSocket 连接。连接建立后触发 `onConnected`。

**消息处理逻辑**：

- 按换行分割数据帧，逐行解析 JSON
- `type === 'control_request'`：如果是 `can_use_tool` 子类型，触发 `onPermissionRequest`；其他子类型发送错误响应以避免服务器挂起
- `type !== 'control_response' && type !== 'keep_alive' && type !== 'control_cancel_request' && type !== 'streamlined_text' && type !== 'streamlined_tool_use_summary' && !(type === 'system' && subtype === 'post_turn_summary')`：转发给 `onMessage`
- 其他消息类型静默忽略

#### sendMessage(content)

```typescript
sendMessage(content: RemoteMessageContent): boolean
```

通过 WebSocket 发送用户消息。发送格式匹配 `--input-format stream-json` 的 `SDKUserMessage`。

- 返回 `true` 表示发送成功，`false` 表示连接未就绪

#### respondToPermissionRequest(requestId, result)

```typescript
respondToPermissionRequest(
  requestId: string,
  result: RemotePermissionResponse,
): void
```

向服务器回复工具使用权限请求。回复格式匹配 `StructuredIO` 期望的 `SDKControlResponse`。

- `result.behavior === 'allow'` 时包含 `updatedInput`
- `result.behavior === 'deny'` 时包含 `message`

#### sendInterrupt()

```typescript
sendInterrupt(): void
```

发送中断信号，取消当前正在处理的请求。发送格式匹配 `StructuredIO` 期望的 `SDKControlRequest`。

#### disconnect()

```typescript
disconnect(): void
```

关闭 WebSocket 连接并清理资源。

#### isConnected()

```typescript
isConnected(): boolean
```

返回 WebSocket 是否处于 `OPEN` 状态。

---

## P2P 直连完整工作流程

```tsx
CLI                                Server                               Claude Code
 |                                   |                                     |
 |  POST /sessions (HTTP)            |                                     |
 |---------------------------------->|                                     |
 |  { cwd, dangerously_skip_permissions }                                |
 |                                   |                                     |
 |  200 { session_id, ws_url }       |                                     |
 |<----------------------------------|                                     |
 |                                   |                                     |
 |  WebSocket CONNECT (ws_url)       |                                     |
 |----------------------------------->|                                     |
 |  (auth header if token provided)  |                                     |
 |                                   |                                     |
 |                                   |  WebSocket CONNECT to Claude Code   |
 |                                   |------------------------------------>|
 |                                   |                                     |
 |<========= WebSocket bidirectional messages ==========>|================>|
 |   user messages                          control_request (can_use_tool) |
 |   assistant responses                    control_response               |
 |   system events                           keep_alive                     |
 |                                   |                                     |
 |  sendInterrupt()                   |                                     |
 |----------------------------------->|  control_request (interrupt)       |
 |                                   |------------------------------------>|
 |                                   |                                     |
 |  disconnect()                      |                                     |
 |----------------------------------->|                                     |
```

**关键设计点**：

1. **会话创建与连接分离**：HTTP POST 创建会话并获取 `ws_url`，随后由 `DirectConnectSessionManager` 独立建立 WebSocket 连接
2. **消息路由**：WebSocket 上的消息通过 `type` 字段分发到不同处理逻辑，非 SDK 消息（control_response、keep_alive 等）由管理器内部消费，SDK 消息转发给调用方
3. **权限请求透传**：服务器的 `can_use_tool` 请求经 WebSocket 透传给 CLI，CLI 调用 `respondToPermissionRequest` 回复结果
4. **中断机制**：`sendInterrupt()` 允许 CLI 主动取消正在服务端执行的请求
