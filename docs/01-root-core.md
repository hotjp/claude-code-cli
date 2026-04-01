# 根目录核心文件

本节文档覆盖项目根目录下 12 个核心模块，它们构成了 Claude Code CLI 的基础架构层——包括工具抽象、命令注册、查询引擎、任务管理、费用追踪、历史记录与会话初始化。

---

## Tool.ts — 工具抽象层接口

`Tool.ts` 定义了整个工具系统的核心抽象，是所有内置工具和 MCP 工具统一遵循的接口契约。

### 导出类型

#### `ToolInputJSONSchema`

```typescript
type ToolInputJSONSchema = {
  [x: string]: unknown
  type: 'object'
  properties?: { [x: string]: unknown }
}
```

MCP 工具直接使用 JSON Schema 描述输入参数时的类型（不走 Zod 转换）。

#### `QueryChainTracking`

```typescript
type QueryChainTracking = {
  chainId: string   // 一次完整查询链的唯一标识
  depth: number      // 当前递归深度（每次 query() 嵌套 +1）
}
```

追踪 query 循环的链式调用关系，用于遥测分析。

#### `ValidationResult`

```typescript
type ValidationResult =
  | { result: true }
  | { result: false; message: string; errorCode: number }
```

工具输入验证结果：通过返回 `{ result: true }`，失败时附带错误消息与错误码。

#### `SetToolJSXFn`

```typescript
type SetToolJSXFn = (
  args: {
    jsx: React.ReactNode | null
    shouldHidePromptInput: boolean
    shouldContinueAnimation?: true
    showSpinner?: boolean
    isLocalJSXCommand?: boolean
    isImmediate?: boolean
    clearLocalJSX?: boolean
  } | null,
) => void
```

设置工具在 REPL 中的自定义 JSX 渲染内容。传 `null` 清除渲染。

| 字段 | 含义 |
|------|------|
| `jsx` | 要渲染的 React 节点 |
| `shouldHidePromptInput` | 是否隐藏用户输入框 |
| `shouldContinueAnimation` | 保持 spinner 动画 |
| `showSpinner` | 显示加载动画 |
| `isLocalJSXCommand` | 标记为本地 JSX 命令 |
| `isImmediate` | 立即渲染（不等下一帧） |
| `clearLocalJSX` | 清除本地 JSX 命令 |

#### `ToolPermissionContext`

```typescript
type ToolPermissionContext = DeepImmutable<{
  mode: PermissionMode
  additionalWorkingDirectories: Map<string, AdditionalWorkingDirectory>
  alwaysAllowRules: ToolPermissionRulesBySource
  alwaysDenyRules: ToolPermissionRulesBySource
  alwaysAskRules: ToolPermissionRulesBySource
  isBypassPermissionsModeAvailable: boolean
  isAutoModeAvailable?: boolean
  strippedDangerousRules?: ToolPermissionRulesBySource
  shouldAvoidPermissionPrompts?: boolean
  awaitAutomatedChecksBeforeDialog?: boolean
  prePlanMode?: PermissionMode
}>
```

工具权限上下文——包含了权限模式、白名单/黑名单规则、是否可跳过权限等核心配置。

| 字段 | 含义 |
|------|------|
| `mode` | 当前权限模式 (`default`/`plan`/`auto`/`bypassPermissions`) |
| `additionalWorkingDirectories` | 额外允许的工作目录映射 |
| `alwaysAllowRules` | 始终允许的工具规则（按来源分组） |
| `alwaysDenyRules` | 始终拒绝的工具规则 |
| `alwaysAskRules` | 始终需要询问的工具规则 |
| `isBypassPermissionsModeAvailable` | 是否可使用跳过权限模式 |
| `shouldAvoidPermissionPrompts` | 后台 agent 是否应自动拒绝权限弹窗 |
| `awaitAutomatedChecksBeforeDialog` | 在弹窗前等待自动化检查完成 |
| `prePlanMode` | 进入 plan 模式前的权限模式备份 |

#### `CompactProgressEvent`

```typescript
type CompactProgressEvent =
  | { type: 'hooks_start'; hookType: 'pre_compact' | 'post_compact' | 'session_start' }
  | { type: 'compact_start' }
  | { type: 'compact_end' }
```

上下文压缩（compact）进度事件类型。

#### `ToolUseContext`

```typescript
type ToolUseContext = {
  options: { ... }           // 工具运行时配置
  abortController: AbortController
  readFileState: FileStateCache
  getAppState(): AppState
  setAppState(f: (prev: AppState) => AppState): void
  setAppStateForTasks?: (f: (prev: AppState) => AppState) => void
  handleElicitation?: (serverName: string, params: ElicitRequestURLParams, signal: AbortSignal) => Promise<ElicitResult>
  setToolJSX?: SetToolJSXFn
  addNotification?: (notif: Notification) => void
  appendSystemMessage?: (msg: Exclude<SystemMessage, SystemLocalCommandMessage>) => void
  sendOSNotification?: (opts: { message: string; notificationType: string }) => void
  nestedMemoryAttachmentTriggers?: Set<string>
  loadedNestedMemoryPaths?: Set<string>
  dynamicSkillDirTriggers?: Set<string>
  discoveredSkillNames?: Set<string>
  userModified?: boolean
  setInProgressToolUseIDs: (f: (prev: Set<string>) => Set<string>) => void
  setHasInterruptibleToolInProgress?: (v: boolean) => void
  setResponseLength: (f: (prev: number) => number) => void
  pushApiMetricsEntry?: (ttftMs: number) => void
  setStreamMode?: (mode: SpinnerMode) => void
  onCompactProgress?: (event: CompactProgressEvent) => void
  setSDKStatus?: (status: SDKStatus) => void
  openMessageSelector?: () => void
  updateFileHistoryState: (updater: (prev: FileHistoryState) => FileHistoryState) => void
  updateAttributionState: (updater: (prev: AttributionState) => AttributionState) => void
  setConversationId?: (id: UUID) => void
  agentId?: AgentId
  agentType?: string
  requireCanUseTool?: boolean
  messages: Message[]
  fileReadingLimits?: { maxTokens?: number; maxSizeBytes?: number }
  globLimits?: { maxResults?: number }
  toolDecisions?: Map<string, { source: string; decision: 'accept' | 'reject'; timestamp: number }>
  queryTracking?: QueryChainTracking
  requestPrompt?: (sourceName: string, toolInputSummary?: string | null) => (request: PromptRequest) => Promise<PromptResponse>
  toolUseId?: string
  criticalSystemReminder_EXPERIMENTAL?: string
  preserveToolUseResults?: boolean
  localDenialTracking?: DenialTrackingState
  contentReplacementState?: ContentReplacementState
  renderedSystemPrompt?: SystemPrompt
}
```

