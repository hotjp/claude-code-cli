# React Context 状态管理 (context/)

## 概述

`context/` 目录下的 9 个 Context Provider 文件统一采用 **外部 Store（非 React 状态）+ `useSyncExternalStore` 精确订阅** 的模式。这种设计与 React 内置的 `useState` 不同：状态存储在 Context Provider 之外的普通 JavaScript 对象中，React 通过 `useSyncExternalStore` 实现精确订阅——只有当订阅的特定 slice 变化时才触发重渲染，从而避免不必要的大型重渲染。

典型模式如下：

```typescript
// 1. 外部 Store（非 React 状态）
const store = createStore(DEFAULT_STATE);

// 2. Context Provider 包裹子组件
<VoiceContext.Provider value={store}>{children}</VoiceContext.Provider>

// 3. 精确订阅特定 slice — 只有该 slice 变化时才重渲染
const voiceState = useSyncExternalStore(store.subscribe, () => selector(store.getState()));
```

与 `useState` 的区别在于：外部 Store 的引用稳定，Provider 不因内部状态变化而重渲染；消费者通过 selector 函数按需获取状态片段，实现细粒度订阅。

---

## 文件索引

| 文件 | 用途 |
|------|------|
| `voice.tsx` | 语音输入状态管理 |
| `modalContext.tsx` | 模态对话框布局上下文 |
| `stats.tsx` | 会话级指标统计 |
| `notifications.tsx` | 通知队列管理 |
| `QueuedMessageContext.tsx` | 排队消息上下文 |
| `mailbox.tsx` | Mailbox 工具 Context |
| `overlayContext.tsx` | 浮层追踪 |
| `fpsMetrics.tsx` | 帧率指标 |
| `promptOverlayContext.tsx` | 提示词浮层 Portal |

---

## voice.tsx — 语音输入状态管理

语音输入的状态管理，使用外部 Store 配合 `useSyncExternalStore` 实现精确订阅。

### 导出类型

#### `VoiceState`

```typescript
export type VoiceState = {
  voiceState: 'idle' | 'recording' | 'processing'
  voiceError: string | null
  voiceInterimTranscript: string
  voiceAudioLevels: number[]
  voiceWarmingUp: boolean
}
```

语音输入的完整状态。

| 字段 | 类型 | 说明 |
|------|------|------|
| `voiceState` | `'idle' \| 'recording' \| 'processing'` | 当前语音状态 |
| `voiceError` | `string \| null` | 错误信息 |
| `voiceInterimTranscript` | `string` | 实时转写的中间结果 |
| `voiceAudioLevels` | `number[]` | 音频音量水平数组 |
| `voiceWarmingUp` | `boolean` | 是否正在预热 |

### 导出接口

#### `VoiceStore`

```typescript
type VoiceStore = Store<VoiceState>
```

基于 `Store<VoiceState>` 的语音状态存储接口，提供 `getState`、`setState`、`subscribe` 方法。

### 导出函数

#### `VoiceProvider`

```typescript
export function VoiceProvider({ children }: Props): React.ReactNode
```

语音状态 Provider。内部使用 `useState` 创建单一 Store 实例（稳定引用），children 永远不会因 Store 变化而重渲染。

#### `useVoiceState`

```typescript
export function useVoiceState<T>(selector: (state: VoiceState) => T): T
```

订阅 VoiceState 的某个切片。仅当选中的值变化时（通过 `Object.is` 比较）才会重渲染。

**示例**：
```typescript
const isRecording = useVoiceState(s => s.voiceState === 'recording')
```

#### `useSetVoiceState`

```typescript
export function useSetVoiceState(): (updater: (prev: VoiceState) => VoiceState) => void
```

获取语音状态 setter。返回稳定引用，永不导致重渲染。`store.setState` 是同步的，调用后可立即通过 `getVoiceState()` 读取新值（`VoiceKeybindingHandler` 依赖此行为）。

#### `useGetVoiceState`

```typescript
export function useGetVoiceState(): () => VoiceState
```

获取同步状态读取器，用于在事件处理器内部读取新鲜状态（而非订阅）。不触发重渲染。

---

## modalContext.tsx — 模态对话框布局上下文

由 `FullscreenLayout` 设置，用于 slash-command 对话框的绝对定位底部面板。帮助消费者组件抑制顶部框架、计算分页大小、管理滚动重置。

### 导出类型

#### `ModalCtx`

