# Plugins 模块 (plugins/)

`assistant/sessionHistory.ts` 提供会话历史翻页读取功能，支持从 Teleport API 按页获取 Claude 会话事件。

## 文件概览

---

## 核心类型

### `HistoryPage`
分页结果结构。

| 字段 | 类型 | 说明 |
|------|------|------|
| `events` | `SDKMessage[]` | 该页中的消息列表，按时间正序排列 |
| `firstId` | `string \| null` | 该页最旧事件的 ID，用于翻页的 `before_id` 游标 |
| `hasMore` | `boolean` | `true` 表示还有更旧的事件可供加载 |

### `HistoryAuthCtx`
认证上下文，在翻页过程中复用。

| 字段 | 类型 | 说明 |
|------|------|------|
| `baseUrl` | `string` | API 请求根 URL，来源于 `getOauthConfig().BASE_API_URL`（即 `${BASE_API_URL}/v1/sessions/${sessionId}/events`） |
| `headers` | `Record<string, string>` | 已包含 OAuth Token、Beta 标识和组织 UUID（含 `anthropic-beta: ccr-byoc-2025-07-29`） |

### `SessionEventsResponse`
Teleport API 返回的原始响应类型。

| 字段 | 类型 | 说明 |
|------|------|------|
| `data` | `SDKMessage[]` | 事件列表 |
| `has_more` | `boolean` | 是否还有更多事件 |
| `first_id` | `string \| null` | 该页最旧事件 ID |
| `last_id` | `string \| null` | 该页最新事件 ID |

## 核心函数

### `createHistoryAuthCtx(sessionId)`
预构建认证上下文，内部调用 `prepareApiRequest()` 获取访问令牌和 org UUID，拼接完整的请求 URL 和 HTTP 头。

**参数：** `sessionId: string` — 会话 ID

**返回：** `Promise<HistoryAuthCtx>`

---

### `fetchLatestEvents(ctx, limit?)`
获取最新的一页事件（最新在前，翻页时 `has_more=true` 表示还有更旧的）。

**参数：**
- `ctx: HistoryAuthCtx` — 认证上下文
- `limit?: number` — 每页数量，默认 100

**返回：** `Promise<HistoryPage | null>` — 失败时返回 `null`

---

### `fetchOlderEvents(ctx, beforeId, limit?)`
在已有游标基础上加载更旧的一页事件。

**参数：**
- `ctx: HistoryAuthCtx` — 认证上下文
- `beforeId: string` — 上一页 `firstId` 作为游标
- `limit?: number` — 每页数量，默认 100

**返回：** `Promise<HistoryPage | null>` — 失败时返回 `null`

## 内部实现

`fetchPage()` 是底层请求函数：
- 使用 `axios.get`，超时 15 秒
- `validateStatus: () => true` 抑制 HTTP 错误抛出，由上层统一处理
- 任何网络错误或非 200 响应均返回 `null`

## 常量

```typescript
export const HISTORY_PAGE_SIZE = 100
```

默认分页大小。
