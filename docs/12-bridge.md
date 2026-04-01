# Bridge 模块 (bridge/)

## 架构概览

Bridge 模块是 Claude Code CLI 的 Remote Control（远程控制）核心层，允许用户通过 claude.ai 或 Claude Code 网页界面远程控制本地 CLI 会话。它建立了 CLI 与 CCR（Cloud Code Runner）后端之间的双向通信通道，使用户能够在浏览器中与本地运行的 Claude Code 会话交互。

### 两种实现路径

- **Env-Based（v1）**：基于 Environments API 的经典路径，包含 register/poll/ack/heartbeat/deregister 的完整环境生命周期
- **Env-Less（v2）**：通过 `tengu_bridge_repl_v2` GrowthBook 特性门控启用，跳过 Environments API 层，直接通过 POST /bridge → worker_jwt 建立连接

```
用户输入 → REPL → Bridge → Session Ingress WS → claude.ai
          ← Bridge ← Permission/Control ← claude.ai ←
```

### 核心生命周期（v1）

```
注册环境（registerBridgeEnvironment）
    ↓
创建会话（createBridgeSession）
    ↓
轮询工作项（pollForWork）→ 收到工作 → 连接 Ingress WS
    ↓
消息路由（handleIngressMessage）
    ↓
权限/控制响应（handleServerControlRequest）
    ↓
会话归档（archiveSession）+ 环境注销（deregisterEnvironment）
```

### 传输协议

