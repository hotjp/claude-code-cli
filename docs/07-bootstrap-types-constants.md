# 启动引导、类型定义、常量与查询层 API 文档

> 本文档涵盖 `bootstrap/`、`types/`、`constants/`、`schemas/`、`query/` 五个目录的详细 API 说明。`entrypoints/` 的内容请参见 [16 - Entrypoints 模块](16-entrypoints.md)。

---

# 一、bootstrap/ — 应用启动引导层（全局状态）

此目录仅包含一个文件 `state.ts`，是整个应用的**全局单例状态管理**模块。所有导出均为 getter/setter 函数，直接操作同一个内部 `STATE` 对象。

## state.ts

### 导出类型

#### `ChannelEntry`

通道入口联合类型，用于 `--channels` 标志解析。

| 变体 | 字段 | 说明 |
|------|------|------|
| `{ kind: 'plugin' }` | `name: string` — 插件名称；`marketplace: string` — 市场；`dev?: boolean` — 是否来自 dev 频道 | 插件通道 |
| `{ kind: 'server' }` | `name: string` — 服务器名称；`dev?: boolean` — 是否来自 dev 频道 | 服务器通道 |

#### `AttributedCounter`

带属性标签的计数器接口。

- `add(value: number, additionalAttributes?: Attributes): void` — 累加计数，合并遥测属性

#### `SessionCronTask`

会话级定时任务类型（不持久化到磁盘）。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `string` | 任务 ID |
| `cron` | `string` | Cron 表达式 |
| `prompt` | `string` | 触发时执行的提示 |
| `createdAt` | `number` | 创建时间戳 |
| `recurring?` | `boolean` | 是否重复执行 |
| `agentId?` | `string` | 创建此任务的队友 ID |

#### `InvokedSkillInfo`

已调用技能的跟踪信息，存储于 `Map<string, InvokedSkillInfo>`（key 为技能路径）。

| 字段 | 类型 | 说明 |
|------|------|------|
| `skillName` | `string` | 技能名称 |
| `skillPath` | `string` | 技能路径 |
| `content` | `string` | 技能内容 |
| `invokedAt` | `number` | 调用时间戳 |
| `agentId` | `string \| null` | 调用此技能的 Agent ID |

