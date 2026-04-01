# Server 模块 (server/)

> 负责与云端 CCR（Claude Code Runner）会话的通信管理，包括 WebSocket 实时消息接收、HTTP 消息发送和权限请求桥接。

## 文件概览

```
remote/
├── RemoteSessionManager.ts   # 核心：远程会话生命周期管理
├── SessionsWebSocket.ts      # 底层：WebSocket 连接与重连
├── sdkMessageAdapter.ts      # 消息格式转换：SDK -> REPL
└── remotePermissionBridge.ts # 辅助：构造合成消息和工具桩
```

**模块协作图**

```tsx
REPL / CLI
    |
    | onMessage(message) / onPermissionRequest(...)
    v
useRemoteSession / useDirectConnect (hooks)  ──>  RemoteSessionManager / DirectConnectSessionManager
                                                    |
                                                    +-- SessionsWebSocket  ──(WebSocket)──>  CCR / Server
                                                    |
                                                    +-- sdkMessageAdapter  ──(convertSDKMessage)──>  REPL Message / StreamEvent
                                                    |
                                                    +-- remotePermissionBridge  ──(createSyntheticAssistantMessage / createToolStub)
```

> **注意：** Screens 层不直接实例化 `RemoteSessionManager` 或 `DirectConnectSessionManager`，而是通过 `useRemoteSession` 和 `useDirectConnect` 等 hooks 封装后使用。

---

## SessionsWebSocket.ts

**导出：** `SessionsWebSocket` 类、`SessionsWebSocketCallbacks` 类型

**职责：** 底层 WebSocket 客户端，负责与 CCR 订阅端点维持持久连接，支持 Bun 和 Node.js 双运行时。

### 连接协议

1. 连接 `wss://api.anthropic.com/v1/sessions/ws/{sessionId}/subscribe?organization_uuid=...`
2. 认证通过请求头 `Authorization: Bearer {token}` 完成
3. 接收来自 CCR 的 `SDKMessage`、`SDKControlRequest`、`SDKControlResponse`、`SDKControlCancelRequest` 四类消息

### 关键常量

| 常量 | 值 | 说明 |
|------|----|------|
| `RECONNECT_DELAY_MS` | `2000` | 重连等待时间 |
| `MAX_RECONNECT_ATTEMPTS` | `5` | 最大重连次数 |
| `PING_INTERVAL_MS` | `30000` | 心跳间隔 |
| `MAX_SESSION_NOT_FOUND_RETRIES` | `3` | 4001 错误最多重试次数 |

### `SessionsWebSocket` 构造参数

```typescript
constructor(
  private readonly sessionId: string,
  private readonly orgUuid: string,
  private readonly getAccessToken: () => string,
  private readonly callbacks: SessionsWebSocketCallbacks,
)
```

### 核心方法

- **`connect(): Promise<void>`** — 建立 WebSocket 连接，自动在 Bun（原生 WebSocket）和 Node.js（`ws` 包）之间选择实现。
- **`reconnect(): void`** — 强制重连，用于容器重启后订阅失效的场景。先关闭现有连接，500ms 后重新 `connect()`。
- **`sendControlRequest(request: SDKControlRequestInner): void`** — 发送控制请求（如 `interrupt`），自动包装为 `SDKControlRequest`（含随机 `request_id`）。
- **`sendControlResponse(response: SDKControlResponse): void`** — 发送控制响应（如权限许可/拒绝）。
- **`isConnected(): boolean`** — 返回当前连接状态。
- **`close(): void`** — 优雅关闭连接，清除所有定时器。

### 关闭码处理逻辑

- `4003`（unauthorized）— 永久关闭，不重连。
- `4001`（session not found）— 在 compaction 期间可能短暂出现，最多重试 3 次。
- 其他关闭码 — 如果之前处于 `connected` 状态，最多重连 5 次。

---

## sdkMessageAdapter.ts

