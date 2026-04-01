# 状态管理 (state/)

## state/store.ts — 核心状态存储

### 类型

- **`Store<T>`** — 通用状态存储接口
  - `getState: () => T` — 获取当前状态
  - `setState: (updater: (prev: T) => T) => void` — 通过 updater 函数更新状态（新旧引用相同时跳过通知）
  - `subscribe: (listener: () => void) => () => void` — 订阅状态变更，返回取消订阅函数

### 函数

- **`createStore<T>(initialState, onChange?)`** — 创建状态存储
  - 参数：`initialState: T` — 初始状态；`onChange?: (args: { newState: T; oldState: T }) => void` — 可选变更回调
  - 返回值：`Store<T>`

---

## state/AppStateStore.ts — AppState 类型定义与默认值

### 核心类型

- **`AppState`** — 全局应用状态，包含以下主要字段：
  - `settings: SettingsJson` — 合并后的设置
  - `verbose: boolean` — 详细模式
  - `mainLoopModel: ModelSetting` — 当前主循环模型
  - `statusLineText: string | undefined` — 状态栏文本
  - `expandedView: 'none' | 'tasks' | 'teammates'` — 展开视图类型
  - `toolPermissionContext: ToolPermissionContext` — 工具权限上下文（含 mode）
  - `tasks: { [taskId: string]: TaskState }` — 任务字典
  - `mcp: { clients, tools, commands, resources, pluginReconnectKey }` — MCP 连接状态
  - `plugins: { enabled, disabled, commands, errors, installationStatus, needsRefresh }` — 插件状态
  - `fileHistory: FileHistoryState` — 文件编辑历史
  - `notifications: { current, queue }` — 通知队列
  - `thinkingEnabled: boolean | undefined` — 思考模式
  - `speculation: SpeculationState` — 推测执行状态
  - `teamContext` — Swarm 团队上下文
  - `inbox` — 消息收件箱
  - `initialMessage` — 初始消息（来自 CLI 参数或 plan mode 退出）
  - `effortValue?: EffortValue` — 努力等级
  - `fastMode?: boolean` — 快速模式
  - `activeOverlays: ReadonlySet<string>` — 活跃的覆盖层（Escape 键协调）

- **`SpeculationState`** — 推测执行状态（idle | active）
- **`CompletionBoundary`** — 推测完成的边界类型（complete / bash / edit / denied_tool）
- **`FooterItem`** — 底栏项目类型（'tasks' | 'tmux' | 'bagel' | 'teams' | 'bridge' | 'companion'）

### 常量

- **`IDLE_SPECULATION_STATE`** — 空闲推测状态默认值 `{ status: 'idle' }`

### 函数

- **`getDefaultAppState(): AppState`** — 返回默认 AppState（含所有字段的初始值）

---

## state/AppState.tsx — React Provider 与 Hooks

### 组件

- **`AppStateProvider`** — 顶层状态 Provider
  - Props：`children: React.ReactNode`；`initialState?: AppState`；`onChangeAppState?: (args) => void`
  - 内部创建 `Store<AppState>`，包裹 `MailboxProvider` 和 `VoiceProvider`

### Hooks

- **`useAppState<T>(selector: (s: AppState) => T): T`** — 订阅状态切片，仅在选中值变化时重渲染
  - 提示：返回已有子对象引用，不要在 selector 中创建新对象
- **`useSetAppState(): (updater: (prev: AppState) => AppState) => void`** — 获取 setState 函数（不订阅任何状态）
- **`useAppStateStore(): Store<AppState>`** — 获取完整 Store 实例（用于传递给非 React 代码）
- **`useAppStateMaybeOutsideOfProvider<T>(selector): T | undefined`** — 安全版 useAppState，在 Provider 外返回 undefined

### 重导出

- `AppState`, `AppStateStore`, `CompletionBoundary`, `getDefaultAppState`, `IDLE_SPECULATION_STATE`, `SpeculationResult`, `SpeculationState`

---

## state/onChangeAppState.ts — 状态变更监听

### 函数

- **`onChangeAppState({ newState, oldState })`** — 状态变更回调，处理以下副作用：
  - 权限模式变更 → 通知 CCR 和 SDK
  - mainLoopModel 变更 → 更新设置文件和启动状态
  - expandedView 变更 → 持久化到 globalConfig
  - verbose 变更 → 持久化到 globalConfig
  - settings 变更 → 清除认证缓存、重新应用环境变量

- **`externalMetadataToAppState(metadata)`** — 将外部元数据恢复为 AppState 更新函数
  - 参数：`metadata: SessionExternalMetadata`
  - 返回值：`(prev: AppState) => AppState`

---

## state/selectors.ts — 状态选择器

- **`getViewedTeammateTask(appState)`** — 获取当前查看的 teammate 任务
  - 参数：`Pick<AppState, 'viewingAgentTaskId' | 'tasks'>`
  - 返回值：`InProcessTeammateTaskState | undefined`

- **`getActiveAgentForInput(appState)`** — 确定用户输入应路由到哪个 agent
  - 返回值：`ActiveAgentForInput`（`{ type: 'leader' }` | `{ type: 'viewed', task }` | `{ type: 'named_agent', task }`）

---

## state/teammateViewHelpers.ts — Teammate 视图切换

- **`enterTeammateView(taskId, setAppState)`** — 进入 teammate 转录视图
  - 设置 `viewingAgentTaskId`，对 local_agent 设置 `retain: true`
- **`exitTeammateView(setAppState)`** — 退出 teammate 视图，释放 retain
- **`stopOrDismissAgent(taskId, setAppState)`** — 上下文相关操作：运行中→中止，已终止→消除

---

# 工具函数 (utils/)

## 一、权限相关 (utils/permissions/)

### permissions/permissions.ts — 权限检查核心

权限系统主入口，处理所有工具的权限检查逻辑。

- **`checkPermissions(tool, input, context, ...)`** — 检查工具是否有权执行
  - 涉及规则匹配、模式检查、sandbox 判定等