### 内部 `State` 类型关键字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `originalCwd` | `string` | 原始工作目录 |
| `cwd` | `string` | 当前工作目录 |
| `projectRoot` | `string` | 稳定的项目根目录（不受 mid-session worktree 影响） |
| `totalCostUSD` | `number` | 累计 API 调用费用（美元） |
| `totalAPIDuration` | `number` | 累计 API 调用时长（ms） |
| `totalAPIDurationWithoutRetries` | `number` | 累计 API 调用时长（不含重试，ms） |
| `totalToolDuration` | `number` | 累计工具执行时长（ms） |
| `turnHookDurationMs` | `number` | 当前轮次 Hook 耗时 |
| `turnToolDurationMs` | `number` | 当前轮次工具耗时 |
| `turnClassifierDurationMs` | `number` | 当前轮次分类器耗时 |
| `turnToolCount` | `number` | 当前轮次工具调用次数 |
| `turnHookCount` | `number` | 当前轮次 Hook 调用次数 |
| `turnClassifierCount` | `number` | 当前轮次分类器调用次数 |
| `startTime` | `number` | 会话开始时间戳 |
| `lastInteractionTime` | `number` | 最后一次用户交互时间 |
| `totalLinesAdded` | `number` | 累计添加行数 |
| `totalLinesRemoved` | `number` | 累计删除行数 |
| `modelUsage` | `{ [modelName: string]: ModelUsage }` | 按模型统计用量 |
| `mainLoopModelOverride` | `ModelSetting \| undefined` | --model 标志覆盖 |
| `initialMainLoopModel` | `ModelSetting \| undefined` | 初始模型（不受后续覆盖影响） |
| `isInteractive` | `boolean` | 是否交互模式 |
| `clientType` | `string` | 客户端类型（如 `'cli'`） |
| `sessionSource` | `string \| undefined` | 会话来源 |
| `sessionId` | `SessionId` | 当前会话 ID |
| `parentSessionId` | `SessionId \| undefined` | 父会话 ID（用于会话继承链） |
| `meter` | `Meter \| null` | OpenTelemetry Meter |
| `meterProvider` | `MeterProvider \| null` | Meter Provider |
| `tracerProvider` | `BasicTracerProvider \| null` | Tracer Provider |
| `loggerProvider` | `LoggerProvider \| null` | Logger Provider |
| `agentColorMap` | `Map<string, AgentColorName>` | Agent 颜色映射 |
| `agentColorIndex` | `number` | Agent 颜色分配计数器 |
| `inlinePlugins` | `string[]` | `--plugin-dir` 指定的会话级插件 |
| `chromeFlagOverride` | `boolean \| undefined` | 显式 `--chrome`/`--no-chrome` 标志值 |
| `useCoworkPlugins` | `boolean` | 使用 cowork_plugins 而非 plugins |
| `sessionPersistenceDisabled` | `boolean` | 禁用会话持久化到磁盘 |
| `hasExitedPlanMode` | `boolean` | 用户是否已退出计划模式 |
| `lspRecommendationShownThisSession` | `boolean` | 本会话是否已显示 LSP 推荐 |
| `initJsonSchema` | `Record<string, unknown> \| null` | SDK 初始化 JSON Schema（结构化输出） |
| `planSlugCache` | `Map<string, string>` | 计划 Slug 缓存（sessionId -> wordSlug） |
| `lastAPIRequest` | `Omit<BetaMessageStreamParams, 'messages'> \| null` | 最近一次 API 请求（用于错误报告） |
| `lastAPIRequestMessages` | `BetaMessageStreamParams['messages'] \| null` | 最近 API 请求的消息数组 |
| `lastClassifierRequests` | `unknown[] \| null` | 最近自动模式分类器请求（用于 /share） |
| `cachedClaudeMdContent` | `string \| null` | CLAUDE.md 内容缓存（打破分类器循环） |
| `inMemoryErrorLog` | `Array<{ error, timestamp }>` | 最近错误的内存日志（最多 100 条） |
| `allowedSettingSources` | `SettingSource[]` | 允许的设置来源 |
| `sessionIngressToken` | `string \| null \| undefined` | 会话入口 Token |
| `oauthTokenFromFd` | `string \| null \| undefined` | OAuth Token（来自文件描述符） |
| `apiKeyFromFd` | `string \| null \| undefined` | API Key（来自文件描述符） |
| `statsStore` | `{ observe(name, value) } \| null` | 统计信息观测存储 |
| `lastMainRequestId` | `string \| undefined` | 主对话链最近一次请求 ID |
| `lastApiCompletionTimestamp` | `number \| null` | 最近一次 API 调用完成时间戳 |
| `sdkBetas` | `string[] \| undefined` | SDK 提供的 Beta 特性列表 |
| `mainThreadAgentType` | `string \| undefined` | 主线程 Agent 类型（来自 `--agent` 标志） |
| `systemPromptSectionCache` | `Map<string, string \| null>` | 系统提示段落缓存 |
| `lastEmittedDate` | `string \| null` | 最近一次发送给模型的日期（检测午夜变更） |
| `additionalDirectoriesForClaudeMd` | `string[]` | `--add-dir` 标志指定的额外目录 |
| `allowedChannels` | `ChannelEntry[]` | `--channels` 标志解析的通道白名单 |
| `hasDevChannels` | `boolean` | 是否有来自 dev 频道的通道 |
| `sessionProjectDir` | `string \| null` | 会话 `.jsonl` 所在目录 |
| `promptCache1hEligible` | `boolean \| null` | 1 小时 Prompt Cache 用户资格（会话稳定） |
| `registeredHooks` | `Partial<Record<HookEvent, RegisteredHookMatcher[]>> \| null` | SDK 注册的 Hook |
| `invokedSkills` | `Map<string, InvokedSkillInfo>` | 已调用技能缓存（跨压缩保留） |
| `slowOperations` | `Array<{ operation, durationMs, timestamp }>` | 慢操作追踪（开发模式） |
| `isRemoteMode` | `boolean` | 是否远程模式 |
| `scheduledTasksEnabled` | `boolean` | 定时任务是否启用 |
| `sessionBypassPermissionsMode` | `boolean` | 会话级绕过权限模式 |
| `promptCache1hAllowlist` | `string[] \| null` | 1 小时 Prompt Cache 白名单 |
| `afkModeHeaderLatched` | `boolean \| null` | AFK 模式 Beta 头粘滞锁 |
| `fastModeHeaderLatched` | `boolean \| null` | 快速模式 Beta 头粘滞锁 |
| `cacheEditingHeaderLatched` | `boolean \| null` | 缓存编辑 Beta 头粘滞锁 |
| `thinkingClearLatched` | `boolean \| null` | 思考清除粘滞锁 |
| `pendingPostCompaction` | `boolean` | 压缩后待标记 |
| `promptId` | `string \| null` | 当前提示 ID（UUID） |
| `hasUnknownModelCost` | `boolean` | 是否有未知模型费用 |
| `kairosActive` | `boolean` | Kairos 模式是否激活 |
| `strictToolResultPairing` | `boolean` | 严格工具结果配对 |
| `sdkAgentProgressSummariesEnabled` | `boolean` | SDK Agent 进度摘要是否启用 |
| `userMsgOptIn` | `boolean` | 用户消息选择启用 |
| `questionPreviewFormat` | `string \| null` | 问题预览格式 |
| `flagSettingsPath` | `string \| null` | 标志设置文件路径 |
| `flagSettingsInline` | `string \| null` | 标志设置内联内容 |
| `sessionCronTasks` | `SessionCronTask[]` | 会话级定时任务 |
| `sessionCreatedTeams` | `Set<string>` | 会话创建的团队 |
| `sessionTrustAccepted` | `boolean` | 会话信任是否接受 |
| `needsPlanModeExitAttachment` | `boolean` | 是否需要计划模式退出附件 |
| `needsAutoModeExitAttachment` | `boolean` | 是否需要自动模式退出附件 |
| `sessionCounter` | `AttributedCounter \| null` | 会话计数器 |
| `locCounter` | `AttributedCounter \| null` | 代码行数计数器 |
| `prCounter` | `AttributedCounter \| null` | PR 计数器 |
| `commitCounter` | `AttributedCounter \| null` | 提交计数器 |
| `costCounter` | `AttributedCounter \| null` | 费用计数器 |
| `tokenCounter` | `AttributedCounter \| null` | Token 计数器 |
| `codeEditToolDecisionCounter` | `AttributedCounter \| null` | 代码编辑工具决策计数器 |
| `activeTimeCounter` | `AttributedCounter \| null` | 活跃时间计数器 |
| `teleportedSessionInfo` | `TeleportedSessionInfo \| null` | 远程会话信息 |
| `directConnectServerUrl` | `string \| null` | 直连服务器 URL |

### 主要导出函数

#### 会话管理

| 函数 | 签名 | 说明 |
|------|------|------|
| `getSessionId()` | `() => SessionId` | 获取当前会话 ID |
| `regenerateSessionId(options?)` | `(options?: { setCurrentAsParent?: boolean }) => SessionId` | 重新生成会话 ID |
| `switchSession(sessionId, projectDir?)` | `(SessionId, string \| null) => void` | 原子切换活动会话 |
| `onSessionSwitch` | `Signal` | 会话切换事件订阅 |
| `getParentSessionId()` | `() => SessionId \| undefined` | 获取父会话 ID |
| `getSessionProjectDir()` | `() => string \| null` | 获取当前会话的项目目录 |

#### 工作目录

| 函数 | 说明 |
|------|------|
| `getOriginalCwd()` / `setOriginalCwd(cwd)` | 获取/设置原始工作目录 |
| `getProjectRoot()` / `setProjectRoot(cwd)` | 获取/设置稳定项目根（仅 `--worktree` 启动时设置） |
| `getCwdState()` / `setCwdState(cwd)` | 获取/设置当前工作目录 |

#### 费用与用量