**导出：** `convertSDKMessage()`、`isSessionEndMessage()`、`isSuccessResult()`、`getResultText()`、`ConvertedMessage` 类型

**职责：** 将 CCR 发送的 SDK 格式消息转换为 REPL 内部使用的 `Message` / `StreamEvent` 类型，供渲染层消费。

### `ConvertedMessage` 联合类型

```typescript
export type ConvertedMessage =
  | { type: 'message'; message: Message }
  | { type: 'stream_event'; event: StreamEvent }
  | { type: 'ignored' }
```

### `ConvertOptions` 配置

```typescript
type ConvertOptions = {
  /** 将包含 tool_result 内容块的消息转为 UserMessage */
  convertToolResults?: boolean
  /** 将用户文本消息转为 UserMessage（用于历史事件回放） */
  convertUserTextMessages?: boolean
}
```

### 转换映射表

| SDK 消息类型 | 转换结果 | 说明 |
|-------------|---------|------|
| `SDKAssistantMessage` | `AssistantMessage` | 直接映射 uuid/timestamp/error |
| `SDKPartialAssistantMessage` | `StreamEvent` | 流式事件透传 |
| `SDKResultMessage` | `SystemMessage` | 错误结果显示为 warning；成功结果忽略 |
| `SDKSystemMessage`（init） | `SystemMessage` | 显示 "Remote session initialized (model: ...)" |
| `SDKSystemMessage`（status） | `SystemMessage` 或 `ignored` | 状态更新如 "Compacting conversation…" |
| `SDKSystemMessage`（compact_boundary） | `SystemMessage`（subtype: compact_boundary） | 携带 `compactMetadata` |
| `SDKToolProgressMessage` | `SystemMessage` | 显示 "Tool {name} running for {time}s…" |
| `SDKUserMessage` | `UserMessage` 或 `ignored` | 由 `convertToolResults`/`convertUserTextMessages` 控制 |
| `auth_status` | `ignored` | 认证状态由专门逻辑处理 |
| `tool_use_summary` | `ignored` | SDK 内部事件，不在 REPL 显示 |
| `rate_limit_event` | `ignored` | SDK 内部事件 |

### 辅助函数

- **`isSessionEndMessage(msg): boolean`** — 判断消息是否结束会话（`msg.type === 'result'`）。
- **`isSuccessResult(msg: SDKResultMessage): boolean`** — 判断结果是否成功（`msg.subtype === 'success'`）。
- **`getResultText(msg: SDKResultMessage): string | null`** — 从成功结果中提取文本内容。

---

## RemoteSessionManager.ts

**导出：** `RemoteSessionManager` 类、`createRemoteSessionConfig()`、`RemoteSessionConfig`、`RemoteSessionCallbacks`、`RemotePermissionResponse` 类型

**职责：** 协调 WebSocket 订阅（接收）和 HTTP POST（发送）两种通信通道，管理权限请求生命周期。

### `RemoteSessionConfig`

```typescript
export type RemoteSessionConfig = {
  sessionId: string
  getAccessToken: () => string
  orgUuid: string
  hasInitialPrompt?: boolean      // 是否有初始 prompt 正在处理
  viewerOnly?: boolean            // 纯查看模式（claude assistant），不发送 interrupt
}
```

### `RemoteSessionCallbacks`

```typescript
export type RemoteSessionCallbacks = {
  onMessage: (message: SDKMessage) => void
  onPermissionRequest: (request: SDKControlPermissionRequest, requestId: string) => void
  onPermissionCancelled?: (requestId: string, toolUseId: string | undefined) => void
  onConnected?: () => void
  onDisconnected?: () => void
  onReconnecting?: () => void
  onError?: (error: Error) => void
}
```

### 核心方法