- **`applyPermissionRulesToPermissionContext(ctx, rules)`** — 将规则应用到权限上下文
- **`getRuleByContentsForToolName(...)`** — 按内容查找规则
- **`syncPermissionRulesFromDisk(ctx, rules)`** — 从磁盘同步权限规则
- **`getAllowRules(ctx)` / `getDenyRules(ctx)` / `getAskRules(ctx)`** — 获取各类规则列表
- **`permissionRuleSourceDisplayString(source)`** — 规则来源显示字符串

### permissions/PermissionMode.ts — 权限模式

- **`permissionModeSchema`** — 权限模式的 Zod schema
- **`externalPermissionModeSchema`** — 外部权限模式 schema
- **`permissionModeTitle(mode)`** — 获取模式标题
- **`permissionModeFromString(s)`** — 从字符串解析权限模式
- **`toExternalPermissionMode(mode)`** — 转换为外部可见模式

模式类型：`'default' | 'plan' | 'acceptEdits' | 'bypassPermissions' | 'dontAsk' | 'auto'`

### permissions/PermissionRule.ts — 权限规则类型

- **`permissionBehaviorSchema`** — 行为 schema (`'allow' | 'deny' | 'ask'`)
- **`permissionRuleValueSchema`** — 规则值 schema（`{ toolName, ruleContent? }`）

### permissions/PermissionResult.ts — 权限结果类型

- **`getRuleBehaviorDescription(behavior)`** — 获取规则行为的文字描述
  - `'allow'` → `'allowed'`，`'deny'` → `'denied'`，`'ask'` → `'asked for confirmation for'`

### permissions/PermissionUpdate.ts — 权限更新

- **`applyPermissionUpdate(ctx, update)`** — 应用单个权限更新到上下文
- **`applyPermissionUpdates(ctx, updates)`** — 批量应用权限更新
- **`persistPermissionUpdates(updates)`** — 持久化权限更新到磁盘
- **`extractRules(updates)`** — 从更新列表提取规则
- **`hasRules(updates)`** — 检查更新列表是否包含规则
- **`createReadRuleSuggestion(path)`** — 创建读取规则建议
- **`createWriteRuleSuggestion(path)`** — 创建写入规则建议

### permissions/PermissionUpdateSchema.ts — 权限更新 Schema

定义权限更新的 Zod schema，支持类型：
- `addRules` — 添加规则
- `replaceRules` — 替换规则
- `removeRules` — 删除规则
- `setMode` — 设置模式
- `addDirectories` / `removeDirectories` — 添加/移除工作目录

### permissions/permissionsLoader.ts — 权限规则加载

- **`shouldAllowManagedPermissionRulesOnly()`** — 是否仅允许托管权限规则
- **`shouldShowAlwaysAllowOptions()`** — 是否显示"始终允许"选项
- **`loadAllPermissionRulesFromDisk()`** — 从磁盘加载所有权限规则
- **`addPermissionRulesToSettings(source, rules, behavior)`** — 添加规则到设置
- **`deletePermissionRuleFromSettings(source, rule)`** — 从设置删除规则

### permissions/permissionSetup.ts — 权限初始化设置

大型模块，处理权限系统的初始化、模式转换、工作目录管理等：

- **`getToolPermissionContext(mode, cwd)`** — 获取初始工具权限上下文
- **`transitionPermissionMode(ctx, newMode, ...)`** — 转换权限模式
- **`createDisabledBypassPermissionsContext(ctx)`** — 创建禁用绕过权限的上下文
- **`isBypassPermissionsModeDisabled()`** — 绕过权限模式是否被禁用
- **`findOverlyBroadBashPermissions(rules, extraRules)`** — 查找过于宽泛的 Bash 权限
- **`removeDangerousPermissions(ctx, rules)`** — 移除危险权限
- **`transitionPlanAutoMode(ctx)`** — plan/auto 模式转换
- **`verifyAutoModeGateAccess()`** — 验证 auto mode 门控访问

### permissions/bashClassifier.ts — Bash 命令分类器

外部构建的 stub 实现（ant-only 功能，外部构建中禁用）：

- **`classifyBashCommand(command, cwd, descriptions, behavior, signal, isNonInteractive)`** — 分类 Bash 命令
  - 返回值：`Promise<ClassifierResult>` — `{ matches, confidence, reason }`
- **`isClassifierPermissionsEnabled()`** — 分类器权限是否启用（外部构建返回 false）
- **`extractPromptDescription(ruleContent)`** — 提取规则描述
- **`createPromptRuleContent(description)`** — 创建规则内容
- **`getBashPrompt{Deny|Ask|Allow}Descriptions(context)`** — 获取各行为的描述列表
- **`generateGenericDescription(command, specificDescription, signal)`** — 生成通用描述

### permissions/yoloClassifier.ts — YOLO 模式分类器

自动模式下的安全分类器，使用 LLM 判断工具调用安全性：

- **`runYoloClassifier(messages, tools, toolUseRequest, context, signal, ...)`** — 运行分类器
  - 返回值：`Promise<YoloClassifierResult>`
- **`getYoloClassifierUsage()`** — 获取分类器使用统计
- **`clearClassifierChecking()` / `setClassifierChecking(v)`** — 控制分类器并发

### permissions/classifierShared.ts — 分类器共享工具

- **`extractToolUseBlock(content, toolName)`** — 从消息内容提取工具调用块
- **`parseClassifierResponse(toolUseBlock, schema)`** — 解析并验证分类器响应

### permissions/classifierDecision.ts — 分类器决策

- **`getSafeYoloAllowlistedTools()`** — 获取 YOLO 模式安全工具白名单
- **`isToolAllowedWithoutClassification(toolName)`** — 工具是否无需分类即可使用

### permissions/shellRuleMatching.ts — Shell 规则匹配