| 函数 | 说明 |
|------|------|
| `addToTotalDurationState(dur, durWithoutRetries)` | 累加 API 调用时长 |
| `addToTotalCostState(cost, modelUsage, model)` | 累加费用和模型用量 |
| `getTotalCostUSD()` | 获取总费用（美元） |
| `getTotalAPIDuration()` / `getTotalDuration()` | 获取 API 时长 / 总时长 |
| `getTotalInputTokens()` / `getTotalOutputTokens()` | 获取总输入/输出 Token 数 |
| `getTotalCacheReadInputTokens()` / `getTotalCacheCreationInputTokens()` | 获取缓存读写 Token 数 |
| `getTotalWebSearchRequests()` | 获取 Web 搜索请求总数 |
| `resetCostState()` | 重置所有费用和用量统计 |

#### 工具与 Hook 计时

| 函数 | 说明 |
|------|------|
| `addToToolDuration(duration)` | 累加工具执行耗时 |
| `getTurnHookDurationMs()` / `addToTurnHookDuration(dur)` / `resetTurnHookDuration()` | 轮次 Hook 耗时管理 |
| `getTurnToolDurationMs()` / `resetTurnToolDuration()` | 轮次工具耗时管理 |
| `getTurnClassifierDurationMs()` / `resetTurnClassifierDuration()` | 轮次分类器耗时管理 |

#### 模型

| 函数 | 说明 |
|------|------|
| `getMainLoopModelOverride()` / `setMainLoopModelOverride(model)` | 获取/设置模型覆盖 |
| `getInitialMainLoopModel()` / `setInitialMainLoopModel(model)` | 获取/设置初始模型 |
| `getModelStrings()` / `setModelStrings(modelStrings)` | 获取/设置模型字符串信息 |

#### 遥测 (OpenTelemetry)

| 函数 | 说明 |
|------|------|
| `setMeter(meter, createCounter)` | 初始化 Meter 及所有计数器 |
| `getSessionCounter()` / `getLocCounter()` / `getPrCounter()` / `getCommitCounter()` | 获取各类计数器 |
| `getCostCounter()` / `getTokenCounter()` / `getCodeEditToolDecisionCounter()` / `getActiveTimeCounter()` | 获取更多计数器 |
| `setLoggerProvider(p)` / `getLoggerProvider()` | Logger Provider |
| `setEventLogger(l)` / `getEventLogger()` | 事件日志器 |
| `setMeterProvider(p)` / `getMeterProvider()` | Meter Provider |
| `setTracerProvider(p)` / `getTracerProvider()` | Tracer Provider |

#### 滚动与交互

| 函数 | 说明 |
|------|------|
| `markScrollActivity()` | 标记滚动事件（150ms 内抑制后台工作） |
| `getIsScrollDraining()` | 是否正在滚动排空 |
| `waitForScrollIdle()` | 等待滚动空闲 |
| `updateLastInteractionTime(immediate?)` | 更新最后交互时间 |
| `flushInteractionTime()` | 刷新延迟的交互时间 |
| `getLastInteractionTime()` | 获取最后交互时间 |

#### Hook 管理

| 函数 | 说明 |
|------|------|
| `registerHookCallbacks(hooks)` | 注册 SDK Hook 回调 |
| `getRegisteredHooks()` | 获取已注册的 Hook |
| `clearRegisteredHooks()` | 清除所有 Hook |
| `clearRegisteredPluginHooks()` | 仅清除插件 Hook |

#### 技能

| 函数 | 说明 |
|------|------|
| `addInvokedSkill(name, path, content, agentId?)` | 添加已调用技能 |
| `getInvokedSkills()` | 获取所有已调用技能 |
| `getInvokedSkillsForAgent(agentId?)` | 获取指定 Agent 的已调用技能 |
| `clearInvokedSkills(preservedAgentIds?)` | 清除技能缓存 |
| `clearInvokedSkillsForAgent(agentId)` | 清除指定 Agent 的技能缓存 |

#### 测试

| 函数 | 说明 |
|------|------|
| `resetStateForTests()` | 重置全部状态（仅测试环境） |
| `resetTotalDurationStateAndCost_FOR_TESTS_ONLY()` | 仅重置时长和费用 |
| `resetModelStringsForTestingOnly()` | 重置模型字符串 |

---

> entrypoints/ 的详细内容请参见 [16 - Entrypoints 模块](16-entrypoints.md)。

---

# 二、types/ — 全局类型定义

## command.ts — 命令类型

### 类型

#### `LocalCommandResult`

命令执行结果联合类型：
- `{ type: 'text', value: string }` — 文本结果
- `{ type: 'compact', compactionResult, displayText? }` — 压缩结果
- `{ type: 'skip' }` — 跳过

#### `PromptCommand`

提示型命令（skill）配置：

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `'prompt'` | 类型标识 |
| `progressMessage` | `string` | 进度消息 |
| `contentLength` | `number` | 内容长度 |
| `argNames?` | `string[]` | 参数名 |
| `allowedTools?` | `string[]` | 允许的工具 |
| `model?` | `string` | 模型 |
| `source` | `SettingSource \| 'builtin' \| 'mcp' \| 'plugin' \| 'bundled'` | 来源 |
| `context?` | `'inline' \| 'fork'` | 执行上下文 |
| `agent?` | `string` | Fork 时的 Agent 类型 |
| `effort?` | `EffortValue` | 推理努力级别 |
| `paths?` | `string[]` | 文件路径 glob 模式 |
| `getPromptForCommand(args, ctx)` | 函数 | 获取命令提示 |

#### `LocalJSXCommandContext`

本地 JSX 命令上下文，扩展 `ToolUseContext`，添加：
- `canUseTool?` — 工具使用检查函数
- `setMessages` — 消息更新器
- `options.dynamicMcpConfig?` — 动态 MCP 配置
- `options.ideInstallationStatus` — IDE 安装状态
- `onChangeAPIKey` — API 密钥变更回调
- `resume?(sessionId, log, entrypoint)` — 恢复会话

#### `CommandBase`

