# 上游代理 (upstreamproxy/)

本节文档覆盖 `upstreamproxy/` 目录下的两个模块，它们共同实现了 CCR 会话容器内的透明上游代理。该代理将 CLI 发出的 HTTPS 请求通过本地 CONNECT-over-WebSocket 中继传输到 CCR 网关，由网关完成 TLS MITM 并注入组织配置凭证（如 Datadog API Key）后转发至真实上游。

设计原则：任何一步失败均安全降级（fail open），代理的破坏不得影响一个原本正常运行的会话；会话令牌仅驻留堆内存，令牌文件在代理确认就绪后立即删除，同时通过 `prctl(PR_SET_DUMPABLE, 0)` 阻止同 UID 下的 ptrace 读取堆。

---

## upstreamproxy.ts — 初始化入口与生命周期管理

### 概述

`upstreamproxy.ts` 是上游代理的初始化与协调模块。它在 CCR 会话容器启动时依次完成以下工作：读取会话令牌文件、禁用进程可 dumpable 能力（防止同 UID ptrace）、下载并拼接 CCR MITM CA 证书到系统 CA bundle、启动本地 CONNECT 中继（见 relay.ts）、安全删除令牌文件（仅在中继确认就绪后）、并通过环境变量将代理配置暴露给所有子进程。

### 导出常量

#### `SESSION_TOKEN_PATH`

```typescript
export const SESSION_TOKEN_PATH = '/run/ccr/session_token'
```

会话令牌文件的容器内路径。Token 内容在读取后保留在堆内存中，文件在中继 listen 成功后由父进程 unlink 删除，确保 supervisor 重启时若 CA 下载或监听失败仍可重试。

### 导出类型

#### `UpstreamProxyState`

```typescript
type UpstreamProxyState = {
  enabled: boolean
  port?: number
  caBundlePath?: string
}
```

`initUpstreamProxy` 的返回值。

| 字段 | 类型 | 含义 |
|------|------|------|
| `enabled` | `boolean` | 代理是否成功启用 |
| `port` | `number?` | 本地 CONNECT 中继监听的端口（仅 `enabled: true` 时有值） |
| `caBundlePath` | `string?` | 拼接后 CA 证书文件路径（仅 `enabled: true` 时有值） |

### 导出函数

#### `initUpstreamProxy`

```typescript
export async function initUpstreamProxy(opts?: {
  tokenPath?: string
  systemCaPath?: string
  caBundlePath?: string
  ccrBaseUrl?: string
}): Promise<UpstreamProxyState>
```

初始化上游代理。调用时机：会话容器启动后，从 `init.ts` 调用一次。条件判断链：

1. `CLAUDE_CODE_REMOTE` 未设置 → 直接返回 `{ enabled: false }`（本地开发环境）
2. `CCR_UPSTREAM_PROXY_ENABLED` 未设置 → 直接返回（服务端 GrowthBook 评估注入）
3. `CLAUDE_CODE_REMOTE_SESSION_ID` 缺失 → 记录警告，返回 disabled
4. 令牌文件读取失败 → 返回 disabled
5. 调用 `setNonDumpable()` 禁用 same-UID ptrace 能力
6. 调用 `downloadCaBundle` 下载并拼接 CA bundle；失败则禁用
7. 调用 `startUpstreamProxyRelay` 启动 WebSocket 中继；失败则禁用
8. 中继就绪后 unlink 令牌文件，注册清理函数，返回 `{ enabled: true, port, caBundlePath }`

| 参数 | 类型 | 默认值 | 含义 |
|------|------|--------|------|
| `opts.tokenPath` | `string?` | `/run/ccr/session_token` | 令牌文件路径（测试用） |
| `opts.systemCaPath` | `string?` | `/etc/ssl/certs/ca-certificates.crt` | 系统 CA bundle 路径 |
| `opts.caBundlePath` | `string?` | `~/.ccr/ca-bundle.crt` | 拼接后 CA bundle 输出路径 |
| `opts.ccrBaseUrl` | `string?` | `process.env.ANTHROPIC_BASE_URL ?? 'https://api.anthropic.com'` | CCR API 地址 |

#### `getUpstreamProxyEnv`

```typescript
export function getUpstreamProxyEnv(): Record<string, string>
```

返回应注入到所有 agent 子进程的环境变量字典。代理未启用时，若父进程已设置 `HTTPS_PROXY` + `SSL_CERT_FILE`（即本进程由已启用代理的父进程 fork），则透传这些变量；否则返回空对象。

代理启用时的返回值：