- **`permissionRuleExtractPrefix(rule)`** — 提取旧版 `:*` 前缀语法
- **`hasWildcards(pattern)`** — 检查是否包含未转义通配符
- **`parseShellPermissionRule(ruleContent)`** — 解析 shell 权限规则
- **`matchShellPermissionRule(rule, command)`** — 匹配命令到规则
- **`generatePermissionSuggestion(toolName, command, rules)`** — 生成权限建议

### permissions/pathValidation.ts — 路径验证

- **`expandTilde(path)`** — 展开波浪号
- **`getGlobBaseDirectory(path)`** — 获取 glob 模式的基础目录
- **`formatDirectoryList(directories)`** — 格式化目录列表
- **`checkPathForTool(toolName, input, context, operation)`** — 检查路径权限
  - 返回值：`PathCheckResult` — `{ allowed, decisionReason? }`

### permissions/permissionExplainer.ts — 权限说明器

- **`generatePermissionExplanation(params)`** — 生成权限说明（使用 LLM 分析命令风险）
  - 参数：`{ toolName, toolInput, toolDescription?, messages?, signal }`
  - 返回值：`Promise<PermissionExplanation>` — `{ riskLevel, explanation, reasoning, risk }`

### permissions/filesystem.ts — 文件系统权限

文件系统权限的核心模块，处理工作目录、安全路径、自动编辑检查等：

- **`DANGEROUS_FILES`** — 危险文件列表（`.gitconfig`, `.bashrc`, `.zshrc` 等）
- **`DANGEROUS_DIRECTORIES`** — 危险目录列表（`.git`, `.vscode`, `.claude` 等）
- **`pathInWorkingPath(path, context)`** — 路径是否在工作目录内
- **`pathInAllowedWorkingPath(path, context)`** — 路径是否在允许的工作目录内
- **`checkEditableInternalPath(path, context)`** — 检查路径是否可编辑
- **`checkReadableInternalPath(path, context)`** — 检查路径是否可读
- **`checkPathSafetyForAutoEdit(path, content)`** — 自动编辑安全性检查
- **`toPosixPath(path)`** — 转换为 POSIX 路径
- **`getClaudeTempDir()`** — 获取 Claude 临时目录

### permissions/getNextPermissionMode.ts — 权限模式循环

- **`getNextPermissionMode(toolPermissionContext, teamContext?)`** — Shift+Tab 循环获取下一个权限模式
  - 循环顺序：default → acceptEdits → plan → bypassPermissions → auto → default

### permissions/denialTracking.ts — 拒绝追踪

- **`createDenialTrackingState()`** — 创建拒绝追踪状态
- **`recordDenial(state)`** — 记录一次拒绝
- **`recordSuccess(state)`** — 记录一次成功（重置连续拒绝计数）
- **`shouldFallbackToPrompting(state)`** — 是否应回退到用户提示（连续≥3 或总计≥20）

### permissions/permissionRuleParser.ts — 规则解析

- **`normalizeLegacyToolName(name)`** — 标准化旧工具名（Task→Agent 等）
- **`getLegacyToolNames(canonicalName)`** — 获取某工具的所有旧名称
- **`escapeRuleContent(content)`** — 转义规则内容中的特殊字符
- **`unescapeRuleContent(content)`** — 反转义规则内容
- **`permissionRuleValueFromString(s)`** — 从字符串解析规则值
- **`permissionRuleValueToString(v)`** — 规则值转字符串

### permissions/shadowedRuleDetection.ts — 遮蔽规则检测

- **`isSharedSettingSource(source)`** — 是否为共享设置来源
- **`detectUnreachableRules(ctx, options?)`** — 检测被遮蔽的不可达规则

### permissions/dangerousPatterns.ts — 危险模式列表

- **`CROSS_PLATFORM_CODE_EXEC`** — 跨平台代码执行入口（python, node, bash 等）
- **`DANGEROUS_BASH_PATTERNS`** — 危险 Bash 模式（含 ant-only 扩展）

### permissions/autoModeState.ts — 自动模式状态

- **`setAutoModeActive(active)`** — 设置自动模式活跃状态
- **`isAutoModeActive()`** — 查询自动模式是否活跃
- **`setAutoModeFlagCli(passed)`** — 设置 CLI 标志
- **`getAutoModeFlagCli()`** — 获取 CLI 标志
- **`setAutoModeCircuitBroken(broken)` / `isAutoModeCircuitBroken()`** — 熔断器状态

### permissions/bypassPermissionsKillswitch.ts — 绕过权限开关

- **`checkAndDisableBypassPermissionsIfNeeded(ctx, setAppState)`** — 检查并禁用绕过权限
- **`resetBypassPermissionsCheck()`** — 重置检查标志
- **`useKickOffCheckAndDisableBypassPermissionsIfNeeded()`** — React Hook 版本
- **`checkAndDisableAutoModeIfNeeded(ctx, setAppState, fastMode?)`** — 检查并禁用自动模式

### permissions/PermissionPromptToolResultSchema.ts — 权限提示结果 Schema

MCP 权限提示工具的输入/输出 Zod schema 定义，用于 SDK 通道的权限检查。

---

## 二、设置相关 (utils/settings/)

### settings/settings.ts — 设置管理核心

- **`getInitialSettings(): SettingsJson`** — 获取合并后的初始设置（按优先级合并所有来源）
- **`getSettingsForSource(source)`** — 获取指定来源的设置
- **`getSettingsFilePathForSource(source)`** — 获取设置文件路径
- **`getSettingsRootPathForSource(source)`** — 获取设置根路径
- **`getSettings_DEPRECATED()`** — 旧版设置获取（向后兼容）
- **`updateSettingsForSource(source, updates)`** — 更新指定来源的设置
- **`getSettingsWithErrors()`** — 获取带验证错误的设置
- **`loadManagedFileSettings()`** — 加载托管文件设置
- **`getAutoModeConfig()`** — 获取自动模式配置

设置合并优先级（低→高）：plugins → userSettings → projectSettings → localSettings → flagSettings → policySettings → remoteManaged