工具使用的完整上下文对象——在每次工具调用时传入，提供对消息历史、应用状态、文件缓存、权限系统、UI 渲染等核心基础设施的访问。

| 关键字段 | 含义 |
|---------|------|
| `options` | 包含 `commands`、`tools`、`mcpClients`、`thinkingConfig` 等运行时配置 |
| `abortController` | 中断控制器，用于取消工具执行 |
| `readFileState` | 文件读取状态 LRU 缓存 |
| `messages` | 当前对话消息列表 |
| `agentId` | 当前子 agent ID（仅子 agent 有值） |
| `queryTracking` | 查询链追踪信息 |

#### `Progress`

```typescript
type Progress = ToolProgressData | HookProgress
```

工具进度事件的联合类型。

#### `ToolProgress<P>`

```typescript
type ToolProgress<P extends ToolProgressData> = {
  toolUseID: string
  data: P
}
```

单个工具调用的进度通知。

#### `ToolResult<T>`

```typescript
type ToolResult<T> = {
  data: T
  newMessages?: (UserMessage | AssistantMessage | AttachmentMessage | SystemMessage)[]
  contextModifier?: (context: ToolUseContext) => ToolUseContext
  mcpMeta?: { _meta?: Record<string, unknown>; structuredContent?: Record<string, unknown> }
}
```

工具执行结果。

| 字段 | 含义 |
|------|------|
| `data` | 工具返回的原始数据 |
| `newMessages` | 工具产生的额外消息（如系统提示） |
| `contextModifier` | 上下文修改器（仅非并发安全工具可用） |
| `mcpMeta` | MCP 协议元数据透传 |

#### `ToolCallProgress<P>`

```typescript
type ToolCallProgress<P extends ToolProgressData = ToolProgressData> = (
  progress: ToolProgress<P>,
) => void
```

工具执行进度回调函数类型。

#### `AnyObject`

```typescript
type AnyObject = z.ZodType<{ [key: string]: unknown }>
```

约束工具输入 schema 必须输出字符串键对象。

#### `Tool<Input, Output, P>`

```typescript
type Tool<
  Input extends AnyObject = AnyObject,
  Output = unknown,
  P extends ToolProgressData = ToolProgressData,
> = {
  aliases?: string[]
  searchHint?: string
  call(args, context, canUseTool, parentMessage, onProgress?): Promise<ToolResult<Output>>
  description(input, options): Promise<string>
  readonly inputSchema: Input
  readonly inputJSONSchema?: ToolInputJSONSchema
  outputSchema?: z.ZodType<unknown>
  inputsEquivalent?(a, b): boolean
  isConcurrencySafe(input): boolean
  isEnabled(): boolean
  isReadOnly(input): boolean
  isDestructive?(input): boolean
  interruptBehavior?(): 'cancel' | 'block'
  isSearchOrReadCommand?(input): { isSearch: boolean; isRead: boolean; isList?: boolean }
  isOpenWorld?(input): boolean
  requiresUserInteraction?(): boolean
  isMcp?: boolean
  isLsp?: boolean
  readonly shouldDefer?: boolean
  readonly alwaysLoad?: boolean
  mcpInfo?: { serverName: string; toolName: string }
  readonly name: string
  maxResultSizeChars: number
  readonly strict?: boolean
  backfillObservableInput?(input: Record<string, unknown>): void
  validateInput?(input, context): Promise<ValidationResult>
  checkPermissions(input, context): Promise<PermissionResult>
  getPath?(input): string
  preparePermissionMatcher?(input): Promise<(pattern: string) => boolean>
  prompt(options): Promise<string>
  userFacingName(input): string
  userFacingNameBackgroundColor?(input): keyof Theme | undefined
  isTransparentWrapper?(): boolean
  getToolUseSummary?(input): string | null
  getActivityDescription?(input): string | null
  toAutoClassifierInput(input): unknown
  mapToolResultToToolResultBlockParam(content, toolUseID): ToolResultBlockParam
  renderToolResultMessage?(content, progressMessages, options): React.ReactNode
  extractSearchText?(out: Output): string
  renderToolUseMessage(input, options): React.ReactNode
  isResultTruncated?(output: Output): boolean
  renderToolUseTag?(input): React.ReactNode
  renderToolUseProgressMessage?(progressMessages, options): React.ReactNode
  renderToolUseQueuedMessage?(): React.ReactNode
  renderToolUseRejectedMessage?(input, options): React.ReactNode
  renderToolUseErrorMessage?(result, options): React.ReactNode
  renderGroupedToolUse?(toolUses, options): React.ReactNode | null
}
```

**工具的完整接口定义**——所有内置工具和 MCP 工具都必须实现此接口。核心方法：

| 方法 | 说明 |
|------|------|
| `call()` | 执行工具逻辑并返回结果 |
| `description()` | 返回工具描述文本（可依据输入动态变化） |
| `checkPermissions()` | 权限检查（在 `validateInput` 之后调用） |
| `isEnabled()` | 工具是否可用 |
| `isConcurrencySafe()` | 是否支持并发调用 |
| `isReadOnly()` | 是否只读 |
| `isDestructive()` | 是否执行不可逆操作 |
| `prompt()` | 生成工具提示词给模型 |
| `renderToolUseMessage()` | 渲染工具调用消息 UI |
| `renderToolResultMessage()` | 渲染工具结果消息 UI |
| `toAutoClassifierInput()` | 生成 auto-mode 安全分类器的输入 |

#### `Tools`

```typescript
type Tools = readonly Tool[]
```

工具集合的类型别名，用于统一追踪工具集的组装和传递。

#### `ToolDef<Input, Output, P>`

```typescript
type ToolDef<Input, Output, P> = Omit<Tool<Input, Output, P>, DefaultableToolKeys> &
  Partial<Pick<Tool<Input, Output, P>, DefaultableToolKeys>>
```

`buildTool()` 接受的部分工具定义——默认方法可选。

### 导出函数

#### `getEmptyToolPermissionContext()`

```typescript
function getEmptyToolPermissionContext(): ToolPermissionContext
```

返回一个空的权限上下文（`mode: 'default'`，所有规则为空）。

#### `filterToolProgressMessages()`

```typescript
function filterToolProgressMessages(
  progressMessagesForMessage: ProgressMessage[],
): ProgressMessage<ToolProgressData>[]
```

从进度消息列表中过滤出仅包含工具进度（非 hook 进度）的消息。

#### `toolMatchesName()`

```typescript
function toolMatchesName(
  tool: { name: string; aliases?: string[] },
  name: string,
): boolean
```

检查工具是否匹配给定名称（包括主名称和别名）。

#### `findToolByName()`