命令基础属性：

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `string` | 命令名 |
| `description` | `string` | 描述 |
| `availability?` | `CommandAvailability[]` | 可用性（auth 要求） |
| `isEnabled?` | `() => boolean` | 是否启用 |
| `isHidden?` | `boolean` | 是否隐藏 |
| `aliases?` | `string[]` | 别名 |
| `isMcp?` | `boolean` | 是否 MCP 命令 |
| `argumentHint?` | `string` | 参数提示 |
| `userInvocable?` | `boolean` | 用户是否可调用 |
| `immediate?` | `boolean` | 立即执行（绕过队列） |
| `isSensitive?` | `boolean` | 是否敏感（参数脱敏） |

#### `Command`

`CommandBase & (PromptCommand | LocalCommand | LocalJSXCommand)` — 完整命令类型。

### 函数

- `getCommandName(cmd)` — 获取用户可见名称
- `isCommandEnabled(cmd)` — 检查是否启用（默认 `true`）

## hooks.ts — Hook 类型

### 函数

- `isHookEvent(value)` — 类型守卫：是否为有效 Hook 事件
- `isSyncHookJSONOutput(json)` — 类型守卫：是否同步 Hook 输出
- `isAsyncHookJSONOutput(json)` — 类型守卫：是否异步 Hook 输出

### Schema

- `promptRequestSchema` — 提示请求（prompt ID + 消息 + 选项）
- `syncHookResponseSchema` — 同步 Hook 响应（continue, suppressOutput, stopReason, decision, systemMessage, hookSpecificOutput）
- `hookJSONOutputSchema` — Hook JSON 输出联合 schema

### 类型

#### `PromptRequest`

| 字段 | 类型 | 说明 |
|------|------|------|
| `prompt` | `string` | 请求 ID |
| `message` | `string` | 显示消息 |
| `options` | `{ key, label, description? }[]` | 选项列表 |

#### `HookCallback`

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `'callback'` | 类型标识 |
| `callback` | 函数 | Hook 回调（接收 input, toolUseID, abort, context） |
| `timeout?` | `number` | 超时（秒） |
| `internal?` | `boolean` | 是否内部 Hook（排除指标） |

#### `HookCallbackMatcher`

| 字段 | 类型 | 说明 |
|------|------|------|
| `matcher?` | `string` | 匹配模式 |
| `hooks` | `HookCallback[]` | Hook 列表 |
| `pluginName?` | `string` | 插件名称 |

#### `HookResult`

Hook 执行结果：

| 字段 | 说明 |
|------|------|
| `message?` | 附加消息 |
| `systemMessage?` | 系统消息 |
| `blockingError?` | 阻塞错误 |
| `outcome` | `'success' \| 'blocking' \| 'non_blocking_error' \| 'cancelled'` |
| `preventContinuation?` | 是否阻止继续 |
| `permissionBehavior?` | 权限行为覆盖 |
| `additionalContext?` | 附加上下文 |
| `updatedInput?` | 更新的工具输入 |
| `retry?` | 是否重试 |

#### `AggregatedHookResult`

聚合 Hook 结果，包含多个 Hook 的合并输出。

## ids.ts — 品牌类型 ID

### 类型

- `SessionId` — 会话 ID（品牌字符串 `string & { readonly __brand: 'SessionId' }`）
- `AgentId` — Agent ID（品牌字符串 `string & { readonly __brand: 'AgentId' }`）

### 函数

- `asSessionId(id)` — 将字符串转为 SessionId
- `asAgentId(id)` — 将字符串转为 AgentId
- `toAgentId(s)` — 验证并转为 AgentId（格式 `a[label-]16hex`，不匹配返回 `null`）

## logs.ts — 日志类型

### 类型

#### `SerializedMessage`

消息序列化格式，扩展 `Message`：

| 字段 | 说明 |
|------|------|
| `cwd` | 工作目录 |
| `userType` | 用户类型 |
| `entrypoint?` | 入口点标识 |
| `sessionId` | 会话 ID |
| `timestamp` | ISO 时间戳 |
| `version` | CLI 版本 |
| `gitBranch?` | Git 分支 |
| `slug?` | 会话 slug |

#### `LogOption`

日志选项（会话列表显示用）：

| 字段 | 说明 |
|------|------|
| `date` | 日期字符串 |
| `messages` | 序列化消息数组 |
| `fullPath?` | 日志文件完整路径 |
| `value` | 排序值 |
| `created` | 创建时间 |
| `modified` | 修改时间 |
| `firstPrompt` | 首条提示 |
| `messageCount` | 消息数 |
| `fileSize?` | 文件大小 |
| `isSidechain` | 是否旁链 |
| `isLite?` | 是否精简模式 |
| `sessionId?` | 会话 ID |
| `customTitle?` | 自定义标题 |
| `tag?` | 标签 |
| `mode?` | `'coordinator' \| 'normal'` |
| `prNumber?` | 关联 PR 编号 |
| `projectPath?` | 原始项目路径 |

#### Transcript 元数据类型

- `SummaryMessage` — AI 摘要
- `CustomTitleMessage` — 用户自定义标题
- `AiTitleMessage` — AI 生成的标题
- `LastPromptMessage` — 最后一条提示
- `TaskSummaryMessage` — 任务摘要
- `TagMessage` — 标签
- `AgentNameMessage` / `AgentColorMessage` / `AgentSettingMessage` — Agent 元信息
- `PRLinkMessage` — PR 关联
- `ModeEntry` — 模式记录
- `WorktreeStateEntry` — 工作树状态
- `ContentReplacementEntry` — 内容替换记录
- `ContextCollapseCommitEntry` — 上下文折叠提交
- `ContextCollapseSnapshotEntry` — 上下文折叠快照
- `FileHistorySnapshotMessage` — 文件历史快照
- `AttributionSnapshotMessage` — 归因快照
- `SpeculationAcceptMessage` — 推测接受

#### `Entry`

所有 transcript 条目的联合类型。

### 函数

- `sortLogs(logs)` — 按修改时间降序排列日志

## permissions.ts — 权限类型

### 常量

- `EXTERNAL_PERMISSION_MODES` — 外部可用的权限模式：`['acceptEdits', 'bypassPermissions', 'default', 'dontAsk', 'plan']`
- `INTERNAL_PERMISSION_MODES` — 内部权限模式（含 `'auto'`）
- `PERMISSION_MODES` — 当前运行时可用模式

### 类型

#### `PermissionMode`