### settings/types.ts — 设置类型定义

- **`SettingsSchema`** — 设置的 Zod schema
- **`SettingsJson`** — 设置 JSON 类型，主要字段：
  - `permissions` — 权限规则（allow/deny/ask/defaultMode/additionalDirectories）
  - `env` — 环境变量
  - `model` — 模型设置
  - `hooks` — 钩子配置
  - `mcpServers` — MCP 服务器配置
  - `apiKeyHelper` — API Key 辅助命令
  - `cleanupPeriodDays` — 清理周期
  - `effortLevel` — 努力等级

### settings/applySettingsChange.ts — 设置变更应用

- **`applySettingsChange(source, setAppState)`** — 应用设置变更到 AppState
  - 重新从磁盘读取设置、重载权限规则、更新 hooks 快照
  - 同时同步 effortLevel 到 AppState

### settings/constants.ts — 设置常量

- **`SETTING_SOURCES`** — 设置来源列表：`['userSettings', 'projectSettings', 'localSettings', 'flagSettings', 'policySettings']`
- **`getSettingSourceName(source)`** — 获取来源显示名
- **`getSourceDisplayName(source)`** — 获取来源短名（首字母大写）
- **`getSettingSourceDisplayNameLowercase(source)`** — 获取小写显示名
- **`getEnabledSettingSources()`** — 获取当前启用的设置来源

### settings/settingsCache.ts — 设置缓存

- **`getSessionSettingsCache()` / `setSessionSettingsCache()`** — 会话级缓存
- **`getCachedSettingsForSource(source)` / `setCachedSettingsForSource(source, value)`** — 按来源缓存
- **`getCachedParsedFile(path)` / `setCachedParsedFile(path, value)`** — 按路径缓存
- **`resetSettingsCache()`** — 重置所有缓存
- **`getPluginSettingsBase()` / `setPluginSettingsBase(settings)`** — 插件设置基础层

### settings/managedPath.ts — 托管设置路径

- **`getManagedFilePath()`** — 获取托管设置文件路径（macOS: `/Library/Application Support/ClaudeCode`，Linux: `/etc/claude-code`）
- **`getManagedSettingsDropInDir()`** — 获取托管设置 drop-in 目录

### settings/changeDetector.ts — 设置文件变更检测

使用 chokidar 监听设置文件变更，支持内部写入过滤和 MDM 设置轮询：

- **`initSettingsChangeDetector()`** — 初始化设置变更检测器
- **`disposeSettingsChangeDetector()`** — 销毁检测器
- **`onSettingsChanged(handler)`** — 注册变更处理器
  - 返回值：取消注册函数

### settings/internalWrites.ts — 内部写入追踪

- **`markInternalWrite(path)`** — 标记内部写入
- **`consumeInternalWrite(path, windowMs)`** — 消费内部写入标记（5s 窗口内匹配则抑制通知）
- **`clearInternalWrites()`** — 清除所有标记

### settings/validationTips.ts — 验证提示

- **`getValidationTip(context)`** — 获取设置验证错误的人性化提示
  - 参数：`TipContext` — `{ path, code, expected?, received?, ... }`
  - 返回值：`ValidationTip` — `{ suggestion?, docLink? }`

### settings/schemaOutput.ts — Schema 输出

- **`generateSettingsJSONSchema()`** — 生成 settings 的 JSON Schema 字符串

### settings/permissionValidation.ts — 权限规则验证

- **`validatePermissionRule(rule)`** — 验证权限规则格式
  - 返回值：`{ valid, error?, suggestion?, examples? }`
- **`PermissionRuleSchema`** — 权限规则的 Zod schema

### settings/pluginOnlyPolicy.ts — 仅插件策略

- **`isRestrictedToPluginOnly(surface)`** — 检查自定义面是否被锁定为仅插件来源
- **`isSourceAdminTrusted(source)`** — 来源是否为管理员信任的（plugin / policySettings / built-in）

### settings/toolValidationConfig.ts — 工具验证配置

- **`TOOL_VALIDATION_CONFIG`** — 工具验证配置对象
  - `filePatternTools` — 接受文件 glob 模式的工具（Read, Write, Edit, Glob 等）
  - `bashPrefixTools` — 接受 Bash 通配符的工具
  - `customValidation` — 自定义验证规则（WebSearch, WebFetch 等）

### settings/validateEditTool.ts — 编辑工具验证

- **`validateInputForSettingsFileEdit(filePath, originalContent, getUpdatedContent)`** — 验证设置文件编辑
  - 返回值：验证失败时返回错误信息，通过时返回 null

### settings/allErrors.ts — 全部错误聚合

- **`getSettingsWithAllErrors()`** — 获取包含 MCP 配置错误在内的所有设置验证错误

---

## 三、模型相关 (utils/model/)

### model/model.ts — 模型管理核心

- **`getSmallFastModel()`** — 获取小型快速模型
- **`getDefaultMainLoopModelSetting()`** — 获取默认主循环模型设置
- **`getDefaultSonnetModel()` / `getDefaultOpusModel()` / `getDefaultHaikuModel()`** — 获取默认 Sonnet/Opus/Haiku 模型
- **`getUserSpecifiedModelSetting()`** — 获取用户指定的模型（优先级：会话覆盖 > CLI 标志 > 环境变量 > 设置）
- **`parseUserSpecifiedModel(input)`** — 解析用户指定的模型字符串
- **`getCanonicalName(model)`** — 获取模型规范名
- **`getRuntimeMainLoopModel()`** — 获取运行时主循环模型
- **`renderDefaultModelSetting(setting)`** — 渲染默认模型设置描述
- **`isNonCustomOpusModel(model)`** — 是否为非自定义 Opus 模型
- **`getClaudeAiUserDefaultModelDescription(fastMode)`** — 获取 Claude.ai 用户默认模型描述

类型：`ModelShortName`, `ModelName`, `ModelSetting`