```typescript
function findToolByName(tools: Tools, name: string): Tool | undefined
```

在工具列表中按名称或别名查找工具。

#### `buildTool<D>(def: D): BuiltTool<D>`

```typescript
function buildTool<D extends AnyToolDef>(def: D): BuiltTool<D>
```

**工厂函数**——从部分定义构建完整 `Tool` 对象。填充的默认值：

| 字段 | 默认值 |
|------|--------|
| `isEnabled` | `() => true` |
| `isConcurrencySafe` | `() => false` |
| `isReadOnly` | `() => false` |
| `isDestructive` | `() => false` |
| `checkPermissions` | 始终允许（交由通用权限系统处理） |
| `toAutoClassifierInput` | 返回 `''`（跳过分类器） |
| `userFacingName` | 返回工具的 `name` |

```typescript
const myTool = buildTool({
  name: 'MyTool',
  inputSchema: z.object({ query: z.string() }),
  async call(args, context) { /* ... */ },
  async description(input) { return 'My custom tool'; },
  prompt: async () => '',
  userFacingName: () => 'MyTool',
  mapToolResultToToolResultBlockParam: (content, id) => ({ type: 'tool_result', tool_use_id: id, content: String(content) }),
})
```

---

## tools.ts — 工具注册与组装

`tools.ts` 负责收集所有内置工具实例，并根据权限上下文、运行模式、Feature Flag 进行过滤和组装。

### 导出常量

#### `TOOL_PRESETS`

```typescript
const TOOL_PRESETS = ['default'] as const
```

预定义的工具集名称列表（当前仅有 `'default'`）。

#### `REMOTE_SAFE_COMMANDS` / `BRIDGE_SAFE_COMMANDS`（从 constants/tools.ts 重导出）

```typescript
export {
  ALL_AGENT_DISALLOWED_TOOLS,
  CUSTOM_AGENT_DISALLOWED_TOOLS,
  ASYNC_AGENT_ALLOWED_TOOLS,
  COORDINATOR_MODE_ALLOWED_TOOLS,
} from './constants/tools.js'
```

工具黑/白名单常量。

### 导出类型

#### `ToolPreset`

```typescript
type ToolPreset = (typeof TOOL_PRESETS)[number]
```

工具集名称的联合类型。

### 导出函数

#### `parseToolPreset()`

```typescript
function parseToolPreset(preset: string): ToolPreset | null
```

解析工具集名称字符串，不合法则返回 `null`。

#### `getToolsForDefaultPreset()`

```typescript
function getToolsForDefaultPreset(): string[]
```

获取默认工具集中所有已启用工具的名称列表。

#### `getAllBaseTools()`

```typescript
function getAllBaseTools(): Tools
```

返回当前环境中所有可用的内置工具列表。这是工具注册的**唯一真相来源**。

根据以下条件动态组装：
- `USER_TYPE === 'ant'`：包含 ConfigTool、TungstenTool、REPLTool 等
- Feature Flag：按条件包含 WorkflowTool、SleepTool、CronTools、MonitorTool 等
- `isToolSearchEnabledOptimistic()`：按需包含 ToolSearchTool
- `hasEmbeddedSearchTools()`：嵌入式搜索时移除 Glob/Grep 独立工具

核心工具列表包括：`AgentTool`, `BashTool`, `FileReadTool`, `FileEditTool`, `FileWriteTool`, `GlobTool`, `GrepTool`, `WebFetchTool`, `WebSearchTool`, `TodoWriteTool`, `AskUserQuestionTool`, `SkillTool` 等。

#### `filterToolsByDenyRules()`

```typescript
function filterToolsByDenyRules<T extends { name: string; mcpInfo?: { serverName: string; toolName: string } }>(
  tools: readonly T[],
  permissionContext: ToolPermissionContext,
): T[]
```

按权限上下文中的拒绝规则过滤工具列表。支持 MCP 服务器前缀匹配（如 `mcp__server` 前缀规则会移除该服务器的所有工具）。

#### `getTools()`

```typescript
function getTools(permissionContext: ToolPermissionContext): Tools
```

根据权限上下文获取过滤后的工具列表。

**核心逻辑：**
1. `CLAUDE_CODE_SIMPLE` 模式：仅返回 Bash/Read/Edit（或 REPL 包装）
2. 正常模式：从 `getAllBaseTools()` 出发
3. 过滤特殊工具（ListMcpResources、ReadMcpResource、SyntheticOutput）
4. 应用 deny 规则过滤
5. REPL 模式下隐藏被 REPL 包装的原始工具
6. 过滤 `isEnabled() === false` 的工具

#### `assembleToolPool()`

```typescript
function assembleToolPool(
  permissionContext: ToolPermissionContext,
  mcpTools: Tools,
): Tools
```

组装完整的工具池（内置 + MCP 工具）。

**逻辑：**
1. 获取内置工具
2. 过滤 MCP 工具的 deny 规则
3. 按名称排序（为 prompt cache 稳定性）
4. 去重（内置工具优先于同名 MCP 工具）

#### `getMergedTools()`

```typescript
function getMergedTools(
  permissionContext: ToolPermissionContext,
  mcpTools: Tools,
): Tools
```

简单合并内置工具和 MCP 工具（不去重、不排序）。用于 token 计数和工具搜索阈值计算等场景。

---

## commands.ts — 命令注册中心

`commands.ts` 是所有斜杠命令（`/help`, `/compact`, `/model` 等）的注册中心，负责加载、缓存、过滤命令。

### 导出类型

从 `./types/command.js` 重导出：

```typescript
export type {
  Command,
  CommandBase,
  CommandResultDisplay,
  LocalCommandResult,
  LocalJSXCommandContext,
  PromptCommand,
  ResumeEntrypoint,
} from './types/command.js'
export { getCommandName, isCommandEnabled } from './types/command.js'
```

### 导出常量

#### `INTERNAL_ONLY_COMMANDS`

```typescript
const INTERNAL_ONLY_COMMANDS: Command[]
```

仅在内部构建中可用的命令列表（backfill-sessions、break-cache、bughunter、commit 等）。

#### `REMOTE_SAFE_COMMANDS`

```typescript
const REMOTE_SAFE_COMMANDS: Set<Command>
```

在 `--remote` 模式下可安全使用的命令集合（session、exit、clear、help、theme、color 等）。

#### `BRIDGE_SAFE_COMMANDS`

```typescript
const BRIDGE_SAFE_COMMANDS: Set<Command>
```

可通过 Remote Control 桥接（移动/Web 客户端）执行的 `'local'` 类型命令白名单（compact、clear、cost、summary 等）。

### 导出函数

#### `getCommands()`

```typescript
async function getCommands(cwd: string): Promise<Command[]>
```