- **`connect(): void`** — 创建 `SessionsWebSocket` 实例并连接，注册回调。
- **`sendMessage(content: RemoteMessageContent, opts?: { uuid?: string }): Promise<boolean>`** — 通过 HTTP POST 发送用户消息到 `/v1/sessions/{id}/events`。`opts.uuid` 用于指定消息的客户端 UUID。
- **`respondToPermissionRequest(requestId: string, result: RemotePermissionResponse): void`** — 响应 CCR 发来的权限请求（allow / deny）。
- **`cancelSession(): void`** — 发送 `interrupt` 控制请求，取消远程正在运行的工具。
- **`reconnect(): void`** — 强制重连 WebSocket。
- **`disconnect(): void`** — 断开连接并清空待处理权限请求。
- **`isConnected(): boolean`** — 返回连接状态。
- **`getSessionId(): string`** — 返回会话 ID。

### 权限请求流程

```
CCR 发送 control_request (can_use_tool)
  -> RemoteSessionManager.handleControlRequest()
  -> 存入 pendingPermissionRequests Map
  -> 触发 onPermissionRequest 回调
  -> 用户在 REPL 中响应（allow / deny）
  -> respondToPermissionRequest()
  -> SessionsWebSocket.sendControlResponse()
  -> Map 中清除该请求
```

### 工厂函数

**`createRemoteSessionConfig()`** — 从 OAuth token 构建配置对象：

```typescript
export function createRemoteSessionConfig(
  sessionId: string,
  getAccessToken: () => string,
  orgUuid: string,
  hasInitialPrompt = false,
  viewerOnly = false,
): RemoteSessionConfig
```

---

## remotePermissionBridge.ts

**导出：** `createSyntheticAssistantMessage()`、`createToolStub()` 函数

**职责：** 为远程会话提供本地不存在的东西的替代品——在远程模式下，工具运行在 CCR 容器中，本地 CLI 没有真实的 `AssistantMessage` 和本地 `Tool` 定义，这两个函数分别构造合成消息和工具桩。

### `createSyntheticAssistantMessage()`

```typescript
export function createSyntheticAssistantMessage(
  request: SDKControlPermissionRequest,
  requestId: string,
): AssistantMessage
```

为权限请求创建一个假的 `AssistantMessage`。由于工具实际运行在远程容器中，本地没有真实的 AI 回复。返回的 `AssistantMessage` 包含一个 `tool_use` content block，类型为 `tool_use`，包含 `tool_use_id`、`tool_name` 和 `input`。

### `createToolStub()`

```typescript
export function createToolStub(toolName: string): Tool
```

为本地不存在的工具（如 MCP 工具）创建最小化 `Tool` 桩对象：

- `name: toolName`
- `inputSchema: {}`
- `isEnabled: () => true`
- `userFacingName: () => toolName`
- `renderToolUseMessage: (input)` — 只渲染前 3 个参数
- `call: async () => ({ data: '' })` — 空调用，响应通过远程返回
- `description: async () => ''` — 返回空字符串
- `prompt: () => ''` — 返回空字符串
- `isReadOnly: () => false`
- `isMcp: false`（实际可能为 MCP 工具，仅作标记用）
- `needsPermissions: () => true` — 始终需要权限

---

## 类型依赖关系

```
SessionsWebSocket
  └── SessionsWebSocketCallbacks
       └── SDKMessage | SDKControlRequest | SDKControlResponse | SDKControlCancelRequest
            (来自 entrypoints/agentSdkTypes.js 和 entrypoints/sdk/controlTypes.js)

RemoteSessionManager
  ├── SessionsWebSocket
  ├── RemoteSessionConfig
  ├── RemoteSessionCallbacks
  └── RemotePermissionResponse

sdkMessageAdapter
  ├── SDKAssistantMessage, SDKResultMessage, SDKSystemMessage, ...
  └── AssistantMessage, Message, StreamEvent, SystemMessage

remotePermissionBridge
  ├── SDKControlPermissionRequest (来自 entrypoints/sdk/controlTypes.js)
  └── Tool (来自 Tool.js)
```