### model/providers.ts — API 提供商

- **`getAPIProvider()`** — 获取当前 API 提供商（firstParty / bedrock / vertex / foundry）
- **`isFirstPartyAnthropicBaseUrl()`** — 检查是否为第一方 API URL
- **`getAPIProviderForStatsig()`** — 获取用于分析上报的提供商

类型：`APIProvider = 'firstParty' | 'bedrock' | 'vertex' | 'foundry'`

### model/aliases.ts — 模型别名

- **`MODEL_ALIASES`** — `['sonnet', 'opus', 'haiku', 'best', 'sonnet[1m]', 'opus[1m]', 'opusplan']`
- **`isModelAlias(input)`** — 是否为模型别名
- **`MODEL_FAMILY_ALIASES`** — `['sonnet', 'opus', 'haiku']`
- **`isModelFamilyAlias(model)`** — 是否为模型家族别名

### model/configs.ts — 模型配置常量

每个模型跨提供商的配置映射，例如：
- **`CLAUDE_OPUS_4_6_CONFIG`** — `{ firstParty: 'claude-opus-4-6', bedrock: '...', vertex: '...', foundry: '...' }`
- **`CLAUDE_SONNET_4_CONFIG`**, **`CLAUDE_HAIKU_4_5_CONFIG`**, **`CLAUDE_OPUS_4_5_CONFIG`** 等

### model/modelStrings.ts — 模型字符串映射

- **`getModelStrings()`** — 获取当前提供商的模型字符串映射
- **`setModelStrings(ms)`** — 设置模型字符串映射
- **`resolveOverriddenModel(model)`** — 解析被覆盖的模型 ID

### model/modelCapabilities.ts — 模型能力查询

- **`getModelCapability(model)`** — 获取模型能力（max_input_tokens, max_tokens 等）
- **`getContextWindowForModel(model)`** — 获取模型上下文窗口大小

### model/modelOptions.ts — 模型选项 UI

- **`getDefaultOptionForUser(fastMode?)`** — 获取用户默认模型选项
- **`getModelOptions()`** — 获取所有可用模型选项列表
- **`getModelOptionsIncludingCustom(customModel?)`** — 包含自定义模型的选项列表

类型：`ModelOption = { value, label, description }`

### model/validateModel.ts — 模型验证

- **`validateModel(model)`** — 通过实际 API 调用验证模型是否可用
  - 返回值：`Promise<{ valid, error? }>`

### model/modelAllowlist.ts — 模型白名单

- **`isModelAllowed(model)`** — 检查模型是否在允许列表中
- **`getAvailableModels()`** — 获取可用模型列表

### model/modelSupportOverrides.ts — 第三方模型能力覆盖

- **`get3PModelCapabilityOverride(model, capability)`** — 获取第三方模型能力覆盖
  - capability 类型：`'effort' | 'max_effort' | 'thinking' | 'adaptive_thinking' | 'interleaved_thinking'`

### model/deprecation.ts — 模型废弃信息

- **`getDeprecatedModelInfo(modelId)`** — 获取模型废弃信息（含退休日期）
- **`getModelDeprecationMessage(modelId)`** — 获取废弃警告消息

### model/contextWindowUpgradeCheck.ts — 上下文窗口升级

- **`getUpgradeMessage(context)`** — 获取上下文窗口升级提示
  - context: `'warning' | 'tip'`

### model/agent.ts — 子代理模型

- **`getAgentModel(agentModel, parentModel, toolSpecifiedModel?, permissionMode?)`** — 获取子代理有效模型
- **`getDefaultSubagentModel()`** — 获取默认子代理模型（返回 `'inherit'`）

### model/bedrock.ts — AWS Bedrock 集成

- **`getBedrockInferenceProfiles()`** — 获取 Bedrock 推理配置文件列表
- **`findFirstMatch(profiles, substring)`** — 在配置文件中查找匹配
- **`getBedrockRegionPrefix(model)`** — 获取 Bedrock 区域前缀
- **`applyBedrockRegionPrefix(model, prefix)`** — 应用区域前缀

### model/check1mAccess.ts — 1M 上下文访问检查

- **`checkOpus1mAccess()`** — 检查 Opus 1M 上下文访问权限
- **`checkSonnet1mAccess()`** — 检查 Sonnet 1M 上下文访问权限

### modelCost.ts — 模型成本计算

- **`getModelCosts(model)`** — 获取模型费用配置
  - 返回值：`ModelCosts` — `{ inputTokens, outputTokens, promptCacheWriteTokens, promptCacheReadTokens, webSearchRequests }`
- **`formatModelPricing(costs)`** — 格式化模型价格显示
- **`getOpus46CostTier()`** — 获取 Opus 4.6 成本层级（fast mode 影响价格）

常量：`COST_TIER_3_15`, `COST_TIER_15_75`, `COST_TIER_5_25`, `COST_TIER_30_150`, `COST_HAIKU_35`, `COST_HAIKU_45`

---

## 四、Git 相关 (utils/git/)

### git/gitConfigParser.ts — Git 配置解析

轻量级 `.git/config` 解析器：

- **`parseGitConfigValue(gitDir, section, subsection, key)`** — 解析 .git/config 中的值
  - 参数：`gitDir` — .git 目录；`section` — 段名（如 `'remote'`）；`subsection` — 子段名（如 `'origin'`）；`key` — 键名（如 `'url'`）
  - 返回值：`Promise<string | null>`
- **`parseConfigString(config, section, subsection, key)`** — 从内存字符串解析配置

### git/gitFilesystem.ts — Git 文件系统操作

不启动 git 子进程的文件系统级 Git 状态读取：

- **`resolveGitDir(startPath?)`** — 解析 .git 目录（支持 worktree/submodule）
- **`clearResolveGitDirCache()`** — 清除缓存
- **`readGitHead(gitDir)`** — 读取 HEAD 引用
- **`resolveRef(gitDir, ref)`** — 解析引用到 SHA（支持 loose refs 和 packed-refs）
- **`isShallowRepo(gitDir)`** — 是否为浅克隆
- **`GitHeadWatcher`** — 监听 HEAD 变化的类（使用 fs.watchFile）