获取当前用户可用的所有命令。加载过程包含：
1. 从磁盘加载 skill 目录命令
2. 加载插件命令
3. 加载 workflow 命令
4. 加载内置命令
5. 过滤可用性要求（`meetsAvailabilityRequirement`）
6. 过滤已禁用命令（`isCommandEnabled`）
7. 插入动态 skill 命令

> 加载过程按 `cwd` 做了 `memoize`，但可用性和启用检查每次调用都会重新执行。

#### `builtInCommandNames()`

```typescript
function builtInCommandNames(): Set<string>
```

返回所有内置命令的名称集合（包含别名），memoized。

#### `meetsAvailabilityRequirement()`

```typescript
function meetsAvailabilityRequirement(cmd: Command): boolean
```

检查命令是否满足可用性要求（如认证/提供商限制）。无 `availability` 声明的命令默认通用。

#### `clearCommandMemoizationCaches()`

```typescript
function clearCommandMemoizationCaches(): void
```

仅清除命令的 memoization 缓存（不清除 skill 缓存）。

#### `clearCommandsCache()`

```typescript
function clearCommandsCache(): void
```

清除所有命令相关缓存（包括插件和 skill 缓存）。

#### `getMcpSkillCommands()`

```typescript
function getMcpSkillCommands(mcpCommands: readonly Command[]): readonly Command[]
```

从 MCP 命令中筛选出可作为 skill 由模型调用的 prompt 类型命令。

#### `getSkillToolCommands()`

```typescript
async function getSkillToolCommands(cwd: string): Promise<Command[]>
```

获取 SkillTool 可展示的所有 prompt 类型命令（包括 skills、bundled skills、legacy commands）。

#### `getSlashCommandToolSkills()`

```typescript
async function getSlashCommandToolSkills(cwd: string): Promise<Command[]>
```

获取 slash command 可调用的 skill 命令。

#### `isBridgeSafeCommand()`

```typescript
function isBridgeSafeCommand(cmd: Command): boolean
```

判断命令是否可在 Remote Control 桥接上安全执行。

#### `filterCommandsForRemoteMode()`

```typescript
function filterCommandsForRemoteMode(commands: Command[]): Command[]
```

过滤出仅 `--remote` 模式安全的命令。

#### `findCommand()`

```typescript
function findCommand(commandName: string, commands: Command[]): Command | undefined
```

按名称/别名查找命令。

#### `hasCommand()`

```typescript
function hasCommand(commandName: string, commands: Command[]): boolean
```

检查命令是否存在。

#### `getCommand()`

```typescript
function getCommand(commandName: string, commands: Command[]): Command
```

获取命令，不存在时抛出 `ReferenceError`（包含可用命令列表）。

#### `formatDescriptionWithSource()`

```typescript
function formatDescriptionWithSource(cmd: Command): string
```

格式化命令描述并附带来源标注（如 `(plugin)`、`(workflow)`、`(bundled)`）。

---

## context.ts — 系统上下文

`context.ts` 负责构建发送给模型的系统上下文和用户上下文，包括 git 状态、CLAUDE.md 文件内容、当前日期等。

### 导出函数

#### `getSystemPromptInjection()` / `setSystemPromptInjection()`

```typescript
function getSystemPromptInjection(): string | null
function setSystemPromptInjection(value: string | null): void
```

获取/设置系统提示注入内容（用于缓存破坏，仅内部构建）。

设置时自动清除 `getUserContext` 和 `getSystemContext` 的缓存。

#### `getGitStatus()`

```typescript
async function getGitStatus(): Promise<string | null>
```

获取当前 git 仓库的状态快照，memoized。

**返回内容包含：**
- 当前分支名
- 主分支名
- git 用户名
- `git status --short`（截断至 2000 字符）
- 最近 5 条 commit 记录

非 git 仓库返回 `null`。所有 git 命令使用 `--no-optional-locks` 防止锁定问题。

#### `getSystemContext()`

```typescript
async function getSystemContext(): Promise<{ [k: string]: string }>
```

获取系统级上下文，memoized。

**可能包含：**
- `gitStatus`：git 状态快照
- `cacheBreaker`：缓存破坏字符串（仅内部构建）

在 CCR（远程）模式或禁用 git 指令时跳过 git 状态。

#### `getUserContext()`

```typescript
async function getUserContext(): Promise<{ [k: string]: string }>
```

获取用户级上下文，memoized。

**返回内容：**
- `claudeMd`：从所有 CLAUDE.md 文件加载的指令内容
- `currentDate`：当前本地日期（如 `"Today's date is 2026-04-01."`）

`CLAUDE_CODE_DISABLE_CLAUDE_MDS` 或 `--bare` 模式（无额外目录）时跳过 CLAUDE.md 加载。

```typescript
// 使用示例
const ctx = await getUserContext()
// ctx = {
//   claudeMd: '## 项目规则\n...',
//   currentDate: "Today's date is 2026-04-01.",
// }
```

---

## QueryEngine.ts — 查询引擎

`QueryEngine.ts` 实现了 `QueryEngine` 类，封装了完整的查询生命周期管理——从用户输入处理到 API 调用、工具执行、消息持久化、SDK 事件输出。

### 导出类型

#### `QueryEngineConfig`

```typescript
type QueryEngineConfig = {
  cwd: string
  tools: Tools
  commands: Command[]
  mcpClients: MCPServerConnection[]
  agents: AgentDefinition[]
  canUseTool: CanUseToolFn
  getAppState: () => AppState
  setAppState: (f: (prev: AppState) => AppState) => void
  initialMessages?: Message[]
  readFileCache: FileStateCache
  customSystemPrompt?: string
  appendSystemPrompt?: string
  userSpecifiedModel?: string
  fallbackModel?: string
  thinkingConfig?: ThinkingConfig
  maxTurns?: number
  maxBudgetUsd?: number
  taskBudget?: { total: number }
  jsonSchema?: Record<string, unknown>
  verbose?: boolean
  replayUserMessages?: boolean
  handleElicitation?: ToolUseContext['handleElicitation']
  includePartialMessages?: boolean
  setSDKStatus?: (status: SDKStatus) => void
  abortController?: AbortController
  orphanedPermission?: OrphanedPermission
  snipReplay?: (yieldedSystemMsg: Message, store: Message[]) => { messages: Message[]; executed: boolean } | undefined
}
```

| 字段 | 含义 |
|------|------|
| `cwd` | 工作目录 |
| `tools` | 可用工具列表 |
| `commands` | 可用命令列表 |
| `mcpClients` | MCP 服务器连接 |
| `agents` | agent 定义列表 |
| `canUseTool` | 工具权限检查回调 |
| `initialMessages` | 初始消息（用于 resume） |
| `readFileCache` | 文件读取状态缓存 |
| `maxTurns` | 最大对话轮数 |
| `maxBudgetUsd` | 最大预算（美元） |
| `jsonSchema` | 结构化输出的 JSON Schema |
| `snipReplay` | Snip 压缩边界重放回调 |