`'default' | 'acceptEdits' | 'bypassPermissions' | 'plan' | 'dontAsk' | 'auto' | 'bubble'`

> **注意**：
> - `'auto'` 模式需要 `TRANSCRIPT_CLASSIFIER` 特性启用
> - `'bubble'` 出现在类型定义中，但**不在**运行时 `INTERNAL_PERMISSION_MODES` 数组中（仅 `'auto'` 条件性添加）

#### `PermissionRule`

| 字段 | 说明 |
|------|------|
| `source` | 规则来源 |
| `ruleBehavior` | `'allow' \| 'deny' \| 'ask'` |
| `ruleValue` | `{ toolName, ruleContent? }` |

#### `PermissionUpdate`

权限更新操作联合类型（addRules / replaceRules / removeRules / setMode / addDirectories / removeDirectories）。

#### `PermissionDecision`

权限决策联合类型：
- `PermissionAllowDecision` — 允许（含 updatedInput, userModified, decisionReason）
- `PermissionAskDecision` — 询问（含 message, suggestions, pendingClassifierCheck）
- `PermissionDenyDecision` — 拒绝

#### `PermissionDecisionReason`

决策原因联合类型（rule / mode / subcommandResults / permissionPromptTool / hook / asyncAgent / sandboxOverride / classifier / workingDir / safetyCheck / other）。

#### `YoloClassifierResult`

自动模式分类器结果：

| 字段 | 说明 |
|------|------|
| `shouldBlock` | 是否应阻止 |
| `reason` | 原因 |
| `model` | 使用的模型 |
| `usage?` | Token 用量 |
| `durationMs?` | 耗时 |
| `stage?` | 分类阶段（fast / thinking） |
| `stage1Usage?` / `stage2Usage?` | 分阶段用量 |
| `transcriptTooLong?` | 转录是否过长 |

#### `ToolPermissionContext`

工具权限上下文：

| 字段 | 说明 |
|------|------|
| `mode` | 权限模式 |
| `additionalWorkingDirectories` | 额外工作目录 |
| `alwaysAllowRules` | 总是允许的规则 |
| `alwaysDenyRules` | 总是拒绝的规则 |
| `alwaysAskRules` | 总是询问的规则 |
| `isBypassPermissionsModeAvailable` | 绕过模式是否可用 |

## plugin.ts — 插件类型

### 类型

#### `BuiltinPluginDefinition`

内置插件定义：

| 字段 | 说明 |
|------|------|
| `name` | 插件名 |
| `description` | 描述 |
| `version?` | 版本 |
| `skills?` | 提供的技能 |
| `hooks?` | 提供的 Hook |
| `mcpServers?` | 提供的 MCP 服务器 |
| `isAvailable?()` | 是否可用 |
| `defaultEnabled?` | 默认启用状态 |

#### `LoadedPlugin`

已加载的插件：

| 字段 | 说明 |
|------|------|
| `name` / `manifest` / `path` / `source` / `repository` | 基础信息 |
| `enabled?` | 是否启用 |
| `isBuiltin?` | 是否内置 |
| `commandsPath?` / `skillsPath?` | 组件路径 |
| `hooksConfig?` / `mcpServers?` / `lspServers?` | 运行时配置 |

#### `PluginError`

25 种区分联合的插件错误类型，涵盖路径未找到、Git 认证、网络、清单解析、市场、MCP/LSP 配置、依赖、缓存等。

#### `PluginLoadResult`

`{ enabled: LoadedPlugin[], disabled: LoadedPlugin[], errors: PluginError[] }`

### 函数

- `getPluginErrorMessage(error)` — 从 PluginError 获取显示消息

## textInputTypes.ts — 文本输入类型

### 类型

#### `InlineGhostText`

内联幽灵文本（命令自动补全）：

| 字段 | 说明 |
|------|------|
| `text` | 显示的幽灵文本 |
| `fullCommand` | 完整命令名 |
| `insertPosition` | 插入位置 |

#### `BaseTextInputProps`

文本输入基础属性（30+ 字段），包含：
- `value`, `onChange`, `onSubmit`, `onExit` — 核心输入控制
- `placeholder`, `mask`, `showCursor`, `focus` — 显示控制
- `multiline` — 多行模式
- `onImagePaste`, `onPaste` — 粘贴处理
- `cursorOffset`, `onChangeCursorOffset` — 光标控制
- `highlights`, `inlineGhostText` — 高亮与补全
- `inputFilter` — 输入过滤器

#### `VimTextInputProps`

扩展 `BaseTextInputProps`，添加 `initialMode` 和 `onModeChange`。

#### `VimMode`

`'INSERT' | 'NORMAL'`

#### `PromptInputMode`

`'bash' | 'prompt' | 'orphaned-permission' | 'task-notification'`

#### `QueuePriority`

| 值 | 说明 |
|----|------|
| `'now'` | 立即中断发送 |
| `'next'` | 当前工具调用完成后发送 |
| `'later'` | 当前轮次结束后发送 |

#### `QueuedCommand`

队列命令：

| 字段 | 说明 |
|------|------|
| `value` | 字符串或 ContentBlockParam 数组 |
| `mode` | 输入模式 |
| `priority?` | 队列优先级 |
| `uuid?` | 消息 UUID |
| `pastedContents?` | 粘贴内容（含图片） |
| `skipSlashCommands?` | 跳过斜杠命令 |
| `bridgeOrigin?` | 来自桥接 |
| `isMeta?` | 元消息（隐藏但模型可见） |
| `origin?` | 消息来源 |
| `workload?` | 工作负载标签 |
| `agentId?` | 目标 Agent ID |

### 函数

- `isValidImagePaste(c)` — 检查是否为有效图片粘贴
- `getImagePasteIds(pastedContents)` — 提取图片粘贴 ID

---

# 三、constants/ — 常量定义

## apiLimits.ts — API 限制