### git/gitignore.ts — Gitignore 操作

- **`isPathGitignored(filePath, cwd)`** — 检查路径是否被 gitignore
- **`getGlobalGitignorePath()`** — 获取全局 gitignore 路径（`~/.config/git/ignore`）
- **`addFileGlobRuleToGitignore(filename, cwd?)`** — 添加文件 glob 规则到全局 gitignore

---

## 五、文件操作

### fileRead.ts — 文件读取

无循环依赖的同步文件读取工具：

- **`detectEncodingForResolvedPath(resolvedPath)`** — 检测文件编码（支持 BOM 检测）
  - 返回值：`BufferEncoding`
- **`detectLineEndingsForString(content)`** — 检测行尾类型
  - 返回值：`'CRLF' | 'LF'`
- **`readFileSyncWithMetadata(filePath)`** — 带元数据的同步读取
  - 返回值：`{ content, encoding, lineEndings }`

类型：`LineEndingType = 'CRLF' | 'LF'`

### fileOperationAnalytics.ts — 文件操作分析

- **`logFileOperation(params)`** — 记录文件操作分析事件
  - 参数：`{ operation: 'read' | 'write' | 'edit', tool, filePath, content?, type? }`

---

## 六、插件相关 (utils/plugins/)

### 插件加载与管理

- **pluginLoader.ts** — `loadPluginsFromSources()` 加载插件、`refreshActivePlugins()` 刷新活跃插件
- **pluginDirectories.ts** — 插件目录解析
- **pluginIdentifier.ts** — 插件标识符解析
- **pluginVersioning.ts** — 插件版本管理
- **validatePlugin.ts** — 插件验证
- **pluginPolicy.ts** — 插件策略检查
- **pluginFlagging.ts** — 插件标记
- **pluginBlocklist.ts** — 插件黑名单
- **pluginAutoupdate.ts** — 插件自动更新
- **pluginStartupCheck.ts** — 插件启动检查
- **pluginOptionsStorage.ts** — 插件选项存储

### 插件安装与市场

- **marketplaceManager.ts** — 市场管理器
- **marketplaceHelpers.ts** — 市场辅助函数
- **officialMarketplace.ts** — 官方市场
- **officialMarketplaceGcs.ts** — 官方市场 GCS 存储
- **officialMarketplaceStartupCheck.ts** — 官方市场启动检查
- **parseMarketplaceInput.ts** — 解析市场输入
- **pluginInstallationHelpers.ts** — 插件安装辅助
- **installCounts.ts** — 安装计数
- **managedPlugins.ts** — 托管插件
- **installedPluginsManager.ts** — 已安装插件管理
- **headlessPluginInstall.ts** — 无头模式插件安装
- **addDirPluginSettings.ts** — 添加目录插件设置

### 插件集成

- **mcpPluginIntegration.ts** — MCP 插件集成
- **mcpbHandler.ts** — MCPB 文件处理
- **lspPluginIntegration.ts** — LSP 插件集成
- **lspRecommendation.ts** — LSP 推荐
- **hintRecommendation.ts** — 提示推荐

### 插件能力加载

- **loadPluginCommands.ts** — 加载插件命令
- **loadPluginAgents.ts** — 加载插件代理
- **loadPluginHooks.ts** — 加载插件钩子
- **loadPluginOutputStyles.ts** — 加载插件输出样式
- **walkPluginMarkdown.ts** — 遍历插件 Markdown

### 缓存与依赖

- **cacheUtils.ts** — 缓存工具
- **zipCache.ts** / **zipCacheAdapters.ts** — ZIP 缓存
- **dependencyResolver.ts** — 依赖解析器
- **schemas.ts** — 插件 schema 定义
- **fetchTelemetry.ts** — 获取遥测数据
- **gitAvailability.ts** — Git 可用性检查
- **reconciler.ts** — 插件状态协调器
- **refresh.ts** — 插件刷新

---

## 七、性能分析

### startupProfiler.ts — 启动性能分析

- **`profileCheckpoint(name)`** — 记录启动检查点
- **`getProfileReport()`** — 获取格式化的性能报告（仅 `CLAUDE_CODE_PROFILE_STARTUP=1` 时可用）

两种模式：
1. 采样日志：ant 用户 100%，外部用户 0.5% → 上报到 Statsig
2. 详细分析：`CLAUDE_CODE_PROFILE_STARTUP=1` → 完整报告含内存快照

### profilerBase.ts — 性能分析基础

- **`getPerformance()`** — 获取 Performance API 实例
- **`formatMs(ms)`** — 格式化毫秒
- **`formatTimelineLine(...)`** — 格式化时间线行

---

## 八、其他工具函数

### auth.ts — 认证管理

核心认证模块，支持多种认证方式：

- **`getApiKey()`** — 获取 API Key（支持 OAuth、环境变量、keychain、apiKeyHelper）
- **`clearApiKeyHelperCache()`** — 清除 apiKeyHelper 缓存
- **`clearAwsCredentialsCache()`** / **`clearGcpCredentialsCache()`** — 清除 AWS/GCP 凭证缓存
- **`isClaudeAISubscriber()`** — 是否为 Claude.ai 订阅者
- **`isMaxSubscriber()`** / **`isProSubscriber()`** / **`isTeamPremiumSubscriber()`** — 订阅级别检查
- **`getSubscriptionType()`** — 获取订阅类型

### cwd.ts — 工作目录管理

- **`getCwd()`** — 获取当前工作目录
- **`pwd()`** — 获取工作目录（AsyncLocalStorage 优先）
- **`runWithCwdOverride<T>(cwd, fn)`** — 在指定目录下运行函数（支持并发 agent 隔离）

### json.ts — JSON 解析