### 导出类

#### `QueryEngine`

```typescript
class QueryEngine {
  constructor(config: QueryEngineConfig)
  async *submitMessage(prompt: string | ContentBlockParam[], options?: { uuid?: string; isMeta?: boolean }): AsyncGenerator<SDKMessage, void, unknown>
  interrupt(): void
  getMessages(): readonly Message[]
  getReadFileState(): FileStateCache
  getSessionId(): string
  setModel(model: string): void
}
```

**方法说明：**

| 方法 | 说明 |
|------|------|
| `constructor(config)` | 初始化引擎状态：消息列表、中断控制器、权限追踪、用量统计 |
| `submitMessage(prompt, options?)` | 提交一条消息并异步 yield SDK 事件流 |
| `interrupt()` | 中断当前正在进行的查询 |
| `getMessages()` | 获取当前消息列表（只读） |
| `getReadFileState()` | 获取文件读取状态缓存 |
| `getSessionId()` | 获取当前会话 ID |
| `setModel(model)` | 动态切换模型 |

**`submitMessage()` 核心流程：**

1. **预处理**：清空 skill 发现追踪，设置工作目录
2. **构建系统提示**：调用 `fetchSystemPromptParts()` 获取系统/用户/系统上下文
3. **处理用户输入**：调用 `processUserInput()` 解析斜杠命令和附件
4. **持久化**：将用户消息写入 transcript（`--bare` 模式 fire-and-forget）
5. **进入查询循环**：调用 `query()` 并处理返回的各类消息
6. **消息分类处理**：
   - `assistant`：推入消息列表、记录 transcript、yield 归一化消息
   - `progress`：同上
   - `user`：同上
   - `stream_event`：累积 usage 统计
   - `attachment`：处理 `max_turns_reached`、`structured_output`、`queued_command`
   - `system`：处理 `compact_boundary`（释放 GC）、`api_error`、`snip` 重放
7. **预算检查**：每条消息后检查 USD 预算
8. **结构化输出重试**：检查 SyntheticOutput 工具调用次数上限
9. **结果生成**：提取最后一条 assistant 消息的文本作为 `result`

### 导出函数

#### `ask()`

```typescript
async function* ask(params: {
  commands: Command[]
  prompt: string | Array<ContentBlockParam>
  promptUuid?: string
  isMeta?: boolean
  cwd: string
  tools: Tools
  verbose?: boolean
  mcpClients: MCPServerConnection[]
  thinkingConfig?: ThinkingConfig
  maxTurns?: number
  maxBudgetUsd?: number
  taskBudget?: { total: number }
  canUseTool: CanUseToolFn
  mutableMessages?: Message[]
  customSystemPrompt?: string
  appendSystemPrompt?: string
  userSpecifiedModel?: string
  fallbackModel?: string
  jsonSchema?: Record<string, unknown>
  getAppState: () => AppState
  setAppState: (f: (prev: AppState) => AppState) => void
  getReadFileCache: () => FileStateCache
  setReadFileCache: (cache: FileStateCache) => void
  abortController?: AbortController
  replayUserMessages?: boolean
  includePartialMessages?: boolean
  handleElicitation?: ToolUseContext['handleElicitation']
  agents?: AgentDefinition[]
  setSDKStatus?: (status: SDKStatus) => void
  orphanedPermission?: OrphanedPermission
}): AsyncGenerator<SDKMessage, void, unknown>
```

`QueryEngine` 的**一次性便捷包装**。创建引擎实例、提交消息、yield 结果，并在 `finally` 中保存文件缓存。

```typescript
// 使用示例
for await (const msg of ask({
  prompt: '解释这段代码',
  cwd: '/path/to/project',
  tools: getTools(permissionCtx),
  commands: await getCommands(cwd),
  mcpClients: [],
  canUseTool,
  getAppState,
  setAppState,
  getReadFileCache,
  setReadFileCache,
})) {
  if (msg.type === 'result') {
    console.log(msg.result)
  }
}
```

---

## query.ts — 底层查询循环

`query.ts` 实现了核心的查询循环（query loop），负责与 Claude API 交互、工具执行、上下文压缩、错误恢复等。

### 导出类型

#### `QueryParams`

```typescript
type QueryParams = {
  messages: Message[]
  systemPrompt: SystemPrompt
  userContext: { [k: string]: string }
  systemContext: { [k: string]: string }
  canUseTool: CanUseToolFn
  toolUseContext: ToolUseContext
  fallbackModel?: string
  querySource: QuerySource
  maxOutputTokensOverride?: number
  maxTurns?: number
  skipCacheWrite?: boolean
  taskBudget?: { total: number }
  deps?: QueryDeps
}
```

| 字段 | 含义 |
|------|------|
| `messages` | 对话消息列表 |
| `systemPrompt` | 系统提示词 |
| `userContext` | 用户上下文（CLAUDE.md 等） |
| `systemContext` | 系统上下文（git 状态等） |
| `querySource` | 查询来源标识（`'sdk'`/`'repl_main_thread'`/`'compact'` 等） |
| `maxTurns` | 最大对话轮数 |
| `taskBudget` | API 任务预算（token 级别） |
| `deps` | 可替换的依赖注入（用于测试） |

### 导出函数

#### `query()`

```typescript
async function* query(params: QueryParams): AsyncGenerator<
  StreamEvent | RequestStartEvent | Message | TombstoneMessage | ToolUseSummaryMessage,
  Terminal
>
```

**核心查询生成器**——实现了完整的 agent 循环。

**循环状态 (`State`)：**

```typescript
type State = {
  messages: Message[]
  toolUseContext: ToolUseContext
  autoCompactTracking: AutoCompactTrackingState | undefined
  maxOutputTokensRecoveryCount: number
  hasAttemptedReactiveCompact: boolean
  maxOutputTokensOverride: number | undefined
  pendingToolUseSummary: Promise<ToolUseSummaryMessage | null> | undefined
  stopHookActive: boolean | undefined
  turnCount: number
  transition: Continue | undefined
}
```

**单次迭代流程：**

1. **工具结果预算**：`applyToolResultBudget()` 限制聚合工具结果大小
2. **Snip 压缩**：`snipCompactIfNeeded()` 按需裁剪历史
3. **微压缩**（Microcompact）：缓存编辑式的上下文压缩
4. **上下文折叠**（Context Collapse）：项目级上下文折叠
5. **自动压缩**（Autocompact）：token 超限时压缩为摘要
6. **Token 阻断检查**：超限时直接返回错误
7. **API 调用**：`deps.callModel()` 流式获取模型响应
8. **工具执行**：`StreamingToolExecutor` 或 `runTools()` 执行工具调用
9. **附件处理**：内存文件预取、skill 发现预取、队列命令
10. **继续/终止判定**：max_turns、stop hooks、token budget