| 变量 | 值 | 含义 |
|------|----|------|
| `HTTPS_PROXY` | `http://127.0.0.1:<port>` | 本地中继地址（仅 HTTPS，HTTP 无凭证注入需求） |
| `https_proxy` | 同上 | 小写形式（部分运行时要求） |
| `NO_PROXY` / `no_proxy` | 逗号分隔绕过列表 | 包含 `localhost`、RFC1918 私网段、IMDS 范围、`*.anthropic.com`、`*.github.com`、主流包 registry |
| `SSL_CERT_FILE` | `~/.ccr/ca-bundle.crt` | Python requests / curl |
| `NODE_EXTRA_CA_CERTS` | 同上 | Node.js 额外信任的 CA |
| `REQUESTS_CA_BUNDLE` | 同上 | Python httpx / requests |
| `CURL_CA_BUNDLE` | 同上 | curl（显式指定 CA） |

`NO_PROXY` 中 `anthropic.com` 三种形式（`anthropic.com` / `.anthropic.com` / `*.anthropic.com`）是为了覆盖 Bun、curl、Go（glob 匹配）、Python urllib/httpx（suffix 匹配，丢弃前导点）等多种运行时对 NO_PROXY 解析的差异。

#### `resetUpstreamProxyForTests`

```typescript
export function resetUpstreamProxyForTests(): void
```

测试专用：将模块级 `state` 重置为 `{ enabled: false }`，用于测试用例间状态隔离。

### 内部函数

#### `readToken`

```typescript
async function readToken(path: string): Promise<string | null>
```

读取并返回指定路径的令牌内容（trim 后）。文件不存在返回 `null`；其他错误记录警告并返回 `null`。

#### `setNonDumpable`

```typescript
function setNonDumpable(): void
```

通过 `libc.so.6` 的 `prctl(PR_SET_DUMPABLE, 0)` FFI 调用（`bun:ffi`），阻止同 UID 进程对本进程堆内存的 ptrace 读取，防止 prompt 注入的 `gdb -p $PPID` 窃取令牌。Linux-only，Bun 运行时下静默 no-op。

#### `downloadCaBundle`

```typescript
async function downloadCaBundle(
  baseUrl: string,
  systemCaPath: string,
  outPath: string,
): Promise<boolean>
```

从 `${baseUrl}/v1/code/upstreamproxy/ca-cert` 获取 CCR MITM CA PEM（5 秒超时），与系统 CA bundle 拼接后写入 `outPath`。成功返回 `true`，失败记录警告并返回 `false`。拼接策略：`systemCa + '\n' + ccrCa`，确保原有信任链完整。

---

## relay.ts — CONNECT-over-WebSocket 中继实现

### 概述

`relay.ts` 实现了本地 TCP 代理服务器，接收来自 curl/gh/kubectl 等工具的 HTTP CONNECT 请求，并将字节流通过 WebSocket 隧道传输到 CCR 网关。网关侧终止隧道、执行 MITM TLS、注入组织凭证后转发到真实上游。

协议使用 `UpstreamProxyChunk` protobuf 消息包装字节（`message UpstreamProxyChunk { bytes data = 1; }`），手写 protobuf 编码以避免热路径引入额外运行时依赖。运行时支持 Bun 原生 `Bun.listen` 和 Node.js `net.createServer` 两种路径，由 `startUpstreamProxyRelay` 统一分发。

### 导出类型

#### `UpstreamProxyRelay`

```typescript
export type UpstreamProxyRelay = {
  port: number
  stop: () => void
}
```

中继实例的句柄。调用方据此将 `HTTPS_PROXY` 指向 `http://127.0.0.1:<port>`。

| 字段 | 类型 | 含义 |
|------|------|------|
| `port` | `number` | 中继绑定的临时端口 |
| `stop` | `() => void` | 关闭中继服务器 |

### 导出函数

#### `encodeChunk`

```typescript
export function encodeChunk(data: Uint8Array): Uint8Array
```

手写 protobuf 编码 `UpstreamProxyChunk { bytes data = 1 }`。

| 字段 | 值 |
|------|-----|
| field_number | 1 |
| wire_type | 2 (Length-delimited) |
| tag byte | `0x0a` (`(1 << 3) \| 2`) |

编码结构：`[0x0a][varint-length][data]`。支持 `data.length === 0` 的情况（keepalive）。

#### `decodeChunk`

```typescript
export function decodeChunk(buf: Uint8Array): Uint8Array | null
```

解析 `UpstreamProxyChunk`。返回 `data` 字段内容；格式错误返回 `null`；零长度 chunk 返回空 `Uint8Array`（keepalive 语义）。

| 参数 | 类型 | 含义 |
|------|------|------|
| `buf` | `Uint8Array` | 原始 WebSocket 二进制帧数据 |

#### `startUpstreamProxyRelay`

```typescript
export async function startUpstreamProxyRelay(opts: {
  wsUrl: string
  sessionId: string
  token: string
}): Promise<UpstreamProxyRelay>
```

启动上游代理中继。根据运行时类型分发到 `startBunRelay` 或 `startNodeRelay`。

| 参数 | 类型 | 含义 |
|------|------|------|
| `opts.wsUrl` | `string` | CCR WebSocket 端点（如 `wss://api.anthropic.com/v1/code/upstreamproxy/ws`） |
| `opts.sessionId` | `string` | CCR 会话 ID（Basic 认证用） |
| `opts.token` | `string` | 会话令牌（Basic + Bearer 认证用） |