```typescript
type ModalCtx = {
  rows: number
  columns: number
  scrollRef: RefObject<ScrollBoxHandle | null> | null
}
```

模态插槽的布局信息。

| 字段 | 类型 | 说明 |
|------|------|------|
| `rows` | `number` | 可用行数 |
| `columns` | `number` | 可用列数 |
| `scrollRef` | `RefObject<ScrollBoxHandle \| null> \| null` | ScrollBox 句柄引用 |

### 导出 Context

#### `ModalContext`

```typescript
export const ModalContext = createContext<ModalCtx | null>(null)
```

值为 `null` 表示不在模态插槽内。

### 导出函数

#### `useIsInsideModal`

```typescript
export function useIsInsideModal(): boolean
```

判断当前组件是否在模态插槽内。

#### `useModalOrTerminalSize`

```typescript
export function useModalOrTerminalSize(fallback: {
  rows: number
  columns: number
}): { rows: number; columns: number }
```

返回模态内可用内容区域大小，否则回退到传入的终端尺寸。当组件需要限制可见内容高度时应使用此 hook（而非 `useTerminalSize()`），因为模态内部区域小于终端。

#### `useModalScrollRef`

```typescript
export function useModalScrollRef(): RefObject<ScrollBoxHandle | null> | null
```

获取模态内 ScrollBox 的引用，用于 Tab 切换时重置滚动位置。

---

## stats.tsx — 会话级指标统计

基于外部 Store 的指标收集系统，支持 Counter、Gauge、Timer（直方图）、Set 四种指标类型，进程退出时自动将指标写入项目配置。

### 导出类型

#### `StatsStore`

```typescript
export type StatsStore = {
  increment(name: string, value?: number): void
  set(name: string, value: number): void
  observe(name: string, value: number): void
  add(name: string, value: string): void
  getAll(): Record<string, number>
}
```

指标存储接口。

| 方法 | 说明 |
|------|------|
| `increment(name, value?)` | 计数器递增（默认 +1） |
| `set(name, value)` | 设置 gauge 绝对值 |
| `observe(name, value)` | 观察值，加入直方图（使用蓄水池采样） |
| `add(name, value)` | 向 Set 添加字符串值 |
| `getAll()` | 返回所有指标，含直方图的 min/max/avg/p50/p95/p99 |

#### `Histogram`

```typescript
type Histogram = {
  reservoir: number[]
  count: number
  sum: number
  min: number
  max: number
}
```

直方图内部结构，使用 Algorithm R 蓄水池采样（大小 1024）。

### 导出函数

#### `createStatsStore`

```typescript
export function createStatsStore(): StatsStore
```

创建新的 StatsStore 实例。

#### `StatsProvider`

```typescript
export function StatsProvider({ store?: StatsStore, children }: Props): React.ReactNode
```

Stats Provider。接受可选的外部 Store，否则创建内部 Store。进程退出时自动将 `getAll()` 结果写入 `lastSessionMetrics`。

#### `useStats`

```typescript
export function useStats(): StatsStore
```

获取 StatsStore 实例。必须在 `StatsProvider` 内使用。

#### `useCounter`

```typescript
export function useCounter(name: string): (value?: number) => void
```

创建命名计数器。返回的函数调用 `store.increment(name, value)`。

**示例**：
```typescript
const increment = useCounter('user.messages')
increment() // +1
increment(5) // +5
```

#### `useGauge`

```typescript
export function useGauge(name: string): (value: number) => void
```

创建命名 Gauge。返回的函数调用 `store.set(name, value)`。

**示例**：
```typescript
const setCpuUsage = useGauge('system.cpu')
setCpuUsage(0.75)
```

#### `useTimer`

```typescript
export function useTimer(name: string): (value: number) => void
```

创建命名 Timer（直方图）。返回的函数调用 `store.observe(name, value)`。

**示例**：
```typescript
const recordLatency = useTimer('request.latency')
recordLatency(42) // 毫秒
// getAll() 返回 { request_latency_count: N, request_latency_min: X, ... }
```

#### `useSet`

```typescript
export function useSet(name: string): (value: string) => void
```

创建命名 Set。返回的函数调用 `store.add(name, value)`。

**示例**：
```typescript
const addUserId = useSet('session.userIds')
addUserId('user_123')
// getAll() 返回 { 'session.userIds': set.size }
```

---

## notifications.tsx — 通知队列管理