**错误恢复路径：**

| 场景 | 恢复策略 |
|------|---------|
| `prompt_too_long` (413) | 尝试 collapse drain → reactive compact → 返回错误 |
| `max_output_tokens` | 逐步提升输出 token 限制（8k → 64k） |
| 模型回退 | `FallbackTriggeredError` → 切换到 `fallbackModel` 重试 |
| 图片过大 | reactive compact 裁剪重试 |
| 流式中断 | 生成合成 `tool_result`、清理 MCP 锁 |

```typescript
// query() 使用示例（通常不直接调用，由 QueryEngine 包装）
for await (const event of query({
  messages,
  systemPrompt,
  userContext,
  systemContext,
  canUseTool,
  toolUseContext,
  querySource: 'sdk',
})) {
  if (event.type === 'assistant') {
    // 处理助手消息
  }
}
```

---

## main.tsx — 主入口

`main.tsx` 是 CLI 的主入口文件，负责命令行解析、环境初始化、REPL 启动。

### 顶层副作用

模块加载时立即执行：

1. **性能打点**：`profileCheckpoint('main_tsx_entry')`
2. **MDM 预读取**：`startMdmRawRead()` 启动 MDM 配置子进程
3. **Keychain 预读取**：`startKeychainPrefetch()` 并行读取 macOS 钥匙串

### 调试检测

```typescript
function isBeingDebugged(): boolean
```

检测进程是否被调试器附加（Node.js `--inspect`/`--debug`、`inspector.url()`）。外部构建中检测到调试器会直接退出。

### 辅助函数

#### `logManagedSettings()`

```typescript
function logManagedSettings(): void
```

记录托管设置键到 Statsig 遥测。

#### `logSessionTelemetry()`

```typescript
function logSessionTelemetry(): void
```

记录会话级别的 skill/plugin 遥测。

#### `logStartupTelemetry()`

```typescript
async function logStartupTelemetry(): Promise<void>
```

记录启动遥测：git 状态、worktree 数量、gh 认证状态、沙箱配置等。

#### `runMigrations()`

```typescript
function runMigrations(): void
```

运行所有同步迁移（版本号 `CURRENT_MIGRATION_VERSION = 11`）。包括模型重命名、设置迁移等。

#### `startDeferredPrefetches()`

```typescript
export function startDeferredPrefetches(): void
```

在 REPL 首次渲染后启动后台预取：用户信息、CLAUDE.md、tips、文件计数、feature flag、模型能力等。`--bare` 模式下完全跳过。

#### `prefetchSystemContextIfSafe()`

```typescript
function prefetchSystemContextIfSafe(): void
```

仅在安全环境下预取系统上下文（信任已确认或非交互模式）。

#### `loadSettingsFromFlag()`

```typescript
function loadSettingsFromFlag(settingsFile: string): void
```

解析 `--settings` 标志，支持 JSON 字符串或文件路径。使用内容哈希路径避免破坏 prompt cache。

#### `eagerLoadSettings()`

```typescript
function eagerLoadSettings(): void
```

在 `init()` 之前解析 `--settings` 和 `--setting-sources` 标志。

#### `initializeEntrypoint()`

```typescript
function initializeEntrypoint(isNonInteractive: boolean): void
```

根据运行模式设置 `CLAUDE_CODE_ENTRYPOINT` 环境变量（`cli`/`sdk-cli`/`mcp`/`claude-code-github-action`）。

### 核心函数

#### `main()`

```typescript
export async function main(): Promise<void>
```

CLI 主入口函数。执行流程：

1. **安全设置**：`NoDefaultCurrentDirectoryInExePath=1`（Windows 安全）
2. **警告处理器初始化**
3. **URL 处理**：`cc://`/`cc+unix://` 深度链接、`--handle-uri`、macOS URL Scheme
4. **SSH/Assistant 模式预处理**：从 argv 中提取并暂存
5. **交互模式判断**：`-p`/`--print`/`--init-only`/非 TTY
6. **客户端类型确定**：`cli`/`sdk-typescript`/`github-action`/`claude-desktop` 等
7. **设置预加载**：`eagerLoadSettings()`
8. **委托给 `run()`**

#### `getInputPrompt()`

```typescript
async function getInputPrompt(
  prompt: string,
  inputFormat: 'text' | 'stream-json',
): Promise<string | AsyncIterable<string>>
```

处理 stdin 输入。非 TTY 时从 stdin 读取数据（3s 超时），`stream-json` 模式返回 AsyncIterable。

#### `run()`

```typescript
async function run(): Promise<CommanderCommand>
```

配置 Commander.js 命令解析器。核心结构：

- **preAction hook**：MDM/keychain 等待、`init()`、日志初始化、迁移、远程设置加载
- **默认命令**：启动 REPL 或 headless 模式
- **子命令**：`mcp`、`plugin`、`doctor` 等

### 待处理类型

```typescript
type PendingConnect = {
  url: string | undefined
  authToken: string | undefined
  dangerouslySkipPermissions: boolean
}

type PendingAssistantChat = {
  sessionId?: string
  discover: boolean
}

type PendingSSH = {
  host: string | undefined
  cwd: string | undefined
  permissionMode: string | undefined
  dangerouslySkipPermissions: boolean
  local: boolean
  extraCliArgs: string[]
}
```

这些类型暂存从 argv 中提取的特殊模式参数，供后续 REPL 分支使用。

---

## Task.ts — 任务类型定义

`Task.ts` 定义了任务系统的基础类型和工具函数。

### 导出类型

#### `TaskType`

```typescript
type TaskType =
  | 'local_bash'       // 本地 shell 命令
  | 'local_agent'      // 本地子 agent
  | 'remote_agent'     // 远程 agent
  | 'in_process_teammate' // 进程内 teammate
  | 'local_workflow'   // 本地 workflow
  | 'monitor_mcp'      // MCP 监控
  | 'dream'            // Dream 任务
```

任务类型枚举。

#### `TaskStatus`

```typescript
type TaskStatus =
  | 'pending'    // 等待中
  | 'running'    // 运行中
  | 'completed'  // 已完成
  | 'failed'     // 已失败
  | 'killed'     // 已杀死
```

任务状态枚举。

#### `TaskHandle`

```typescript
type TaskHandle = {
  taskId: string
  cleanup?: () => void
}
```