认证头构建：
- `Authorization`（透传进隧道 CONNECT）：`Basic ${base64(sessionId:token)}`
- WS Upgrade 请求头：`Bearer ${token}`（网关 PRIVATE_API 认证）

#### `startNodeRelay`

```typescript
export async function startNodeRelay(
  wsUrl: string,
  authHeader: string,
  wsAuthHeader: string,
): Promise<UpstreamProxyRelay>
```

Node.js 版本的 TCP 服务器实现。测试可直接调用此函数绕过运行时检测。

使用 `createServer` + `ws` 包（而非 `globalThis.WebSocket`），以便通过显式 agent 经过 HTTP CONNECT 代理建立 WebSocket（undici 的 `globalThis.WebSocket` 不咨询全局 dispatcher）。

### 内部类型

#### `ConnState`

```typescript
type ConnState = {
  ws?: WebSocketLike
  connectBuf: Buffer
  pinger?: ReturnType<typeof setInterval>
  pending: Buffer[]
  wsOpen: boolean
  established: boolean
  closed: boolean
}
```

每个 TCP 连接维护的协议状态机。

| 字段 | 类型 | 含义 |
|------|------|------|
| `ws` | `WebSocketLike?` | 已建立的 WebSocket 隧道（phase 2 使用） |
| `connectBuf` | `Buffer` | 累积的 CONNECT 请求头（phase 1 使用） |
| `pinger` | `ReturnType<typeof setInterval>?` | 应用层 keepalive 定时器 |
| `pending` | `Buffer[]` | WS 握手完成前到达的字节（TCP 粘包/粘半包），待 onopen 后 flush |
| `wsOpen` | `boolean` | WS handshake 是否完成 |
| `established` | `boolean` | 服务器 200 已转发、隧道已承载 TLS（此后不再写明文 502） |
| `closed` | `boolean` | 连接已关闭标记（防止 `ws.onerror` + `ws.onclose` 重复清理） |

#### `ClientSocket`

```typescript
type ClientSocket = {
  write: (data: Uint8Array | string) => void
  end: () => void
}
```

与运行时解耦的本地 socket 抽象。Bun 实现处理写回压（`sock.write()` 返回实际写入字节数，剩余数据入队等待 `drain` 事件）；Node 实现依赖 `net.Socket` 内部缓冲。

### 协议细节

#### CONNECT 请求处理
- 累积数据至 `\r\n\r\n` 分隔符（部分客户端可能分多次发送）
- 解析首行 `CONNECT <host:port> HTTP/1.[01]`；非 CONNECT 方法返回 `405 Method Not Allowed`
- CONNECT 首行之后、 `\r\n\r\n` 之前的字节（可能是 TCP 粘包的 TLS ClientHello）存入 `pending`，待 WebSocket 握手完成后 flush
- 请求头缓冲区超过 8192 字节仍无分隔符：返回 `400 Bad Request`

#### WebSocket 握手
- 请求头 `Content-Type: application/proto` 触发服务端 `protojson.Unmarshaling`（而非默认 JSON 模式）
- `ws.onopen` 发送的第一个 chunk 载荷为 `CONNECT <line>\r\nProxy-Authorization: <auth>\r\n\r\n`，供服务器完成隧道认证并获知目标 host:port

#### Chunk 分片与 keepalive
- `forwardToWs` 每次最多发送 `MAX_CHUNK_BYTES`（512 KB），超过则分片发送
- `sendKeepalive` 每 30 秒发送零长度 `encodeChunk` 作为应用层 keepalive（sidecar 空闲超时 50 秒，留有安全余量）

#### 错误处理
- `ws.onerror`：若 `established === false`（隧道未承载 TLS）则向客户端写明文 `HTTP/1.1 502 Bad Gateway`，防止污染已进入 TLS 阶段的字节流
- `ws.onclose` / `cleanupConn`：清除 pinger、关闭 WebSocket、置空引用

### 架构总览

```
curl / gh / kubectl / npm
    │  HTTPS_PROXY=http://127.0.0.1:<port>
    ▼
┌──────────────────────────────────────┐
│  relay.ts — 本地 TCP 中继             │
│  127.0.0.1:<port>                    │
│  解析 HTTP CONNECT 请求              │
└──────────────┬───────────────────────┘
               │ WebSocket
               │ Content-Type: application/proto
               │ Authorization: Bearer <token>
               │ Proxy-Authorization: Basic <base64(sessionId:token)>
               ▼
┌──────────────────────────────────────┐
│  CCR 服务器                          │
│  终止 WebSocket 隧道                 │
│  MITM TLS，注入组织凭证（DD-API-KEY）│
│  转发至真实上游                       │
└──────────────────────────────────────┘
```

整个链路所有故障点均设计为"静默禁用"：代理未就绪时 CLI 仍以直连方式运行，不会因代理配置失败而崩溃。