- **`safeParseJSON(json, shouldLogError?)`** — 安全 JSON 解析（LRU 缓存，50 条上限）
- **`safeParseJSONC(json)`** — 安全 JSONC 解析（支持注释）
- **`modifyJSONC(content, path, value)`** — 修改 JSONC（保留注释和格式）
- **`getJSONCPathValue(content, path)`** — 获取 JSONC 路径值

### path.ts — 路径处理

- **`expandPath(path, baseDir?)`** — 展开路径（支持 `~`、相对路径、POSIX→Windows 转换）
- **`containsPathTraversal(path)`** — 检查路径遍历攻击
- **`sanitizePath(path)`** — 清理路径
- **`getDirectoryForPath(path)`** — 获取路径所在目录

### envUtils.ts — 环境工具

- **`getClaudeConfigHomeDir()`** — 获取 Claude 配置目录（`~/.claude`，支持 `CLAUDE_CONFIG_DIR` 覆盖）
- **`isEnvTruthy(value)`** — 检查环境变量是否为真值（`1/true/yes/on`）
- **`isEnvDefinedFalsy(value)`** — 检查环境变量是否为已定义的假值
- **`isBareMode()`** — 是否为精简模式（`--bare` 或 `CLAUDE_CODE_SIMPLE`）
- **`hasNodeOption(flag)`** — 检查 NODE_OPTIONS 中是否包含标志
- **`parseEnvVars(rawEnvArgs)`** — 解析环境变量字符串数组

### teammate.ts — Teammate 工具

- **`getParentSessionId()`** — 获取父会话 ID
- **`setDynamicTeamContext(context)`** — 设置动态团队上下文
- **`clearDynamicTeamContext()`** — 清除动态团队上下文
- **`isTeammate()`** — 当前实例是否为 teammate
- **`isPlanModeRequired()`** — 是否要求 plan 模式
- **`getTeamName()`** / **`getAgentName()`** / **`getAgentId()`** — 获取团队信息

### sessionStart.ts — 会话启动钩子

- **`processSessionStartHooks(source, options?)`** — 处理会话启动钩子
  - source: `'startup' | 'resume' | 'clear' | 'compact'`
  - 返回值：`Promise<HookResultMessage[]>`
- **`takeInitialUserMessage()`** — 获取初始用户消息

### contextAnalysis.ts — 上下文分析

- **`analyzeContext(messages)`** — 分析消息列表的 token 统计
  - 返回值：`TokenStats` — 含 toolRequests, toolResults, humanMessages, attachments 等

### claudemd.ts — CLAUDE.md 文件加载

CLAUDE.md 记忆文件的发现和加载系统：

- **`loadClaudeMemoryFiles(options?)`** — 加载所有 CLAUDE.md 文件
  - 加载顺序：托管 → 用户 → 项目 → 本地
  - 支持 `@include` 指令
- **`getClaudeMdContent()`** — 获取缓存的 CLAUDE.md 内容

### imageStore.ts — 图片存储

- **`cacheImagePath(content)`** — 缓存图片路径（无 I/O）
- **`storeImage(content)`** — 存储图片到磁盘
- **`getStoredImagePath(id)`** — 获取已存储图片路径
- **`cleanupImageStore()`** — 清理图片存储

### QueryGuard.ts — 查询生命周期守卫

同步状态机，兼容 `useSyncExternalStore`：

- **`reserve()`** — 预留守卫（idle → dispatching）
- **`cancelReservation()`** — 取消预留（dispatching → idle）
- **`tryStart()`** — 开始查询（→ running），返回 generation 号
- **`end(generation)`** — 结束查询（→ idle），返回是否为当前代
- **`isActive`** — 是否活跃（dispatching 或 running）
- **`subscribe` / `getSnapshot`** — React 兼容接口

### Cursor.ts — 文本光标与编辑

文本编辑光标系统，支持 Unicode grapheme cluster 和多行操作：

#### Kill Ring（剪贴板环）
- **`pushToKillRing(text, direction?)`** — 压入 kill ring
- **`getLastKill()`** — 获取最近 kill
- **`yankPop()`** — 循环 kill ring

#### Cursor 类
- **`Cursor.fromText(text, columns, offset?, selection?)`** — 从文本创建光标
- 导航：`left()`, `right()`, `up()`, `down()`, `startOfLine()`, `endOfLine()`, `nextWord()`, `prevWord()`
- Vim 操作：`nextVimWord()`, `prevVimWord()`, `endOfVimWord()`, `nextWORD()`, `prevWORD()`, `findCharacter()`
- 逻辑行：`startOfLogicalLine()`, `endOfLogicalLine()`, `upLogicalLine()`, `downLogicalLine()`
- 编辑：`insert(str)`, `del()`, `backspace()`, `deleteWordBefore()`, `deleteWordAfter()`, `modifyText(end, insert?)`
- 视口：`getViewportStartLine(maxLines?)`, `render(cursorChar, mask, invert, ghostText?)`
- 查询：`isAtStart()`, `isAtEnd()`, `getPosition()`, `goToLine(n)`, `endOfFile()`

#### MeasuredText 类
- 文本测量与换行引擎，支持 Unicode grapheme、CJK 宽字符
- **`nextOffset(offset)` / `prevOffset(offset)`** — grapheme 级别偏移导航
- **`getWrappedText()` / `getWrappedLines()`** — 获取换行后文本
- **`getWordBoundaries()`** — 获取词边界（使用 Intl.Segmenter）
- **`snapToGraphemeBoundary(offset)`** — 对齐到 grapheme 边界

### 其他独立文件