| 常量 | 值 | 说明 |
|------|----|------|
| `API_IMAGE_MAX_BASE64_SIZE` | 5 MB | Base64 图片最大大小 |
| `IMAGE_TARGET_RAW_SIZE` | 3.75 MB | 原始图片目标大小 |
| `IMAGE_MAX_WIDTH` / `IMAGE_MAX_HEIGHT` | 2000px | 客户端最大尺寸 |
| `PDF_TARGET_RAW_SIZE` | 20 MB | PDF 原始大小上限 |
| `API_PDF_MAX_PAGES` | 100 | PDF 最大页数 |
| `PDF_EXTRACT_SIZE_THRESHOLD` | 3 MB | PDF 提取阈值 |
| `PDF_MAX_EXTRACT_SIZE` | 100 MB | PDF 提取最大大小 |
| `PDF_MAX_PAGES_PER_READ` | 20 | Read 工具单次最大页数 |
| `PDF_AT_MENTION_INLINE_THRESHOLD` | 10 | @ 引用内联阈值 |
| `API_MAX_MEDIA_PER_REQUEST` | 100 | 每请求最大媒体数 |

## betas.ts — Beta 头常量

| 常量 | 值 | 说明 |
|------|----|------|
| `CLAUDE_CODE_20250219_BETA_HEADER` | `'claude-code-20250219'` | Claude Code Beta |
| `INTERLEAVED_THINKING_BETA_HEADER` | `'interleaved-thinking-2025-05-14'` | 交错思考 |
| `CONTEXT_1M_BETA_HEADER` | `'context-1m-2025-08-07'` | 1M 上下文 |
| `CONTEXT_MANAGEMENT_BETA_HEADER` | `'context-management-2025-06-27'` | 上下文管理 |
| `STRUCTURED_OUTPUTS_BETA_HEADER` | `'structured-outputs-2025-12-15'` | 结构化输出 |
| `WEB_SEARCH_BETA_HEADER` | `'web-search-2025-03-05'` | Web 搜索 |
| `TOOL_SEARCH_BETA_HEADER_1P` | `'advanced-tool-use-2025-11-20'` | 工具搜索（1P） |
| `TOOL_SEARCH_BETA_HEADER_3P` | `'tool-search-tool-2025-10-19'` | 工具搜索（3P） |
| `EFFORT_BETA_HEADER` | `'effort-2025-11-24'` | 推理努力级别 |
| `TASK_BUDGETS_BETA_HEADER` | `'task-budgets-2026-03-13'` | 任务预算 |
| `FAST_MODE_BETA_HEADER` | `'fast-mode-2026-02-01'` | 快速模式 |
| `AFK_MODE_BETA_HEADER` | 条件：`'afk-mode-2026-01-31'`（需要 `feature('TRANSCRIPT_CLASSIFIER')`） | AFK 模式 |
| `REDACT_THINKING_BETA_HEADER` | `'redact-thinking-2026-02-12'` | 思考脱敏 |
| `TOKEN_EFFICIENT_TOOLS_BETA_HEADER` | `'token-efficient-tools-2026-03-28'` | Token 高效工具 |
| `ADVISOR_BETA_HEADER` | `'advisor-tool-2026-03-01'` | Advisor 工具 |
| `PROMPT_CACHING_SCOPE_BETA_HEADER` | `'prompt-caching-scope-2026-01-05'` | Prompt 缓存范围 |
| `SUMMARIZE_CONNECTOR_TEXT_BETA_HEADER` | 条件：`'summarize-connector-text-2026-03-13'`（需要 `CONNECTOR_TEXT` 特性） | Connector 文本摘要 |
| `CLI_INTERNAL_BETA_HEADER` | 条件：`'cli-internal-2026-02-09'`（需要 `USER_TYPE === 'ant'`） | CLI 内部特性 |

## common.ts — 通用工具

- `getLocalISODate()` — 获取本地 ISO 日期（YYYY-MM-DD）
- `getSessionStartDate` — 记忆化的会话开始日期（缓存稳定）
- `getLocalMonthYear()` — 获取 "Month YYYY" 格式

## cyberRiskInstruction.ts — 网络风险指令

- `CYBER_RISK_INSTRUCTION` — 安全相关行为边界指令字符串

## errorIds.ts — 错误 ID

- `E_TOOL_USE_SUMMARY_GENERATION_FAILED` = `344` — 工具摘要生成失败错误 ID
- 下一个可用 ID：346

## figures.ts — Unicode 图形常量

| 常量 | 字符 | 说明 |
|------|------|------|
| `BLACK_CIRCLE` | `⏺` / `●` | 黑色圆圈 |
| `BULLET_OPERATOR` | `∙` | 项目符号 |
| `TEARDROP_ASTERISK` | `✻` | 泪滴星号 |
| `UP_ARROW` / `DOWN_ARROW` | `↑` / `↓` | 箭头 |
| `LIGHTNING_BOLT` | `↯` | 闪电（快速模式） |
| `EFFORT_LOW` / `MEDIUM` / `HIGH` / `MAX` | `○` / `◐` / `●` / `◉` | 努力级别指示器 |
| `PLAY_ICON` / `PAUSE_ICON` | `▶` / `⏸` | 媒体控制 |
| `REFRESH_ARROW` | `↻` | 资源更新 |
| `DIAMOND_OPEN` / `DIAMOND_FILLED` | `◇` / `◆` | 审核状态 |
| `FLAG_ICON` | `⚑` | 问题标记 |
| `BLOCKQUOTE_BAR` | `▎` | 引用线 |

## files.ts — 文件相关常量

- `BINARY_EXTENSIONS` — 二进制文件扩展名集合（图片、视频、音频、压缩包、可执行文件、文档、字体、字节码、数据库、设计文件等）
- `hasBinaryExtension(filePath)` — 检查文件是否有二进制扩展名
- `isBinaryContent(buffer)` — 检查缓冲区是否包含二进制内容（检查 null 字节和 >10% 非打印字符）

## github-app.ts — GitHub App 常量

- `PR_TITLE` — PR 标题模板
- `GITHUB_ACTION_SETUP_DOCS_URL` — 设置文档 URL
- `WORKFLOW_CONTENT` — GitHub Actions 工作流模板
- `PR_BODY` — PR 描述模板
- `CODE_REVIEW_PLUGIN_WORKFLOW_CONTENT` — 代码审核工作流模板

## keys.ts — GrowthBook 密钥

- `getGrowthBookClientKey()` — 根据用户类型返回 GrowthBook SDK 密钥