任务句柄——包含任务 ID 和可选的清理函数。

#### `SetAppState`

```typescript
type SetAppState = (f: (prev: AppState) => AppState) => void
```

设置应用状态的函数类型。

#### `TaskContext`

```typescript
type TaskContext = {
  abortController: AbortController
  getAppState: () => AppState
  setAppState: SetAppState
}
```

任务执行上下文。

#### `TaskStateBase`

```typescript
type TaskStateBase = {
  id: string
  type: TaskType
  status: TaskStatus
  description: string
  toolUseId?: string
  startTime: number
  endTime?: number
  totalPausedMs?: number
  outputFile: string
  outputOffset: number
  notified: boolean
}
```

所有任务状态的共享基础字段。

| 字段 | 含义 |
|------|------|
| `id` | 任务 ID（带类型前缀，如 `b` + 8位随机字符） |
| `type` | 任务类型 |
| `status` | 当前状态 |
| `description` | 任务描述 |
| `toolUseId` | 关联的工具调用 ID |
| `startTime` | 开始时间戳 |
| `endTime` | 结束时间戳 |
| `outputFile` | 输出文件路径 |
| `outputOffset` | 输出偏移量 |
| `notified` | 是否已通知用户 |

#### `LocalShellSpawnInput`

```typescript
type LocalShellSpawnInput = {
  command: string
  description: string
  timeout?: number
  toolUseId?: string
  agentId?: AgentId
  kind?: 'bash' | 'monitor'
}
```

本地 shell 任务的输入参数。

#### `Task`

```typescript
type Task = {
  name: string
  type: TaskType
  kill(taskId: string, setAppState: SetAppState): Promise<void>
}
```

任务接口——所有任务类型必须实现 `kill()` 方法。

### 导出函数

#### `isTerminalTaskStatus()`

```typescript
function isTerminalTaskStatus(status: TaskStatus): boolean
```

判断任务状态是否为终态（`completed`/`failed`/`killed`）。

#### `generateTaskId()`

```typescript
function generateTaskId(type: TaskType): string
```

生成带类型前缀的任务 ID。格式：`{前缀}{8位随机字符}`。

| 类型 | 前缀 |
|------|------|
| `local_bash` | `b` |
| `local_agent` | `a` |
| `remote_agent` | `r` |
| `in_process_teammate` | `t` |
| `local_workflow` | `w` |
| `monitor_mcp` | `m` |
| `dream` | `d` |

#### `createTaskStateBase()`

```typescript
function createTaskStateBase(
  id: string,
  type: TaskType,
  description: string,
  toolUseId?: string,
): TaskStateBase
```

创建任务状态基础对象。默认 `status: 'pending'`，`startTime: Date.now()`。

---

## tasks.ts — 任务管理

`tasks.ts` 提供任务注册表的访问入口，模式与 `tools.ts` 对称。

### 导出函数

#### `getAllTasks()`

```typescript
function getAllTasks(): Task[]
```

返回所有可用任务类型的列表。

**当前包含：**
- `LocalShellTask` — 本地 shell 命令任务
- `LocalAgentTask` — 本地子 agent 任务
- `RemoteAgentTask` — 远程 agent 任务
- `DreamTask` — Dream 任务
- `LocalWorkflowTask`（Feature Flag `WORKFLOW_SCRIPTS`）
- `MonitorMcpTask`（Feature Flag `MONITOR_TOOL`）

#### `getTaskByType()`

```typescript
function getTaskByType(type: TaskType): Task | undefined
```

按类型查找任务。内部调用 `getAllTasks().find()`。

```typescript
const shellTask = getTaskByType('local_bash')
await shellTask?.kill(taskId, setAppState)
```

---

## cost-tracker.ts — 费用跟踪

`cost-tracker.ts` 管理会话级别的费用统计、token 使用量、模型用量等。

### 导出重导出

从 `bootstrap/state.js` 重导出：

```typescript
export {
  getTotalCost,           // 总费用（美元）
  getTotalDuration,       // 总持续时间
  getTotalAPIDuration,    // API 调用总时间
  getTotalAPIDurationWithoutRetries, // 不含重试的 API 时间
  addToTotalLinesChanged, // 增加代码行变更
  getTotalLinesAdded,     // 总增加行数
  getTotalLinesRemoved,   // 总删除行数
  getTotalInputTokens,    // 总输入 token
  getTotalOutputTokens,   // 总输出 token
  getTotalCacheReadInputTokens,    // 总缓存读取 token
  getTotalCacheCreationInputTokens, // 总缓存创建 token
  getTotalWebSearchRequests,        // 总 Web 搜索请求
  formatCost,
  hasUnknownModelCost,
  resetStateForTests,
  resetCostState,
  setHasUnknownModelCost,
  getModelUsage,           // 按模型的用量映射
  getUsageForModel,        // 获取指定模型用量
} from './bootstrap/state.js'
```

### 内部类型

#### `StoredCostState`

```typescript
type StoredCostState = {
  totalCostUSD: number
  totalAPIDuration: number
  totalAPIDurationWithoutRetries: number
  totalToolDuration: number
  totalLinesAdded: number
  totalLinesRemoved: number
  lastDuration: number | undefined
  modelUsage: { [modelName: string]: ModelUsage } | undefined
}
```

持久化到项目配置的费用状态。

### 导出函数

#### `getStoredSessionCosts()`

```typescript
function getStoredSessionCosts(sessionId: string): StoredCostState | undefined
```

从项目配置读取指定会话的费用数据。仅当 `lastSessionId` 匹配时返回。

#### `restoreCostStateForSession()`

```typescript
function restoreCostStateForSession(sessionId: string): boolean
```

从项目配置恢复指定会话的费用状态。成功返回 `true`。

#### `saveCurrentSessionCosts()`

```typescript
function saveCurrentSessionCosts(fpsMetrics?: FpsMetrics): void
```

将当前会话的所有费用数据保存到项目配置。包含：
- 总费用、API 时间、工具时间、持续时间
- 输入/输出/缓存 token
- Web 搜索请求数
- 代码行变更数
- FPS 指标
- 按模型的用量明细

#### `formatTotalCost()`

```typescript
function formatTotalCost(): string
```

格式化总费用报告字符串。包含：

```
Total cost:            $0.1234
Total duration (API):  1m 23s
Total duration (wall): 2m 45s
Total code changes:    15 lines added, 3 lines removed
Usage by model:
           sonnet-4:  1,234 input, 567 output, 890 cache read, 0 cache write ($0.05)
```

#### `addToTotalSessionCost()`

```typescript
function addToTotalSessionCost(cost: number, usage: Usage, model: string): number
```

将单次 API 调用的费用和用量累加到会话总计。