| 文件 | 主要导出 | 功能简述 |
|------|----------|----------|
| `execFileNoThrow.ts` | `execFileNoThrow(file, args, options)` | 不抛异常的 execFile |
| `contextSuggestions.ts` | `getContextSuggestions(query)` | 获取上下文建议 |
| `conversationRecovery.ts` | `recoverConversation(...)` | 恢复会话 |
| `frontmatterParser.ts` | `parseFrontmatter(content)` | 解析 Markdown frontmatter |
| `generatedFiles.ts` | `isGeneratedFile(path)` | 判断是否为生成文件 |
| `heatmap.ts` | 热力图工具 | 代码变更热力图 |
| `intl.ts` | `getGraphemeSegmenter()`, `getWordSegmenter()` | 国际化分段器 |
| `memoize.ts` | `memoizeWithLRU(fn, keyFn, max)`, `memoizeWithTTLAsync(fn, ttl)` | 缓存工具 |
| `uuid.ts` | `uuid()` | UUID 生成 |
| `semanticNumber.ts` | `toOrdinal(n)` | 序数词转换 |
| `set.ts` | `isEqualSet(a, b)` | Set 工具 |
| `array.ts` | `uniq(arr)`, `count(iterable)` | 数组工具 |
| `shellConfig.ts` | `getShellConfig()` | Shell 配置 |
| `systemPromptType.ts` | 系统提示类型 | 提示类型定义 |
| `systemDirectories.ts` | `getSystemDirectories()` | 系统目录 |
| `textHighlighting.ts` | `highlightText(...)` | 文本高亮 |
| `windowsPaths.ts` | `posixPathToWindowsPath(p)`, `windowsPathToPosixPath(p)` | Windows 路径转换 |
| `tempfile.ts` | `createTempFile(prefix?)` | 临时文件创建 |
| `cliHighlight.ts` | CLI 高亮 | 终端语法高亮 |
| `queryContext.ts` | 查询上下文 | 查询上下文管理 |
| `sessionEnvironment.ts` | `getSessionEnvironment()` | 会话环境变量 |
| `bundledMode.ts` | `isBundledMode()` | 是否为捆绑模式 |
| `extraUsage.ts` | 额外用量工具 | 用量统计 |
| `exampleCommands.ts` | 示例命令 | 示例命令列表 |
| `diagLogs.ts` | `logForDiagnosticsNoPII(...)` | 无 PII 诊断日志 |
| `keyboardShortcuts.ts` | 键盘快捷键 | 快捷键定义 |
| `listSessionsImpl.ts` | `listSessions()` | 列出会话 |
| `getWorktreePathsPortable.ts` | `getWorktreePaths()` | 获取 worktree 路径 |
| `streamlinedTransform.ts` | 简化转换 | 流式处理转换 |
| `modelCost.ts` | `getModelCosts(model)` | 模型费用计算 |
| `ink.ts` | Ink 工具 | React 终端渲染辅助 |
| `jsonRead.ts` | `stripBOM(str)` | BOM 剥离 |
| `zodToJsonSchema.ts` | `zodToJsonSchema(schema)` | Zod → JSON Schema |
| `cronTasksLock.ts` | 定时任务锁 | cron 任务互斥 |
| `pdfUtils.ts` | PDF 工具 | PDF 处理 |

---

## 九、Hooks 系统 (utils/hooks/)

| 文件 | 主要功能 |
|------|----------|
| `sessionHooks.ts` | 会话钩子状态管理 |
| `hooksConfigManager.ts` | 钩子配置管理 |
| `hooksConfigSnapshot.ts` | 钩子配置快照 |
| `postSamplingHooks.ts` | 采样后钩子 |
| `execPromptHook.ts` | 执行提示钩子 |
| `execHttpHook.ts` | 执行 HTTP 钩子 |
| `execAgentHook.ts` | 执行代理钩子 |
| `hookHelpers.ts` | 钩子辅助函数 |
| `hookEvents.ts` | 钩子事件定义 |
| `apiQueryHookHelper.ts` | API 查询钩子辅助 |
| `AsyncHookRegistry.ts` | 异步钩子注册表 |
| `registerFrontmatterHooks.ts` | 注册 frontmatter 钩子 |
| `registerSkillHooks.ts` | 注册技能钩子 |
| `skillImprovement.ts` | 技能改进 |
| `ssrfGuard.ts` | SSRF 防护 |
| `fileChangedWatcher.ts` | 文件变更监听 |
| `hooksSettings.ts` | 钩子设置 |

---

## 十、Swarm 系统 (utils/swarm/)

| 文件 | 主要功能 |
|------|----------|
| `teamHelpers.ts` | 团队辅助函数 |
| `teammateInit.ts` | Teammate 初始化 |
| `teammateModel.ts` | Teammate 模型选择 |
| `teammateLayoutManager.ts` | Teammate 布局管理 |
| `teammatePromptAddendum.ts` | Teammate 提示补充 |
| `inProcessRunner.ts` | 进程内运行器 |
| `spawnInProcess.ts` | 进程内生成 |
| `spawnUtils.ts` | 生成工具 |
| `permissionSync.ts` | 权限同步 |
| `leaderPermissionBridge.ts` | Leader 权限桥接 |
| `reconnection.ts` | 重连机制 |
| `constants.ts` | 常量定义 |
| `backends/` | 后端实现（Tmux, ITerm, InProcess） |

---

## 十一、Deep Link 系统 (utils/deepLink/)

| 文件 | 主要功能 |
|------|----------|
| `parseDeepLink.ts` | 解析 deep link URL |
| `protocolHandler.ts` | 协议处理器 |
| `registerProtocol.ts` | 注册协议 |
| `terminalLauncher.ts` | 终端启动器 |
| `terminalPreference.ts` | 终端偏好 |
| `banner.ts` | 横幅显示 |

---

## 十二、消息处理 (utils/messages/)

| 文件 | 主要功能 |
|------|----------|
| `systemInit.ts` | 系统初始化消息构建 |
| `mappers.ts` | 消息映射器 |

---

## 十三、用户输入处理 (utils/processUserInput/)

| 文件 | 主要功能 |
|------|----------|
| `processUserInput.ts` | 处理用户输入（at-mention 展开、命令解析等） |
| `processTextPrompt.ts` | 处理文本提示 |