## messages.ts — 消息常量

- `NO_CONTENT_MESSAGE` = `'(no content)'`

## oauth.ts — OAuth 配置

### 类型

#### `OauthConfig`

| 字段 | 说明 |
|------|------|
| `BASE_API_URL` | API 基础 URL |
| `CONSOLE_AUTHORIZE_URL` | Console 授权 URL |
| `CLAUDE_AI_AUTHORIZE_URL` | Claude.ai 授权 URL |
| `CLAUDE_AI_ORIGIN` | Claude.ai 来源 |
| `TOKEN_URL` | Token URL |
| `API_KEY_URL` | API 密钥 URL |
| `ROLES_URL` | 角色 URL |
| `CLIENT_ID` | 客户端 ID |
| `OAUTH_FILE_SUFFIX` | OAuth 文件后缀 |
| `MCP_PROXY_URL` / `MCP_PROXY_PATH` | MCP 代理配置 |

### 函数

- `getOauthConfig()` — 获取 OAuth 配置（支持 prod / staging / local / custom）
- `fileSuffixForOauthConfig()` — 获取 OAuth 文件后缀

### 常量

- `CLAUDE_AI_INFERENCE_SCOPE` — 推理权限范围
- `CLAUDE_AI_PROFILE_SCOPE` — 个人资料权限范围
- `OAUTH_BETA_HEADER` — OAuth Beta 头
- `CLAUDE_AI_OAUTH_SCOPES` — Claude.ai OAuth 权限列表
- `CONSOLE_OAUTH_SCOPES` — Console OAuth 权限列表
- `ALL_OAUTH_SCOPES` — 所有 OAuth 权限
- `MCP_CLIENT_METADATA_URL` — MCP 客户端元数据 URL

## outputStyles.ts — 输出风格

### 类型

#### `OutputStyleConfig`

| 字段 | 说明 |
|------|------|
| `name` | 风格名称 |
| `description` | 描述 |
| `prompt` | 系统提示 |
| `source` | 来源 |
| `keepCodingInstructions?` | 是否保留编码指令 |
| `forceForPlugin?` | 插件强制风格 |

### 常量

- `DEFAULT_OUTPUT_STYLE_NAME` = `'default'`
- `OUTPUT_STYLE_CONFIG` — 内置输出风格（default / Explanatory / Learning）

### 函数

- `getAllOutputStyles(cwd)` — 获取所有输出风格（含插件和自定义）
- `getOutputStyleConfig()` — 获取当前输出风格配置
- `hasCustomOutputStyle()` — 是否有自定义风格
- `clearAllOutputStylesCache()` — 清除缓存

## product.ts — 产品 URL

- `PRODUCT_URL` = `'https://claude.com/claude-code'`
- `CLAUDE_AI_BASE_URL` / `STAGING` / `LOCAL` — Claude.ai URL
- `isRemoteSessionStaging(sessionId?, ingressUrl?)` — 是否 staging 环境
- `isRemoteSessionLocal(sessionId?, ingressUrl?)` — 是否本地环境
- `getClaudeAiBaseUrl(sessionId?, ingressUrl?)` — 获取 Claude.ai 基础 URL
- `getRemoteSessionUrl(sessionId, ingressUrl?)` — 获取远程会话 URL

## prompts.ts — 系统提示

大型系统提示构建模块（914 行）。核心导出：

- `getSystemPrompt(tools, model)` — 获取完整系统提示
- 使用 `systemPromptSection()` 和 `DANGEROUS_uncachedSystemPromptSection()` 进行缓存优化

## spinnerVerbs.ts — 加载动画动词

- `SPINNER_VERBS` — 200+ 个趣味动词列表（如 'Accomplishing', 'Booping', 'Clauding', 'Quantumizing' 等）
- `getSpinnerVerbs()` — 获取动词列表（支持 replace / append 模式）

## system.ts — 系统常量

- `CLI_SYSPROMPT_PREFIXES` — 系统提示前缀集合
- `getCLISyspromptPrefix(options?)` — 获取系统提示前缀
- `getAttributionHeader(fingerprint)` — 获取 API 归因头

## systemPromptSections.ts — 系统提示段落

- `systemPromptSection(name, compute)` — 创建缓存型系统提示段落
- `DANGEROUS_uncachedSystemPromptSection(name, compute, reason)` — 创建非缓存型段落
- `resolveSystemPromptSections(sections)` — 解析所有段落
- `clearSystemPromptSections()` — 清除缓存

## toolLimits.ts — 工具限制

| 常量 | 值 | 说明 |
|------|----|------|
| `DEFAULT_MAX_RESULT_SIZE_CHARS` | 50,000 | 默认工具结果最大字符数 |
| `MAX_TOOL_RESULT_TOKENS` | 100,000 | 工具结果最大 Token 数 |
| `BYTES_PER_TOKEN` | 4 | 每字节 Token 估计 |
| `MAX_TOOL_RESULT_BYTES` | 400,000 | 工具结果最大字节数 |
| `MAX_TOOL_RESULTS_PER_MESSAGE_CHARS` | 200,000 | 每消息最大工具结果字符数 |
| `TOOL_SUMMARY_MAX_LENGTH` | 50 | 工具摘要最大长度 |

## tools.ts — 工具常量

- `ALL_AGENT_DISALLOWED_TOOLS` — 所有 Agent 禁用的工具集
- `CUSTOM_AGENT_DISALLOWED_TOOLS` — 自定义 Agent 禁用的工具集
- `ASYNC_AGENT_ALLOWED_TOOLS` — 异步 Agent 允许的工具集
- `IN_PROCESS_TEAMMATE_ALLOWED_TOOLS` — 进程内队友允许的工具集
- `COORDINATOR_MODE_ALLOWED_TOOLS` — 协调者模式允许的工具集

## turnCompletionVerbs.ts — 轮次完成动词

- `TURN_COMPLETION_VERBS` — 轮次完成消息使用的过去式动词：`['Baked', 'Brewed', 'Churned', 'Cogitated', 'Cooked', 'Crunched', 'Sautéed', 'Worked']`

## xml.ts — XML 标签常量

命令与消息的 XML 标签名：