**逻辑：**
1. 更新模型级别用量（input/output/cache/webSearch token + 费用）
2. 更新全局费用状态
3. 更新 Statsig 计数器（费用/各类 token）
4. 递归处理 advisor 用量（advisor 模型的 token 和费用）

返回本次调用及其 advisor 的总费用。

---

## history.ts — 历史记录

`history.ts` 管理用户提示历史的持久化和读取，支持 Up-arrow 回溯和 Ctrl+R 搜索。

### 导出类型

#### `TimestampedHistoryEntry`

```typescript
type TimestampedHistoryEntry = {
  display: string          // 显示文本
  timestamp: number        // 时间戳
  resolve: () => Promise<HistoryEntry>  // 懒加载完整内容（含粘贴内容）
}
```

带时间戳的历史条目（用于 Ctrl+R 搜索，粘贴内容延迟加载）。

### 内部类型

#### `StoredPastedContent`

```typescript
type StoredPastedContent = {
  id: number
  type: 'text' | 'image'
  content?: string         // 内联内容（≤1024 字符）
  contentHash?: string     // 大内容的哈希引用（存储在 pasteStore）
  mediaType?: string
  filename?: string
}
```

持久化的粘贴内容——短内容内联存储，长内容通过 hash 引用外部存储。

#### `LogEntry`

```typescript
type LogEntry = {
  display: string
  pastedContents: Record<number, StoredPastedContent>
  timestamp: number
  project: string
  sessionId?: string
}
```

历史日志条目的磁盘存储格式。

### 导出函数

#### `getPastedTextRefNumLines()`

```typescript
function getPastedTextRefNumLines(text: string): number
```

计算粘贴文本的行数（换行符数量）。

#### `formatPastedTextRef()`

```typescript
function formatPastedTextRef(id: number, numLines: number): string
```

格式化粘贴文本引用标记，如 `[Pasted text #1 +10 lines]`。

#### `formatImageRef()`

```typescript
function formatImageRef(id: number): string
```

格式化图片引用标记，如 `[Image #1]`。

#### `parseReferences()`

```typescript
function parseReferences(input: string): Array<{ id: number; match: string; index: number }>
```

解析输入中的所有粘贴引用标记（Pasted text/Image/Truncated text）。

#### `expandPastedTextRefs()`

```typescript
function expandPastedTextRefs(input: string, pastedContents: Record<number, PastedContent>): string
```

将输入中的 `[Pasted text #N]` 占位符替换为实际粘贴内容。图片引用保留不变（作为 content block 处理）。

#### `makeHistoryReader()`

```typescript
async function* makeHistoryReader(): AsyncGenerator<HistoryEntry>
```

异步生成器——从全局历史文件倒序读取所有历史条目。

#### `getTimestampedHistory()`

```typescript
async function* getTimestampedHistory(): AsyncGenerator<TimestampedHistoryEntry>
```

获取当前项目的去重历史条目（按显示文本去重，最多 100 条），用于 Ctrl+R 搜索。

#### `getHistory()`

```typescript
async function* getHistory(): AsyncGenerator<HistoryEntry>
```

获取当前项目的历史条目。**当前会话条目优先**于其他会话，避免并发会话的 up-arrow 历史交错。

#### `addToHistory()`

```typescript
function addToHistory(command: HistoryEntry | string): void
```

添加一条历史记录。

**存储逻辑：**
- 小文本（≤1024字符）内联存储
- 大文本计算哈希后异步写入 pasteStore（fire-and-forget）
- 图片跳过（存储在 image-cache）
- 写入过程带文件锁（retry 3 次，10s 过期）
- 最多保留 100 条记录
- `CLAUDE_CODE_SKIP_PROMPT_HISTORY` 环境变量可跳过

#### `clearPendingHistoryEntries()`

```typescript
function clearPendingHistoryEntries(): void
```

清除所有待写入的历史条目。

#### `removeLastFromHistory()`

```typescript
function removeLastFromHistory(): void
```

撤销最近一次 `addToHistory` 调用。用于 Esc 恢复对话时同步清除对应的历史条目。

---

## setup.ts — 设置流程

`setup.ts` 实现了会话初始化的设置流程，在 REPL 渲染前执行。

### 导出函数

#### `setup()`

```typescript
async function setup(
  cwd: string,
  permissionMode: PermissionMode,
  allowDangerouslySkipPermissions: boolean,
  worktreeEnabled: boolean,
  worktreeName: string | undefined,
  tmuxEnabled: boolean,
  customSessionId?: string | null,
  worktreePRNumber?: number,
  messagingSocketPath?: string,
): Promise<void>
```

会话初始化主函数。

**参数说明：**

| 参数 | 含义 |
|------|------|
| `cwd` | 工作目录 |
| `permissionMode` | 权限模式 |
| `allowDangerouslySkipPermissions` | 是否允许跳过权限 |
| `worktreeEnabled` | 是否启用 worktree 模式 |
| `worktreeName` | worktree 名称 |
| `tmuxEnabled` | 是否创建 tmux 会话 |
| `customSessionId` | 自定义会话 ID |
| `worktreePRNumber` | 关联的 PR 编号 |
| `messagingSocketPath` | UDS 消息 socket 路径 |

**初始化流程：**

1. **Node.js 版本检查**：要求 ≥ 18
2. **会话 ID 设置**：如有自定义 session ID 则切换
3. **UDS 消息服务启动**：Mac/Linux 下启动 Unix Domain Socket 消息服务器
4. **Teammate 快照**：Agent Swarms 模式下捕获 teammate 状态快照
5. **终端备份恢复**：检测并恢复 iTerm2/Terminal.app 的中断设置
6. **工作目录设置**：`setCwd(cwd)`
7. **Hooks 配置快照**：`captureHooksConfigSnapshot()` 防止隐藏 hook 修改
8. **FileChanged 监听器初始化**
9. **Worktree 创建**（如启用）：
   - Git 仓库检查
   - 创建 worktree 分支和目录
   - 可选创建 tmux 会话
   - 更新工作目录和项目根
10. **后台任务启动**：
    - Session memory 初始化
    - Context collapse 初始化
    - 版本锁定
11. **预取**：
    - 插件命令和 hooks
    - Attribution hooks（内部构建）
    - Session file access hooks
    - Team memory watcher
    - API key 预取
12. **权限安全检查**：
    - `bypassPermissions` 模式禁止 root/sudo
    - 内部构建要求 Docker/sandbox 环境
13. **上一会话退出遥测**：记录上一次会话的费用和持续时间
14. **Release notes 检查**：获取最近活动（非 bare 模式）

```typescript
await setup(
  '/path/to/project',
  'default',
  false,
  false,
  undefined,
  false,
)
// setup 完成后 REPL 可以安全渲染
```