基于 `useAppStateStore` 的通知队列系统，支持优先级排序、自动超时、折叠（fold）和失效（invalidate）机制。

### 导出类型

#### `Priority`

```typescript
type Priority = 'low' | 'medium' | 'high' | 'immediate'
```

通知优先级，`immediate` 最高且会中断当前通知。

#### `BaseNotification`

```typescript
type BaseNotification = {
  key: string
  invalidates?: string[]
  priority: Priority
  timeoutMs?: number
  fold?: (accumulator: Notification, incoming: Notification) => Notification
}
```

所有通知类型的基类。

| 字段 | 类型 | 说明 |
|------|------|------|
| `key` | `string` | 唯一标识 |
| `invalidates` | `string[]` | 此通知使其他通知失效（从队列和当前显示中移除） |
| `priority` | `Priority` | 优先级 |
| `timeoutMs` | `number` | 显示超时（默认 8000ms） |
| `fold` | `(acc, incoming) => Notification` | 相同 key 的合并函数，类似 `Array.reduce()` |

#### `TextNotification`

```typescript
type TextNotification = BaseNotification & {
  text: string
  color?: keyof Theme
}
```

文本通知。

#### `JSXNotification`

```typescript
type JSXNotification = BaseNotification & {
  jsx: React.ReactNode
}
```

自定义 JSX 通知。

#### `Notification`

```typescript
export type Notification = TextNotification | JSXNotification
```

通知的联合类型。

#### `AddNotificationFn`

```typescript
type AddNotificationFn = (content: Notification) => void
```

添加通知函数。

#### `RemoveNotificationFn`

```typescript
type RemoveNotificationFn = (key: string) => void
```

移除通知函数。

### 导出函数

#### `useNotifications`

```typescript
export function useNotifications(): {
  addNotification: AddNotificationFn
  removeNotification: RemoveNotificationFn
}
```

返回 `addNotification` 和 `removeNotification` 函数。

**行为说明**：
- `immediate` 优先级立即显示，清除当前 timeout
- `fold` 函数存在时，相同 key 的通知会合并
- `invalidates` 数组中的 key 会被移除
- 非 `immediate` 通知进入队列，按优先级排序

#### `getNext`

```typescript
export function getNext(queue: Notification[]): Notification | undefined
```

从队列中取出最高优先级（数值最小）的通知。

---

## QueuedMessageContext.tsx — 排队消息上下文

管理排队消息的布局状态，为后续消息提供缩进和内边距。

### 导出类型

#### `QueuedMessageContextValue`

```typescript
type QueuedMessageContextValue = {
  isQueued: boolean
  isFirst: boolean
  paddingWidth: number
}
```

Context 值。

| 字段 | 类型 | 说明 |
|------|------|------|
| `isQueued` | `boolean` | 始终为 `true` |
| `isFirst` | `boolean` | 是否是队列中第一条消息 |
| `paddingWidth` | `number` | 容器内边距缩减量（`paddingX * 2`） |

### 导出函数

#### `useQueuedMessage`

```typescript
export function useQueuedMessage(): QueuedMessageContextValue | undefined
```

获取队列消息 Context 值。可能在 Provider 外返回 `undefined`。

#### `QueuedMessageProvider`

```typescript
export function QueuedMessageProvider({
  isFirst,
  useBriefLayout,
  children
}: Props): React.ReactNode
```

Provider 组件。

| 参数 | 类型 | 说明 |
|------|------|------|
| `isFirst` | `boolean` | 是否为第一条消息 |
| `useBriefLayout` | `boolean \| undefined` | 为 `true` 时 padding 为 0（Brief Tool UI 已通过 `paddingLeft` 缩进） |
| `children` | `React.ReactNode` | 子元素 |

---

## mailbox.tsx — Mailbox 工具 Context

基于 `Mailbox` 工具的 Context Provider，用于进程间通信。

### 导出函数

#### `MailboxProvider`

```typescript
export function MailboxProvider({ children }: Props): React.ReactNode
```

提供单例 `Mailbox` 实例给子树。内部使用 `useMemo` 确保实例稳定。

#### `useMailbox`

```typescript
export function useMailbox(): Mailbox
```

获取 `Mailbox` 实例。必须在 `MailboxProvider` 内使用。

**异常**：
```
Error: useMailbox must be used within a MailboxProvider
```

---

## overlayContext.tsx — 浮层追踪

用于 Escape 键协调——当浮层（如带 `onCancel` 的 Select）打开时，防止取消请求处理器误触发。