| 常量 | 说明 |
|------|------|
| `COMMAND_NAME_TAG` | 命令名标签 |
| `COMMAND_MESSAGE_TAG` | 命令消息标签 |
| `COMMAND_ARGS_TAG` | 命令参数标签 |
| `BASH_INPUT_TAG` / `BASH_STDOUT_TAG` / `BASH_STDERR_TAG` | Bash I/O 标签 |
| `TERMINAL_OUTPUT_TAGS` | 所有终端输出标签数组 |
| `TICK_TAG` | 计时标签 |
| `TASK_NOTIFICATION_TAG` / `TASK_ID_TAG` 等 | 任务通知相关标签 |
| `ULTRAPLAN_TAG` | 超级计划模式标签 |
| `REMOTE_REVIEW_TAG` / `REMOTE_REVIEW_PROGRESS_TAG` | 远程审核标签 |
| `TEAMMATE_MESSAGE_TAG` | 队友消息标签 |
| `CHANNEL_MESSAGE_TAG` / `CHANNEL_TAG` | 通道消息标签 |
| `FORK_BOILERPLATE_TAG` / `FORK_DIRECTIVE_PREFIX` | Fork 样板标签 |
| `COMMON_HELP_ARGS` / `COMMON_INFO_ARGS` | 常见帮助/信息参数 |

---

# 四、schemas/ — JSON Schema 定义

## hooks.ts — Hook Schema

### Schema

#### `HookCommandSchema`

Hook 命令联合类型（4 种）：

**BashCommandHook** (`type: 'command'`)

| 字段 | 说明 |
|------|------|
| `command` | Shell 命令 |
| `if?` | 条件过滤（权限规则语法） |
| `shell?` | Shell 类型（bash / powershell） |
| `timeout?` | 超时（秒） |
| `statusMessage?` | 状态消息 |
| `once?` | 仅运行一次 |
| `async?` | 异步执行 |
| `asyncRewake?` | 异步 + 退出码 2 唤醒 |

**PromptHook** (`type: 'prompt'`)

| 字段 | 说明 |
|------|------|
| `prompt` | LLM 提示（支持 `$ARGUMENTS` 占位符） |
| `model?` | 使用的模型 |
| `timeout?` | 超时 |
| `once?` | 仅运行一次 |

**HttpHook** (`type: 'http'`)

| 字段 | 说明 |
|------|------|
| `url` | POST URL |
| `headers?` | 额外头（支持 `$VAR` 环境变量插值） |
| `allowedEnvVars?` | 允许插值的环境变量名列表 |
| `timeout?` | 超时 |
| `once?` | 仅运行一次 |

**AgentHook** (`type: 'agent'`)

| 字段 | 说明 |
|------|------|
| `prompt` | Agent 验证提示（支持 `$ARGUMENTS`） |
| `model?` | 使用的模型 |
| `timeout?` | 超时 |
| `once?` | 仅运行一次 |

#### `HookMatcherSchema`

| 字段 | 说明 |
|------|------|
| `matcher?` | 匹配模式（如工具名 "Write"） |
| `hooks` | Hook 命令列表 |

#### `HooksSchema`

`Partial<Record<HookEvent, HookMatcher[]>>` — Hook 事件到匹配器数组的映射。

### 推断类型

- `HookCommand` — Hook 命令联合类型
- `BashCommandHook` / `PromptHook` / `AgentHook` / `HttpHook` — 各类 Hook
- `HookMatcher` — 匹配器
- `HooksSettings` — Hook 设置（`Partial<Record<HookEvent, HookMatcher[]>>`）

---

# 五、query/ — 查询层

## config.ts — 查询配置

### 类型

#### `QueryConfig`

| 字段 | 类型 | 说明 |
|------|------|------|
| `sessionId` | `SessionId` | 会话 ID |
| `gates.streamingToolExecution` | `boolean` | 流式工具执行 |
| `gates.emitToolUseSummaries` | `boolean` | 发出工具使用摘要 |
| `gates.isAnt` | `boolean` | 是否内部用户 |
| `gates.fastModeEnabled` | `boolean` | 快速模式是否启用 |

### 函数

- `buildQueryConfig()` — 构建查询配置（快照一次，不随运行时变化）

## deps.ts — 查询依赖

### 类型

#### `QueryDeps`

查询 I/O 依赖，用于测试注入：

| 字段 | 说明 |
|------|------|
| `callModel` | 调用模型（流式） |
| `microcompact` | 微压缩消息 |
| `autocompact` | 自动压缩 |
| `uuid` | UUID 生成器 |

### 函数

- `productionDeps()` — 创建生产环境依赖

## stopHooks.ts — 停止 Hook 处理

### `handleStopHooks()`

异步生成器函数，处理轮次结束后的所有 Hook：

1. 保存缓存安全参数
2. 模板任务分类（如果 `CLAUDE_JOB_DIR` 存在）
3. 执行提示建议（非 bare 模式）
4. 执行记忆提取（如果启用）
5. 执行自动 Dream
6. 清理 Computer Use
7. 执行 Stop Hook
8. 对队友执行 TaskCompleted 和 TeammateIdle Hook

返回 `StopHookResult`：`{ blockingErrors: Message[], preventContinuation: boolean }`

## tokenBudget.ts — Token 预算管理

### 类型

#### `BudgetTracker`

| 字段 | 说明 |
|------|------|
| `continuationCount` | 继续次数 |
| `lastDeltaTokens` | 上次增量 Token |
| `lastGlobalTurnTokens` | 上次全局轮次 Token |
| `startedAt` | 开始时间 |

#### `TokenBudgetDecision`

决策联合类型：
- `{ action: 'continue', nudgeMessage, continuationCount, pct, turnTokens, budget }` — 继续
- `{ action: 'stop', completionEvent }` — 停止

### 函数

- `createBudgetTracker()` — 创建预算追踪器
- `checkTokenBudget(tracker, agentId, budget, globalTurnTokens)` — 检查 Token 预算

**预算决策逻辑**：
- 无预算或子 Agent → 直接停止
- 轮次 Token < 预算 × 90% 且无收益递减 → 继续
- 连续 3 次增量 < 500 Token → 收益递减 → 停止
- 其他情况 → 停止