- **v1**：HybridTransport（WebSocket 读取 + POST 写入 Session-Ingress）
- **v2**：SSETransport（读取）+ CCRClient（写入 CCR /worker/*）

### 特性门控

| 特性 | 说明 |
|------|------|
| `tengu_bridge_repl_v2` | 启用 env-less v2 模式 |
| `tengu_bridge_min_version` | v1 最低版本要求 |
| `tengu_bridge_repl_v2_config.min_version` | v2 最低版本要求 |
| `tengu_bridge_initial_history_cap` | 初始 flush 消息上限 |
| `tengu_sessions_elevated_auth_enforcement` | 强制受信任设备认证 |
| `KAIROS` | KAIROS 模式（assistant-mode bridge worker_type） |

---

## 核心接口

| 接口/类型 | 说明 |
|---------|------|
| `BridgeApiClient` | Environments API 客户端，包含 register/poll/ack/stop/deregister 等方法 |
| `BridgeConfig` | 桥接配置，包含 dir、machineName、branch、maxSessions、spawnMode 等 |
| `WorkResponse` | 轮询返回的工作项，包含 session ingress token 和 secret |
| `WorkSecret` | 解码后的工作密钥，包含 session_ingress_token、api_base_url、sources 等 |
| `SessionHandle` | 会话句柄，包含 sessionId、kill()、activities、accessToken 等 |
| `SessionSpawnOpts` | 会话 spawn 选项 |
| `ReplBridgeHandle` | 返回给调用者的桥接句柄，包含 writeMessages、sendControlRequest、teardown 等 |
| `ReplBridgeTransport` | 传输层抽象，统一 v1 HybridTransport 和 v2 SSETransport+CCRClient |
| `BridgeLogger` | 日志接口，包含 logSessionStart/logSessionComplete/updateIdleStatus 等 |
| `BoundedUUIDSet` | FIFO 有界 UUID 集合，用于消息去重（回声过滤 + 重发去重） |

---

## 入口与初始化

### initReplBridge

**用途**: REPL 的桥接初始化入口，读取引导状态（cwd、session ID、git context、OAuth、title），然后委托给 bootstrap-free core。

- **文件**: `initReplBridge.ts`

**核心逻辑**:
1. 运行时门控检查（`isBridgeEnabledBlocking`）
2. OAuth 检查（token 存在性、过期检测、跨进程退避）
3. 组织策略检查（`isPolicyAllowed('allow_remote_control')`）
4. session title 派生（显式名称 → /rename → 首条有意义用户消息 → 自动生成 slug）
5. v1/v2 路径分支（GrowthBook `tengu_bridge_repl_v2` 门控）

**关键回调**:
- `onInboundMessage` — 入站消息（用户从 claude.ai 输入）处理
- `onPermissionResponse` — 权限响应处理
- `onInterrupt` — 中断信号处理
- `onStateChange` — 状态变更通知（ready/connected/reconnecting/failed）

---

### initBridgeCore（v1 Env-Based）

**用途**: Bootstrap-free 核心，env 注册 → session 创建 → 轮询循环 → ingress WS → 清理。

- **文件**: `replBridge.ts`

**核心逻辑**:
1. 创建 BridgeApiClient
2. 注册 bridge 环境（`registerBridgeEnvironment`）
3. 创建会话（`createBridgeSession`）
4. 启动工作轮询循环（`startWorkPollLoop`）
5. 收到工作后连接 ingress WebSocket（HybridTransport 或 v2 CCR）
6. 处理入站消息和服务器控制请求
7. 清理：归档会话、停止工作、注销环境

**重连策略**:
- Strategy 1：同一环境重新注册 + `reconnectSession`（TTL 未过期时）
- Strategy 2：新建会话 + `archiveSession`（环境已删除时）
- 最多 3 次重连尝试

---

### initEnvLessBridgeCore（v2 Env-Less）

**用途**: 无 Environments API 的轻量级路径，直接通过 /bridge endpoint 获取 worker JWT。

- **文件**: `remoteBridgeCore.ts`

**核心流程**:
1. POST /v1/code/sessions（创建会话）
2. POST /v1/code/sessions/{id}/bridge（获取 worker_jwt、expires_in、worker_epoch）
3. createV2ReplTransport（SSE + CCRClient）
4. 启动 JWT 刷新调度器（proactive /bridge 重新调用）

**特点**: 无 register/poll/ack/stop/heartbeat/deregister 环境生命周期

---

## API 客户端

### bridgeApi.ts

**用途**: Environments API 的 HTTP 客户端封装，通过 OAuth 认证与 CCR 后端通信。

**工厂函数**: `createBridgeApiClient(deps)` → `BridgeApiClient`

**核心方法**:
| 方法 | 说明 |
|------|------|
| `registerBridgeEnvironment(config)` | POST /v1/environments/bridge，注册桥接环境 |
| `pollForWork(envId, envSecret, signal, reclaimOlderThanMs)` | GET /v1/environments/{id}/work/poll，轮询工作项 |
| `acknowledgeWork(envId, workId, sessionToken)` | POST /v1/environments/{id}/work/{id}/ack，确认工作项 |
| `stopWork(envId, workId, force)` | POST /v1/environments/{id}/work/{id}/stop，停止工作项 |
| `deregisterEnvironment(envId)` | DELETE /v1/environments/bridge/{envId}，注销环境 |
| `sendPermissionResponseEvent(sessionId, event, sessionToken)` | POST /v1/sessions/{id}/events，发送权限响应 |
| `archiveSession(sessionId)` | POST /v1/sessions/{id}/archive，归档会话 |
| `reconnectSession(envId, sessionId)` | POST /v1/environments/{id}/bridge/reconnect，重新连接会话 |
| `heartbeatWork(envId, workId, sessionToken)` | POST /v1/environments/{id}/work/{id}/heartbeat，发送心跳 |

**错误处理**: `BridgeFatalError`（401/403/404/410 等不可重试的错误）、OAuth 401 自动刷新重试

---

## 会话管理

### createSession.ts

**用途**: 会话创建、获取、归档和标题更新的 API 调用。

**函数**:
- `createBridgeSession()` — POST /v1/sessions，创建桥接会话
- `getBridgeSession()` — GET /v1/sessions/{id}，获取会话信息（用于 --session-id 恢复）
- `archiveBridgeSession()` — POST /v1/sessions/{id}/archive，归档会话
- `updateBridgeSessionTitle()` — PATCH /v1/sessions/{id}，更新会话标题

---

## 消息与传输

### bridgeMessaging.ts

**用途**: 传输层共享的消息处理工具，提取自 replBridge.ts 以供 v1 和 v2 核心共用。

**核心函数**:
| 函数 | 说明 |
|------|------|
| `isSDKMessage(value)` | 类型谓词，验证是否为 SDKMessage |
| `isSDKControlResponse(value)` | 类型谓词，验证是否为 control_response |
| `isSDKControlRequest(value)` | 类型谓词，验证是否为 control_request |
| `isEligibleBridgeMessage(m)` | 判断消息是否应转发（user/assistant/local_command） |
| `extractTitleText(m)` | 从消息中提取标题文本 |
| `handleIngressMessage(data, ...)` | 解析 WS 消息并路由到对应处理器 |
| `handleServerControlRequest(request, handlers)` | 处理服务器控制请求（initialize、set_model、interrupt 等） |
| `makeResultMessage(sessionId)` | 构建 result 消息用于会话归档 |
| `BoundedUUIDSet` | FIFO 有界 UUID 集合（容量 2000） |

---

### replBridgeTransport.ts

**用途**: 传输层抽象，统一 v1 HybridTransport 和 v2 SSETransport+CCRClient 的差异。

**工厂函数**:
- `createV1ReplTransport(hybrid)` — 适配 HybridTransport
- `createV2ReplTransport(opts)` — 创建 v2 传输（SSETransport + CCRClient）

**ReplBridgeTransport 接口**:
```typescript
{
  write(message): Promise<void>
  writeBatch(messages): Promise<void>
  close(): void
  isConnectedStatus(): boolean
  getStateLabel(): string
  setOnData(callback): void
  setOnClose(callback): void
  setOnConnect(callback): void
  connect(): void
  getLastSequenceNum(): number
  droppedBatchCount: number
  reportState(state): void
  reportMetadata(metadata): void
  reportDelivery(eventId, status): void
  flush(): Promise<void>
}
```

---

## 认证与配置

### bridgeConfig.ts

**用途**: 桥接认证和 URL 配置，整合 ANT-only 的 CLAUDE_BRIDGE_* 开发覆盖。

**函数**:
| 函数 | 说明 |
|------|------|
| `getBridgeTokenOverride()` | 获取 ANT-only CLAUDE_BRIDGE_OAUTH_TOKEN 覆盖 |
| `getBridgeBaseUrlOverride()` | 获取 ANT-only CLAUDE_BRIDGE_BASE_URL 覆盖 |
| `getBridgeAccessToken()` | 获取桥接访问令牌（覆盖优先，否则 OAuth） |
| `getBridgeBaseUrl()` | 获取桥接 API 基础 URL（覆盖优先，否则生产配置） |

---

### trustedDevice.ts

**用途**: 受信任设备令牌管理，用于 CCR v2 的 Elevated Auth 认证。

**函数**: `getTrustedDeviceToken()` — 返回 X-Trusted-Device-Token header 值

---

### jwtUtils.ts

**用途**: JWT 令牌刷新调度器，用于 env-less 桥接的主动令牌刷新。

---

### workSecret.ts

**用途**: 工作密钥的解码和 URL 构建。

**函数**:
| 函数 | 说明 |
|------|------|
| `decodeWorkSecret(secret)` | 解码 base64url 编码的工作密钥并验证 version === 1 |
| `buildSdkUrl(apiBaseUrl, sessionId)` | 构建 v1 WebSocket SDK URL |
| `buildCCRv2SdkUrl(apiBaseUrl, sessionId)` | 构建 CCR v2 session URL |
| `sameSessionId(a, b)` | 比较两个 session ID（忽略 tagged 前缀差异） |
| `registerWorker(sessionUrl, accessToken)` | 注册 CCR v2 worker，返回 worker_epoch |

---

### envLessBridgeConfig.ts

**用途**: env-less 桥接的默认配置，包含 GrowthBook 驱动的参数。

---

### pollConfig.ts / pollConfigDefaults.ts

**用途**: 轮询间隔配置，包含 GrowthBook 驱动的可调参数。

---

## 状态与指针

### bridgePointer.ts

**用途**: 崩溃恢复指针文件管理，记录当前桥接会话的 environmentId 和 sessionId。

**函数**:
| 函数 | 说明 |
|------|------|
| `writeBridgePointer(dir, data)` | 写入 bridgePointer.json |
| `readBridgePointer(dir)` | 读取指针文件 |
| `clearBridgePointer(dir)` | 删除指针文件 |

**指针文件结构**: `{ sessionId, environmentId, source: 'repl' }`

**TTL**: 4 小时（BRIDGE_POINTER_TTL_MS），超过则视为过期

---

### sessionIdCompat.ts

**用途**: session ID 兼容性处理，`cse_*` ↔ `session_*` 之间的转换。

**函数**:
- `toCompatSessionId(id)` — v2 cse_* → v1 兼容 session_* 格式
- `toInfraSessionId(id)` — session_* → cse_* 格式
- `setCseShimGate(enabled)` — 设置 CSE shim kill switch

---

## 权限与状态

### bridgePermissionCallbacks.ts

**用途**: 权限回调处理，用于处理来自 claude.ai 的权限请求。

---

### bridgeStatusUtil.ts

**用途**: 桥接状态工具函数。

---

### bridgeUI.ts

**用途**: 桥接 UI 渲染（TTY 输出）。

---

## 调试与工具

### bridgeDebug.ts

**用途**: ANT-only 调试工具，用于故障注入和调试。

**函数**: `wrapApiForFaultInjection(api)` — 包装 API 以注入 poll/register/heartbeat 故障

---

### debugUtils.ts

**用途**: 共享调试工具函数。

**函数**:
| 函数 | 说明 |
|------|------|
| `logBridgeSkip(reason, message, isError?)` | 记录跳过原因 |
| `describeAxiosError(err)` | 描述 Axios 错误 |
| `extractHttpStatus(err)` | 提取 HTTP 状态码 |
| `debugBody(obj)` | 调试日志体 |

---

## 其他组件

### capacityWake.ts

**用途**: 容量唤醒信号，当传输丢失时提前唤醒 at-capacity 睡眠状态，使轮询循环立即切换到快速轮询。

---

### flushGate.ts

**用途**: 消息刷新闸门，在初始历史消息刷新期间阻塞新消息，防止服务器接收乱序消息。

---

### inboundAttachments.ts

**用途**: 入站附件处理。

---

### inboundMessages.ts

**用途**: 入站消息处理。

---

### sessionRunner.ts

**用途**: 会话运行器（用于 standalone bridge 模式）。

---

### codeSessionApi.ts

**用途**: 代码会话 API（daemon 专用，HTTP-only）。

---

### bridgeMain.ts

**用途**: standalone `claude remote-control` 的主入口点。

---

## 文件索引

| 文件 | 用途 |
|------|------|
| `bridgeApi.ts` | Environments API HTTP 客户端封装 |
| `bridgeConfig.ts` | 桥接认证/URL 配置 |
| `bridgeDebug.ts` | ANT-only 故障注入调试 |
| `bridgeEnabled.ts` | 运行时门控和版本检查 |
| `bridgeMain.ts` | standalone remote-control 入口 |
| `bridgeMessaging.ts` | 消息处理和路由共享工具 |
| `bridgePermissionCallbacks.ts` | 权限回调处理 |
| `bridgePointer.ts` | 崩溃恢复指针文件管理 |
| `bridgeStatusUtil.ts` | 状态工具函数 |
| `bridgeUI.ts` | TTY UI 渲染 |
| `capacityWake.ts` | 容量唤醒信号 |
| `codeSessionApi.ts` | daemon 会话 API（HTTP-only） |
| `createSession.ts` | 会话创建/归档/标题更新 |
| `debugUtils.ts` | 共享调试工具 |
| `envLessBridgeConfig.ts` | env-less 桥接默认配置 |
| `flushGate.ts` | 初始刷新闸门 |
| `inboundAttachments.ts` | 入站附件处理 |
| `inboundMessages.ts` | 入站消息处理 |
| `initReplBridge.ts` | REPL 桥接初始化入口 |
| `jwtUtils.ts` | JWT 刷新调度器 |
| `pollConfig.ts` | 轮询间隔配置 |
| `pollConfigDefaults.ts` | 轮询间隔默认值 |
| `remoteBridgeCore.ts` | env-less（v2）桥接核心 |
| `replBridge.ts` | env-based（v1）桥接核心 |
| `replBridgeHandle.ts` | ReplBridgeHandle 类型定义 |
| `replBridgeTransport.ts` | 传输层抽象 |
| `sessionIdCompat.ts` | session ID 兼容性处理 |
| `sessionRunner.ts` | 会话运行器 |
| `trustedDevice.ts` | 受信任设备令牌 |
| `types.ts` | 核心类型定义 |
| `workSecret.ts` | 工作密钥解码和 URL 构建 |