### 常量

#### `NON_MODAL_OVERLAYS`

```typescript
const NON_MODAL_OVERLAYS = new Set(['autocomplete'])
```

非模态浮层集合，这些浮层不会禁用 TextInput 焦点。

### 导出函数

#### `useRegisterOverlay`

```typescript
export function useRegisterOverlay(id: string, enabled = true): void
```

注册活跃浮层。自动在挂载时注册、卸载时取消注册。

| 参数 | 类型 | 说明 |
|------|------|------|
| `id` | `string` | 浮层唯一标识（如 `'select'`、`'multi-select'`） |
| `enabled` | `boolean` | 是否注册（默认 `true`），可用于条件注册 |

**行为**：
- 挂载时将 id 加入 `activeOverlays` Set
- 卸载时移除
- 同时调用 `instances.get(process.stdout)?.invalidatePrevFrame()` 强制全量 diff

#### `useIsOverlayActive`

```typescript
export function useIsOverlayActive(): boolean
```

返回是否有任何浮层处于活跃状态（`activeOverlays.size > 0`）。响应式——浮层状态变化时组件重渲染。

#### `useIsModalOverlayActive`

```typescript
export function useIsModalOverlayActive(): boolean
```

返回是否有任何模态浮层（非 `autocomplete`）处于活跃状态。用于 TextInput 焦点控制。

**示例**：
```typescript
focus: !isSearchingHistory && !isModalOverlayActive
```

---

## fpsMetrics.tsx — 帧率指标

帧率指标的 Context 传递。

### 导出类型

#### `FpsMetricsGetter`

```typescript
type FpsMetricsGetter = () => FpsMetrics | undefined
```

返回 `FpsMetrics` 的函数类型。

### 导出函数

#### `FpsMetricsProvider`

```typescript
export function FpsMetricsProvider({
  getFpsMetrics,
  children
}: Props): React.ReactNode
```

提供 `getFpsMetrics` getter 函数。

| 参数 | 类型 | 说明 |
|------|------|------|
| `getFpsMetrics` | `FpsMetricsGetter` | 获取当前 FPS 指标的函数 |
| `children` | `React.ReactNode` | 子元素 |

#### `useFpsMetrics`

```typescript
export function useFpsMetrics(): FpsMetricsGetter | undefined
```

获取 FPS 指标 getter。可能在 Provider 外调用返回 `undefined`。

---

## promptOverlayContext.tsx — 提示词浮层 Portal

浮于提示词上方的内容 Portal，用于逃脱 `FullscreenLayout` 底部插槽的 `overflowY:hidden` 裁剪。`PromptInputFooter` 写入建议数据，`PromptInput` 写入对话框节点，`FullscreenLayout` 在裁剪区外渲染。

### 导出类型

#### `PromptOverlayData`

```typescript
export type PromptOverlayData = {
  suggestions: SuggestionItem[]
  selectedSuggestion: number
  maxColumnWidth?: number
}
```

提示词浮层数据。

| 字段 | 类型 | 说明 |
|------|------|------|
| `suggestions` | `SuggestionItem[]` | 建议项数组 |
| `selectedSuggestion` | `number` | 当前选中索引 |
| `maxColumnWidth` | `number \| undefined` | 最大列宽 |

#### `Setter<T>`

```typescript
type Setter<T> = (d: T | null) => void
```

Setter 函数类型。

### 导出函数

#### `PromptOverlayProvider`

```typescript
export function PromptOverlayProvider({ children }: Props): React.ReactNode
```

浮层 Context Provider。内部使用两对独立的 data/setter Context，使 setter context 保持稳定，避免写入方自渲染。

#### `usePromptOverlay`

```typescript
export function usePromptOverlay(): PromptOverlayData | null
```

读取当前浮层数据。

#### `usePromptOverlayDialog`

```typescript
export function usePromptOverlayDialog(): React.ReactNode
```

读取当前对话框节点。

#### `useSetPromptOverlay`

```typescript
export function useSetPromptOverlay(data: PromptOverlayData | null): void
```

注册建议数据。挂载时设置数据，卸载时清空。在 Provider 外为 no-op。

#### `useSetPromptOverlayDialog`

```typescript
export function useSetPromptOverlayDialog(node: React.ReactNode): void
```

注册对话框节点。挂载时设置节点，卸载时清空。在 Provider 外为 no-op。
