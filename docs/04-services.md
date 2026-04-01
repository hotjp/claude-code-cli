# 服务层 (services/)

服务层是 Claude Code CLI 的核心业务逻辑模块，负责 API 通信、MCP 协议管理、分析埋点、语言服务、插件、语音输入、设置同步、团队记忆、自动记忆合并、提示建议、会话记忆、文档自动更新和提示系统等功能。

---

## services/api — API 通信层

与 Anthropic API 的所有通信，包括客户端创建、请求重试、错误处理、用量追踪、会话持久化和文件上传下载。

### client.ts — API 客户端工厂

| 导出 | 类型 | 说明 |
|------|------|------|
| `getAnthropicClient(params)` | `async function` | 创建并返回 Anthropic SDK 客户端实例。支持直接 API Key、AWS Bedrock、Azure Foundry、Google Vertex AI 等多种认证方式 |

**`getAnthropicClient` 参数：**
- `apiKey?: string` — 可选 API 密钥覆盖
- `maxRetries: number` — 最大重试次数
- `model?: string` — 目标模型名称（用于选择正确的后端/区域）
- `fetchOverride?: ClientOptions['fetch']` — 自定义 fetch 实现
- `source?: string` — 调用来源标识

**环境变量支持：**
- `ANTHROPIC_API_KEY` — 直接 API 访问密钥
- `AWS_REGION` / `AWS_DEFAULT_REGION` — AWS Bedrock 区域
- `ANTHROPIC_FOUNDRY_RESOURCE` — Azure Foundry 资源名
- `CLOUD_ML_REGION` / `ANTHROPIC_VERTEX_PROJECT_ID` — Vertex AI 配置
- `API_TIMEOUT_MS` — 请求超时（默认 600 秒）

### claude.ts — 核心查询引擎

| 导出 | 类型 | 说明 |
|------|------|------|
| `queryModel(params)` | `async function` | 流式查询模型，返回消息流事件。核心 API 调用入口 |
| `queryModelWithoutStreaming(params)` | `async function` | 非流式查询，等待完整响应后返回 |
| `queryHaiku(params)` | `async function` | 使用 Haiku 小模型的快捷查询（用于摘要、分类等轻量任务） |
| `getMaxOutputTokensForModel(model)` | `function` | 获取指定模型的最大输出 token 数 |
| `getAPIMetadata()` | `function` | 获取当前 API 请求元数据（请求 ID、模型等） |
| `getExtraBodyParams()` | `function` | 获取额外请求体参数（Bedrock 兼容） |

**`queryModel` 核心参数：**
- `messages: MessageParam[]` — 消息历史
- `systemPrompt: SystemPrompt` — 系统提示词
- `tools: Tool[]` — 可用工具列表
- `thinkingConfig: ThinkingConfig` — 思考模式配置
- `options.model` — 模型名称
- `options.querySource` — 查询来源标识（用于分析和限流）
- `options.toolChoice` — 工具选择策略
- `options.abortSignal` — 取消信号

### errors.ts — API 错误处理

| 导出 | 类型 | 说明 |
|------|------|------|
| `getAssistantMessageFromError(params)` | `async function` | 将 SDK/API 错误转换为 `AssistantMessage` 错误消息 |
| `classifyAPIError(error)` | `function` | 将 API 错误分类为 `transient`（可重试）或 `fatal`（不可重试） |
| `isPromptTooLongMessage(msg)` | `function` | 判断消息是否为 prompt 过长错误 |
| `isMediaSizeError(raw)` | `function` | 判断是否为媒体文件大小超限错误 |
| `parsePromptTooLongTokenCounts(raw)` | `function` | 从错误消息中解析实际/限制 token 数量 |
| `getPromptTooLongTokenGap(msg)` | `function` | 返回超出限制的 token 数量 |
| `startsWithApiErrorPrefix(text)` | `function` | 检查文本是否以 API 错误前缀开头 |
| `REPEATED_529_ERROR_MESSAGE` | `const string` | 连续 529 过载错误的提示消息 |

### withRetry.ts — 请求重试引擎

| 导出 | 类型 | 说明 |
|------|------|------|
| `withRetry(fn, options)` | `async function` | 带指数退避的请求重试包装器，处理 529/429/连接错误等 |
| `CannotRetryError` | `class` | 无法继续重试时抛出的错误，携带原始错误和重试上下文 |
| `getRetryDelay(attempt)` | `function` | 计算指定重试次数的退避延迟时间 |
| `BASE_DELAY_MS` | `const` | 基础退避延迟（500ms） |

**`withRetry` 选项：**
- `maxRetries?: number` — 最大重试次数（默认 10）
- `model: string` — 当前模型
- `fallbackModel?: string` — 降级模型（用于 prompt 过长时切换）
- `thinkingConfig: ThinkingConfig` — 思考配置
- `querySource?: QuerySource` — 查询来源（决定 529 是否重试）
- `signal?: AbortSignal` — 取消信号

### usage.ts — 用量查询

| 导出 | 类型 | 说明 |
|------|------|------|
| `fetchUtilization()` | `async function` | 获取当前用户的 API 用量统计。返回 `Utilization` 对象 |
| `RateLimit` | `type` | 速率限制状态：`{ utilization: number \| null, resets_at: string \| null }` |
| `ExtraUsage` | `type` | 额外用量：`{ is_enabled, monthly_limit, used_credits, utilization }` |
| `Utilization` | `type` | 聚合用量数据：5 小时 / 7 天 / Opus / Sonnet 各窗口的利用率 |

### bootstrap.ts — 启动引导数据

| 导出 | 类型 | 说明 |
|------|------|------|
| `fetchBootstrapData()` | `async function` | 从 API 获取启动引导数据（客户端数据、额外模型选项）并持久化到磁盘缓存 |

### sessionIngress.ts — 会话日志持久化

| 导出 | 类型 | 说明 |
|------|------|------|
| `appendSessionLog(sessionId, entry)` | `async function` | 将会话日志条目追加到远程服务。支持重试、冲突解决（409）、UUID 链式追踪 |
| `fetchSessionLogs(sessionId)` | `async function` | 获取指定会话的所有日志条目 |

### filesApi.ts — 文件上传下载

| 导出 | 类型 | 说明 |
|------|------|------|
| `downloadFiles(files, config)` | `async function` | 批量从 Anthropic Files API 下载文件到本地 |
| `downloadFile(fileId, config)` | `async function` | 下载单个文件 |
| `uploadFile(filePath, config)` | `async function` | 上传文件到 Files API |
| `File` | `type` | 文件规格：`{ fileId: string, relativePath: string }` |
| `FilesApiConfig` | `type` | API 配置：`{ oauthToken, baseUrl?, sessionId }` |
| `DownloadResult` | `type` | 下载结果：`{ fileId, path, success, error?, bytesWritten? }` |

### logging.ts — API 日志记录

| 导出 | 类型 | 说明 |
|------|------|------|
| `logAPICompletion(params)` | `function` | 记录 API 完成事件，包含 token 用量、延迟、缓存命中率等 |
| `logAPIError(params)` | `function` | 记录 API 错误事件 |
| `EMPTY_USAGE` | `const` | 空用量对象 |
| `GlobalCacheStrategy` | `type` | 全局缓存策略：`'tool_based' \| 'system_prompt' \| 'none'` |

### grove.ts — Grove 通知设置

| 导出 | 类型 | 说明 |
|------|------|------|
| `getGroveSettings()` | `async function` | 获取用户的 Grove 通知设置（会话级缓存） |
| `updateGroveSettings(groveEnabled)` | `async function` | 更新 Grove 启用状态 |
| `markGroveNoticeViewed()` | `async function` | 标记 Grove 通知已查看 |
| `GroveConfig` | `type` | Grove 配置：`{ grove_enabled, domain_excluded, notice_is_grace_period, ... }` |
| `ApiResult<T>` | `type` | API 调用结果：`{ success: true, data: T } \| { success: false }` |

### 其他 API 子模块

| 文件 | 说明 |
|------|------|
| `errorUtils.ts` | 错误工具函数：提取连接错误详情、格式化 API 错误 |
| `metricsOptOut.ts` | 指标选择退出处理 |
| `overageCreditGrant.ts` | 超额信用额度查询 |
| `ultrareviewQuota.ts` | UltraReview 配额管理 |
| `referral.ts` | 推荐奖励查询 |
| `promptCacheBreakDetection.ts` | Prompt 缓存失效检测 |
| `dumpPrompts.ts` | Prompt 转储工具（调试用） |
| `firstTokenDate.ts` | 首 token 日期追踪 |
| `adminRequests.ts` | 管理员请求处理 |
| `emptyUsage.ts` | 空用量常量 |

---

## services/mcp — Model Context Protocol

MCP（模型上下文协议）服务层，负责 MCP 服务器的配置管理、客户端连接、工具发现、OAuth 认证和生命周期管理。

### types.ts — 类型定义

| 导出 | 类型 | 说明 |
|------|------|------|
| `ConfigScope` | `type` | 配置来源范围：`'local' \| 'user' \| 'project' \| 'dynamic' \| 'enterprise' \| 'claudeai' \| 'managed'` |
| `Transport` | `type` | 传输协议：`'stdio' \| 'sse' \| 'sse-ide' \| 'http' \| 'ws' \| 'sdk'` |
| `McpStdioServerConfig` | `type` | Stdio 服务器配置：`{ type?, command, args?, env? }` |
| `McpSSEServerConfig` | `type` | SSE 服务器配置：`{ type: 'sse', url, headers?, oauth? }` |
| `McpHTTPServerConfig` | `type` | HTTP Streamable 服务器配置 |
| `McpWebSocketServerConfig` | `type` | WebSocket 服务器配置 |
| `McpSdkServerConfig` | `type` | SDK 内置服务器配置 |
| `McpServerConfig` | `union type` | 所有服务器配置类型的联合类型 |
| `MCPServerConnection` | `type` | 已连接的 MCP 服务器实例（含客户端、工具列表、状态等） |
| `ConnectedMCPServer` | `type` | 已连接服务器的摘要信息 |
| `ServerResource` | `type` | 服务器资源：`{ server, uri, name, description? }` |
| `ScopedMcpServerConfig` | `type` | 带配置范围的服务器配置 |

### client.ts — MCP 客户端核心

| 导出 | 类型 | 说明 |
|------|------|------|
| `getMcpToolsCommandsAndResources()` | `async function` | 获取所有已连接 MCP 服务器的工具、命令和资源 |
| `fetchToolsForClient(client, name)` | `async function` | 从单个 MCP 客户端获取工具列表 |
| `fetchCommandsForClient(client, name)` | `async function` | 从单个 MCP 客户端获取命令（prompt）列表 |
| `fetchResourcesForClient(client, name)` | `async function` | 从单个 MCP 客户端获取资源列表 |
| `reconnectMcpServerImpl(name)` | `async function` | 重新连接指定 MCP 服务器 |
| `callIdeRpc(client, method, params)` | `async function` | 调用 IDE 集成的 RPC 方法 |
| `clearServerCache(name)` | `function` | 清除指定服务器的工具/命令缓存 |
| `McpAuthError` | `class` | MCP 认证错误（401 时抛出） |

**客户端创建支持的传输方式：**
- `StdioClientTransport` — 通过标准输入输出通信
- `SSEClientTransport` — Server-Sent Events 长连接
- `StreamableHTTPClientTransport` — HTTP 流式传输
- `WebSocketTransport` — WebSocket 连接
- `SdkControlClientTransport` — SDK 控制协议

### config.ts — MCP 配置管理

| 导出 | 类型 | 说明 |
|------|------|------|
| `getAllMcpConfigs()` | `async function` | 获取所有来源的 MCP 配置（本地、用户、项目、企业、Claude.ai、插件） |
| `getMcpConfigByName(name)` | `async function` | 按名称获取特定 MCP 服务器配置 |
| `addMcpServer(name, config, scope)` | `async function` | 添加 MCP 服务器到指定配置范围 |
| `removeMcpServer(name, scope)` | `async function` | 从指定范围移除 MCP 服务器 |
| `setMcpServerEnabled(name, enabled)` | `async function` | 启用/禁用 MCP 服务器 |
| `isMcpServerDisabled(name)` | `function` | 检查服务器是否被禁用 |
| `resetMcpServer(name)` | `async function` | 重置 MCP 服务器配置 |
| `getEnterpriseMcpFilePath()` | `function` | 获取企业级 MCP 配置文件路径 |
| `filterMcpServersByPolicy(servers)` | `function` | 按策略过滤 MCP 服务器 |
| `dedupClaudeAiMcpServers(servers)` | `function` | 去重 Claude.ai 来源的 MCP 服务器 |
| `doesEnterpriseMcpConfigExist()` | `function` | 检查企业级 MCP 配置是否存在 |

### auth.ts — MCP OAuth 认证

| 导出 | 类型 | 说明 |
|------|------|------|
| `ClaudeAuthProvider` | `class` | MCP OAuth 认证提供者，实现 `OAuthClientProvider` 接口 |
| `hasMcpDiscoveryButNoToken(config)` | `function` | 检查服务器是否配置了 OAuth 发现但尚未完成认证 |
| `wrapFetchWithStepUpDetection(fetchFn)` | `function` | 包装 fetch 以检测 Step-Up 认证需求 |

**OAuth 流程支持：**
- 自动发现授权服务器元数据
- PKCE（Proof Key for Code Exchange）流程
- 客户端注册（动态客户端注册 DCR）
- Token 刷新与缓存（使用系统安全存储）
- 非标准错误码规范化（如 Slack 的 `invalid_refresh_token`）

### utils.ts — MCP 工具函数

| 导出 | 类型 | 说明 |
|------|------|------|
| `filterToolsByServer(tools, serverName)` | `function` | 按服务器名称筛选工具 |
| `filterCommandsByServer(commands, serverName)` | `function` | 按服务器名称筛选命令 |
| `filterResourcesByServer(resources, serverName)` | `function` | 按服务器名称筛选资源 |
| `excludeToolsByServer(tools, serverName)` | `function` | 排除指定服务器的工具 |
| `excludeCommandsByServer(commands, serverName)` | `function` | 排除指定服务器的命令 |
| `excludeResourcesByServer(resources, serverName)` | `function` | 排除指定服务器的资源 |
| `commandBelongsToServer(command, serverName)` | `function` | 判断命令是否属于指定服务器 |
| `getProjectMcpServerStatus()` | `function` | 获取项目级 MCP 服务器状态 |
| `getLoggingSafeMcpBaseUrl(config)` | `function` | 获取日志安全的 MCP URL（脱敏） |

### normalization.ts — 名称规范化

| 导出 | 类型 | 说明 |
|------|------|------|
| `normalizeNameForMCP(name)` | `function` | 将服务器名称规范化为 MCP 兼容格式（`^[a-zA-Z0-9_-]{1,64}$`）。Claude.ai 来源的名称还会压缩连续下划线并去除首尾下划线 |

### elicitationHandler.ts — 弹窗交互处理

| 导出 | 类型 | 说明 |
|------|------|------|
| `registerElicitationHandler(client, serverName, setAppState)` | `function` | 注册 MCP 弹窗请求处理器（支持表单和 URL 两种模式） |
| `runElicitationHooks(params)` | `async function` | 运行弹窗前置钩子 |
| `runElicitationResultHooks(params)` | `async function` | 运行弹窗结果后置钩子 |
| `ElicitationRequestEvent` | `type` | 弹窗请求事件：`{ serverName, requestId, params, signal, respond, waitingState? }` |
| `ElicitationWaitingState` | `type` | 等待状态配置：`{ actionLabel, showCancel? }` |

### claudeai.ts — Claude.ai MCP 服务器

| 导出 | 类型 | 说明 |
|------|------|------|
| `fetchClaudeAIMcpConfigsIfEligible()` | `async function` | 从 Claude.ai 获取组织管理的 MCP 服务器配置（会话级缓存） |
| `markClaudeAiMcpConnected()` | `function` | 标记 Claude.ai MCP 已连接 |
| `clearClaudeAIMcpConfigsCache()` | `function` | 清除 Claude.ai MCP 配置缓存 |

### officialRegistry.ts — 官方注册表

| 导出 | 类型 | 说明 |
|------|------|------|
| `prefetchOfficialMcpUrls()` | `async function` | 预获取官方 MCP 注册表 URL 列表 |
| `isOfficialMcpUrl(normalizedUrl)` | `function` | 判断 URL 是否属于官方 MCP 注册表 |

### useManageMCPConnections.ts — React 连接管理 Hook

| 导出 | 类型 | 说明 |
|------|------|------|
| `useManageMCPConnections(props)` | `React Hook` | 管理 MCP 连接生命周期的 React Hook。处理自动连接、重连（指数退避，最多 5 次）、工具/命令/资源发现、列表变更通知、错误处理 |

**连接管理功能：**
- 基于 `AppState` 的服务器状态追踪
- 指数退避重连（初始 1s，最大 30s，最多 5 次）
- 工具/命令/资源列表变更通知处理
- 插件错误去重和报告
- Channel 权限管理

### 其他 MCP 子模块

| 文件 | 说明 |
|------|------|
| `envExpansion.ts` | 环境变量展开（在 MCP 配置值中替换 `$VAR` 占位符） |
| `mcpStringUtils.ts` | MCP 字符串工具（构建工具名、解析服务器名） |
| `headersHelper.ts` | MCP 请求头构建 |
| `SdkControlTransport.ts` | SDK 控制协议传输层 |
| `InProcessTransport.ts` | 进程内传输层 |
| `channelAllowlist.ts` | Channel 白名单管理 |
| `channelNotification.ts` | Channel 消息通知处理 |
| `channelPermissions.ts` | Channel 权限回调管理 |
| `xaa.ts` | 跨应用访问（XAA）Token 交换 |
| `xaaIdpLogin.ts` | XAA IdP 登录和 OIDC 发现 |
| `oauthPort.ts` | OAuth 回调端口管理 |
| `vscodeSdkMcp.ts` | VSCode SDK MCP 集成 |

---

## services/analytics — 分析埋点

事件分析系统，支持 Datadog 和第一方事件日志双通道输出。

### index.ts — 分析公共 API

| 导出 | 类型 | 说明 |
|------|------|------|
| `logEvent(eventName, metadata)` | `function` | 同步记录分析事件。Sink 未附加时自动入队 |
| `logEventAsync(eventName, metadata)` | `async function` | 异步记录分析事件 |
| `attachAnalyticsSink(sink)` | `function` | 附加分析后端（幂等，启动时调用一次） |
| `AnalyticsSink` | `type` | 分析后端接口：`{ logEvent, logEventAsync }` |
| `AnalyticsMetadata_I_VERIFIED_THIS_IS_NOT_CODE_OR_FILEPATHS` | `type` | 标记类型，强制验证元数据不包含敏感信息 |
| `AnalyticsMetadata_I_VERIFIED_THIS_IS_PII_TAGGED` | `type` | 标记类型，用于 PII 标记的 proto 列 |
| `stripProtoFields(metadata)` | `function` | 从元数据中移除 `_PROTO_*` 前缀的 PII 字段 |

### sink.ts — 分析后端路由

| 导出 | 类型 | 说明 |
|------|------|------|
| `initializeAnalyticsSink()` | `function` | 初始化分析 Sink（启动时调用，幂等） |
| `initializeAnalyticsGates()` | `function` | 从服务端更新分析开关状态 |

**事件路由逻辑：**
- 事件采样（基于 `tengu_event_sampling_config` 动态配置）
- Datadog 通道（需 `tengu_log_datadog_events` 功能开关启用，自动剥离 PII 字段）
- 第一方事件日志通道（保留完整元数据）

### 其他分析子模块

| 文件 | 说明 |
|------|------|
| `datadog.ts` | Datadog 事件追踪 |
| `firstPartyEventLogger.ts` | 第一方事件日志（支持采样） |
| `firstPartyEventLoggingExporter.ts` | 第一方事件导出器 |
| `growthbook.ts` | GrowthBook 功能开关和动态配置（缓存机制，非阻塞） |
| `metadata.ts` | 分析元数据工具（工具名脱敏、文件扩展名提取） |
| `config.ts` | 分析配置 |
| `sinkKillswitch.ts` | Sink 紧急关闭开关 |

---

## services/lsp — 语言服务协议

LSP 客户端实现，为 Claude Code 提供 IDE 级别的代码智能（诊断、跳转定义、hover 等）。

### manager.ts — LSP 管理器单例

| 导出 | 类型 | 说明 |
|------|------|------|
| `initializeLspServerManager()` | `function` | 初始化 LSP 管理器单例（启动时调用，幂等） |
| `getLspServerManager()` | `function` | 获取 LSP 管理器实例（可能为 `undefined`） |
| `getInitializationStatus()` | `function` | 获取初始化状态：`'not-started' \| 'pending' \| 'success' \| 'failed'` |
| `isLspConnected()` | `function` | 检查是否至少有一个语言服务器已连接 |
| `waitForInitialization()` | `async function` | 等待初始化完成 |
| `shutdownLspServerManager()` | `async function` | 关闭所有 LSP 服务器 |
| `reinitializeLspServerManager()` | `async function` | 重新初始化 LSP 管理器 |

### LSPServerManager.ts — LSP 服务器管理器

| 导出 | 类型 | 说明 |
|------|------|------|
| `LSPServerManager` | `interface` | 服务器管理器接口 |
| `createLSPServerManager()` | `function` | 创建 LSP 服务器管理器实例 |

**`LSPServerManager` 方法：**
- `initialize()` — 加载所有配置的 LSP 服务器
- `shutdown()` — 关闭所有运行中的服务器
- `getServerForFile(filePath)` — 获取文件对应的 LSP 服务器实例
- `ensureServerStarted(filePath)` — 确保文件的 LSP 服务器已启动
- `sendRequest<T>(filePath, method, params)` — 发送 LSP 请求
- `openFile(filePath, content)` — 同步文件打开（`textDocument/didOpen`）
- `changeFile(filePath, content)` — 同步文件变更（`textDocument/didChange`）
- `saveFile(filePath)` — 同步文件保存（`textDocument/didSave`）
- `closeFile(filePath)` — 同步文件关闭（`textDocument/didClose`）
- `getAllServers()` — 获取所有服务器实例
- `isFileOpen(filePath)` — 检查文件是否已打开

### LSPClient.ts — LSP 客户端

| 导出 | 类型 | 说明 |
|------|------|------|
| `LSPClient` | `interface` | LSP 客户端接口 |
| `createLSPClient(serverName, onCrash?)` | `function` | 创建基于 vscode-jsonrpc 的 LSP 客户端。通过 stdio 管理与 LSP 服务器的通信 |

**`LSPClient` 接口方法：**
- `start(command, args, options?)` — 启动 LSP 服务器进程
- `initialize(params)` — 发送 LSP 初始化请求
- `sendRequest<TResult>(method, params)` — 发送通用请求
- `sendNotification(method, params)` — 发送通知
- `onNotification(method, handler)` — 注册通知处理器
- `onRequest<TParams, TResult>(method, handler)` — 注册请求处理器
- `stop()` — 停止服务器

### 其他 LSP 子模块

| 文件 | 说明 |
|------|------|
| `LSPServerInstance.ts` | 单个 LSP 服务器实例封装（生命周期管理、自动重启） |
| `config.ts` | LSP 服务器配置加载 |
| `passiveFeedback.ts` | 被动反馈（将 LSP 诊断注入对话上下文） |
| `LSPDiagnosticRegistry.ts` | LSP 诊断信息注册表 |

---

## services/plugins — 插件系统

### PluginInstallationManager.ts — 插件安装管理器

| 导出 | 类型 | 说明 |
|------|------|------|
| `performBackgroundPluginInstallations(setAppState)` | `async function` | 后台安装插件和 marketplace。新安装后自动刷新插件缓存；仅更新时通知用户运行 `/reload-plugins` |

### pluginOperations.ts — 插件操作

| 导出 | 说明 |
|------|------|
| 插件安装、卸载、更新等操作函数 | |

### pluginCliCommands.ts — 插件 CLI 命令

| 导出 | 说明 |
|------|------|
| `/install-plugin`、`/uninstall-plugin` 等 CLI 命令注册 | |

---

## services/voice — 语音录制

| 导出 | 类型 | 说明 |
|------|------|------|
| `startRecording()` | `async function` | 开始音频录制 |
| `stopRecording()` | `async function` | 停止录制并返回 WAV 音频 Buffer |
| `checkRecordingAvailability()` | `async function` | 检查录音功能是否可用（检测音频设备和依赖） |
| `getInstallInstructions()` | `function` | 获取音频依赖的安装说明（平台特定） |
| `getPackageManagerInfo()` | `function` | 获取当前平台的包管理器信息 |

**音频录制支持（按优先级）：**
1. 原生音频捕获（`audio-capture-napi`）— macOS/Linux/Windows
2. SoX `rec` 命令
3. `arecord`（ALSA，Linux）

**录制参数：**
- 采样率：16000 Hz
- 声道：单声道
- 静默检测：2 秒静默后自动停止

---

## services/voiceStreamSTT — 语音流式识别

| 导出 | 类型 | 说明 |
|------|------|------|
| `connectVoiceStream(callbacks, options?)` | `async function` | 连接 Anthropic voice_stream WebSocket 端点进行实时语音转文字 |
| `isVoiceStreamAvailable()` | `function` | 检查 voice_stream 是否可用（需要有效的 OAuth token） |
| `VoiceStreamConnection` | `type` | 连接对象：`{ send(audioChunk), finalize(), close(), isConnected() }` |
| `VoiceStreamCallbacks` | `type` | 回调：`{ onTranscript, onError, onClose, onReady }` |
| `FinalizeSource` | `type` | 结束方式：`'post_closestream_endpoint' \| 'no_data_timeout' \| 'safety_timeout' \| 'ws_close' \| 'ws_already_closed'` |

**WebSocket 协议：**
- 发送：二进制音频帧（linear16, 16kHz, 单声道）
- 接收：`TranscriptText`（文本片段）、`TranscriptEndpoint`（语音端点检测）
- 控制消息：`KeepAlive`（8 秒间隔）、`CloseStream`

---

## services/voiceKeyterms — 语音关键词

| 导出 | 类型 | 说明 |
|------|------|------|
| `getVoiceKeyterms(recentFiles?)` | `async function` | 构建 STT 关键词列表，包含全局编程术语 + 项目上下文（项目名、Git 分支、最近文件名） |
| `splitIdentifier(name)` | `function` | 将标识符拆分为单词（支持 camelCase、PascalCase、kebab-case、snake_case） |

---

## services/settingsSync — 设置同步

| 导出 | 类型 | 说明 |
|------|------|------|
| `uploadUserSettingsInBackground()` | `async function` | 后台上传本地设置到远程（增量同步，仅上传变更项）。交互式 CLI 专用 |
| `downloadUserSettings()` | `async function` | 从远程下载设置到本地（CCR 模式）。首次调用启动下载，后续调用共享同一个 Promise |
| `forceFreshDownload()` | `async function` | 强制重新下载设置（跳过启动缓存，用于 `/reload-plugins`） |

**同步语义：**
- 上传：增量对比，只上传变更的条目
- 下载：覆盖本地文件（服务端优先）
- 最大文件大小：500KB/文件

---

## services/teamMemorySync — 团队记忆同步

| 导出 | 类型 | 说明 |
|------|------|------|
| `pullTeamMemory(state)` | `async function` | 从服务器拉取团队记忆文件到本地（服务端优先） |
| `pushTeamMemory(state)` | `async function` | 将本地团队记忆推送到服务器（增量上传，仅上传内容哈希不同的条目） |
| `createSyncState()` | `function` | 创建同步状态对象 |
| `hashContent(content)` | `function` | 计算 `sha256:<hex>` 内容哈希 |

**`SyncState` 状态对象：**
- `lastKnownChecksum: string | null` — 服务端 ETag
- `serverChecksums: Map<string, string>` — 每个条目的服务端内容哈希
- `serverMaxEntries: number | null` — 服务端条目数上限（从 413 响应中学习）

**同步特性：**
- 按 Git 远程哈希限定仓库范围
- 增量上传（仅上传哈希不同的条目）
- 大 body 自动分批（200KB/批）
- 密钥扫描（推送前检测并跳过含密钥的文件）
- 条目大小上限：250KB/条目

---

## services/autoDream — 自动记忆合并

| 导出 | 类型 | 说明 |
|------|------|------|
| `initAutoDream()` | `function` | 初始化自动合并（启动时调用） |

**触发条件（全部满足才执行）：**
1. 时间门：距上次合并 ≥ `minHours` 小时（默认 24h）
2. 会话门：新会话数 ≥ `minSessions`（默认 5 个）
3. 锁门：无其他进程正在合并

**执行流程：**
1. 扫描符合条件的会话
2. 构建合并 prompt
3. 以 forked agent 形式执行 `/dream` 命令
4. 结果写入自动记忆目录

### 子模块

| 文件 | 说明 |
|------|------|
| `config.ts` | 功能开关和配置（`isAutoDreamEnabled()`） |
| `consolidationLock.ts` | 合并锁管理（防止并发合并） |
| `consolidationPrompt.ts` | 合并 prompt 构建 |

---

## services/PromptSuggestion — 提示建议

| 导出 | 类型 | 说明 |
|------|------|------|
| `shouldEnablePromptSuggestion()` | `function` | 判断是否应启用提示建议（综合环境变量、功能开关、用户设置、交互模式等） |
| `tryGenerateSuggestion(params)` | `async function` | 尝试生成下一条提示建议。返回 `{ suggestion, promptId, generationRequestId }` 或 `null` |
| `abortPromptSuggestion()` | `function` | 中止当前进行中的建议生成 |
| `getSuggestionSuppressReason(appState)` | `function` | 返回建议生成应被抑制的原因，或 `null`（允许生成） |
| `PromptVariant` | `type` | 提示变体：`'user_intent' \| 'stated_intent'` |

**抑制条件：** 功能禁用、权限等待中、弹窗活跃、计划模式、速率限制

### speculation.ts — 推测性生成

在模型流式响应期间提前生成下一条建议，减少用户等待时间。

---

## services/SessionMemory — 会话记忆

| 导出 | 类型 | 说明 |
|------|------|------|
| `shouldExtractMemory(messages)` | `function` | 判断是否应提取会话记忆（基于 token 阈值和工具调用次数） |
| `initSessionMemory()` | `function` | 初始化会话记忆（注册后采样钩子） |
| `resetLastMemoryMessageUuid()` | `function` | 重置上次记忆消息 UUID（测试用） |

**触发阈值：**
- 初始化阈值：上下文窗口 token 数达到一定比例
- 更新阈值：token 增长量 + 工具调用次数

### 子模块

| 文件 | 说明 |
|------|------|
| `sessionMemoryUtils.ts` | 会话记忆配置、阈值计算、状态管理 |
| `prompts.ts` | 记忆提取和更新 prompt 构建 |

---

## services/MagicDocs — 文档自动更新

| 导出 | 类型 | 说明 |
|------|------|------|
| `detectMagicDocHeader(content)` | `function` | 检测文件是否包含 Magic Doc 头部（`# MAGIC DOC: [title]`）。返回 `{ title, instructions? }` 或 `null` |
| `registerMagicDoc(filePath)` | `function` | 将文件注册为 Magic Doc（读取时自动调用） |
| `clearTrackedMagicDocs()` | `function` | 清除所有已追踪的 Magic Doc |

**Magic Doc 格式：**
```markdown
# MAGIC DOC: 文档标题
*可选的自定义更新指令*

文档内容...
```

**工作原理：**
1. 当 `FileReadTool` 读取文件时检测 Magic Doc 头部
2. 注册为受追踪文档
3. 后台通过 forked agent 定期更新文档内容

---

## services/tips — 提示系统

### tipRegistry.ts — 提示注册表

| 导出 | 类型 | 说明 |
|------|------|------|
| `getRelevantTips(context?)` | `async function` | 获取当前上下文相关的提示列表 |
| `TIP_REGISTRY` | `Tip[]` | 所有已注册提示的数组 |

**`Tip` 接口：**
- `id: string` — 提示唯一标识
- `content: async () => string` — 提示内容生成函数
- `cooldownSessions: number` — 冷却会话数（显示后多少次会话内不再显示）
- `isRelevant: async (context?) => boolean` — 相关性判断

**提示示例：** `new-user-warmup`、`plan-mode-for-complex-tasks`、`git-worktrees`、`default-permission-mode-config` 等

### tipScheduler.ts — 提示调度

| 导出 | 类型 | 说明 |
|------|------|------|
| `getTipToShowOnSpinner(context?)` | `async function` | 获取在加载动画期间显示的提示（选择最久未展示的提示） |
| `selectTipWithLongestTimeSinceShown(tips)` | `function` | 从候选提示中选择距离上次展示最久的 |
| `recordShownTip(tip)` | `function` | 记录提示已展示（更新历史 + 发送分析事件） |

### tipHistory.ts — 提示历史

| 导出 | 说明 |
|------|------|
| `getSessionsSinceLastShown(tipId)` | 获取距离上次展示以来的会话数 |
| `recordTipShown(tipId)` | 记录提示已展示 |

---

## services/oauth — OAuth 认证

### index.ts — OAuth 服务

| 导出 | 类型 | 说明 |
|------|------|------|
| `OAuthService` | `class` | OAuth 2.0 授权码流程（含 PKCE） |

**`OAuthService` 方法：**
- `startOAuthFlow(authURLHandler, options?)` — 启动 OAuth 流程
  - `options.loginWithClaudeAi` — 使用 Claude.ai 登录
  - `options.inferenceOnly` — 仅推理权限
  - `options.orgUUID` — 组织 UUID
  - `options.skipBrowserOpen` — 跳过浏览器打开（SDK 模式）
- `startManualAuthFlow(authURLHandler)` — 手动复制授权码模式
- `refreshTokens(tokens)` — 刷新 OAuth token

---

## services/claudeAiLimits — 速率限制管理

| 导出 | 类型 | 说明 |
|------|------|------|
| `currentLimits` | `ClaudeAILimits` | 当前速率限制状态（全局可变） |
| `getRateLimitDisplayName(type)` | `function` | 获取限制类型的显示名称 |
| `getRateLimitErrorMessage(params)` | `function` | 生成速率限制错误消息 |
| `getRateLimitWarning(params)` | `function` | 生成速率限制警告 |
| `getUsingOverageText()` | `function` | 获取超额使用提示文本 |
| `extractQuotaStatusFromHeaders(headers)` | `function` | 从响应头提取配额状态 |
| `extractQuotaStatusFromError(error)` | `function` | 从错误响应提取配额状态 |
| `getRawUtilization()` | `function` | 获取原始利用率数据 |

**`ClaudeAILimits` 类型：**
- `status: 'allowed' | 'allowed_warning' | 'rejected'` — 配额状态
- `unifiedRateLimitFallbackAvailable: boolean` — 是否有降级模型可用
- `rateLimitType` — 限制类型：`five_hour | seven_day | seven_day_opus | seven_day_sonnet | overage`
- `utilization` — 利用率
- `overageStatus` — 超额状态
- `isUsingOverage` — 是否正在使用超额额度

---

## services/compact — 对话压缩

### autoCompact.ts — 自动压缩

| 导出 | 类型 | 说明 |
|------|------|------|
| `isAutoCompactEnabled()` | `function` | 检查自动压缩是否启用 |
| `getAutoCompactThreshold(model)` | `function` | 获取自动压缩触发阈值（token 数） |
| `getEffectiveContextWindowSize(model)` | `function` | 获取有效上下文窗口大小 |
| `calculateTokenWarningState(usage, model)` | `function` | 计算 token 使用警告状态 |
| `AutoCompactTrackingState` | `type` — 压缩追踪状态 |
| `AUTOCOMPACT_BUFFER_TOKENS` | `const` — 自动压缩缓冲（13,000 tokens） |

**`calculateTokenWarningState` 返回值：**
- `percentLeft` — 剩余百分比
- `isAboveWarningThreshold` — 是否超过警告阈值
- `isAboveErrorThreshold` — 是否超过错误阈值
- `isAboveAutoCompactThreshold` — 是否触发自动压缩
- `isAtBlockingLimit` — 是否到达阻塞限制

### compact.ts — 压缩执行

| 导出 | 类型 | 说明 |
|------|------|------|
| `compactConversation(params)` | `async function` | 执行对话压缩（使用 forked agent 生成摘要） |
| `CompactionResult` | `type` — 压缩结果 |
| `RecompactionInfo` | `type` — 重新压缩信息 |

---

## services/extractMemories — 记忆提取

| 导出 | 类型 | 说明 |
|------|------|------|
| `initExtractMemories()` | `function` | 初始化记忆提取（注册后采样钩子） |
| `createAutoMemCanUseTool()` | `function` | 创建自动记忆专用的工具权限检查函数 |

**功能：** 在每个完整查询循环结束时，使用 forked agent 从对话中提取持久记忆，写入 `~/.claude/projects/<path>/memory/` 目录。

---

## services/notifier — 通知发送

| 导出 | 类型 | 说明 |
|------|------|------|
| `sendNotification(notif, terminal)` | `async function` | 发送桌面通知 |
| `NotificationOptions` | `type` — `{ message, title?, notificationType }` |

**通知渠道：**
- `auto` — 自动选择（iTerm2 → Kitty → Ghostty → Terminal Bell）
- `iterm2` / `iterm2_with_bell` — iTerm2 专用通知
- `kitty` — Kitty 终端通知
- `ghostty` — Ghostty 终端通知
- `terminal_bell` — 终端响铃
- `notifications_disabled` — 禁用通知

---

## services/preventSleep — 防止休眠

| 导出 | 类型 | 说明 |
|------|------|------|
| `startPreventSleep()` | `function` | 增加引用计数并开始防止休眠（macOS `caffeinate`） |
| `stopPreventSleep()` | `function` | 减少引用计数，无引用时允许休眠 |
| `forceStopPreventSleep()` | `function` | 强制停止防止休眠（清理时使用） |

**机制：** macOS 上使用 `caffeinate` 命令，每 4 分钟重启一次（5 分钟超时），仅 macOS 有效。

---

## services/diagnosticTracking — 诊断追踪

| 导出 | 类型 | 说明 |
|------|------|------|
| `DiagnosticTrackingService` | `class` | 单例服务，追踪 LSP/IDE 诊断变化，用于检测代码修改引入的错误 |

**主要方法：**
- `getInstance()` — 获取单例实例
- `initialize(mcpClient)` — 使用 IDE MCP 客户端初始化
- `getNewDiagnosticsSinceBaseline(fileUri)` — 获取自基线以来的新诊断
- `getFileDiagnosticsSummary(fileUri)` — 获取文件诊断摘要
- `reset()` — 重置追踪状态
- `shutdown()` — 关闭服务

---

## services/tokenEstimation — Token 估算

| 导出 | 类型 | 说明 |
|------|------|------|
| `countTokens(params)` | `async function` | 精确计算消息的 token 数。支持 Anthropic API、AWS Bedrock、Vertex AI |
| `countTokensWithCache(params)` | `async function` | 带缓存的 token 计算 |

---

## services/vcr — 请求录制回放

| 导出 | 类型 | 说明 |
|------|------|------|
| `withVCR(messages, fn)` | `async function` | VCR 包装器：测试时录制/回放 API 响应 |
| `withTokenCountVCR(fn)` | `function` | Token 计数 VCR 包装器 |

**机制：** 基于 SHA-1 哈希的请求-响应 fixture 缓存。CI 中缺失 fixture 会报错，本地自动录制。

---

## services/awaySummary — 离线摘要

| 导出 | 类型 | 说明 |
|------|------|------|
| `generateAwaySummary(messages, signal)` | `async function` | 生成"离开期间"会话摘要（1-3 句话），用于用户返回时快速了解进展 |

---

## services/internalLogging — 内部日志

| 导出 | 类型 | 说明 |
|------|------|------|
| `getContainerId()` | `async function` | 获取 OCI 容器 ID（内部环境） |
| `logPermissionContextForAnts(context, moment)` | `async function` | 记录权限上下文（内部环境） |

---

## services/tools — 工具执行

### StreamingToolExecutor.ts — 流式工具执行器

| 导出 | 类型 | 说明 |
|------|------|------|
| `StreamingToolExecutor` | `class` | 流式工具执行器，支持并发控制和顺序输出 |

**特性：**
- 并发安全工具可并行执行
- 非并发工具独占执行
- 结果按接收顺序缓冲输出
- 支持 discard（流式回退时丢弃结果）

### toolExecution.ts — 工具执行核心

| 导出 | 类型 | 说明 |
|------|------|------|
| `runToolUse(params)` | `async function` | 执行单个工具调用（权限检查 → 执行 → 结果处理） |

### toolHooks.ts — 工具钩子

工具执行前后的钩子处理。

### toolOrchestration.ts — 工具编排

多工具调用的编排逻辑。

---

## services/toolUseSummary — 工具使用摘要

| 导出 | 类型 | 说明 |
|------|------|------|
| `generateToolUseSummary(params)` | `async function` | 使用 Haiku 模型生成工具批次的简短摘要（≤ 30 字符）。用于 SDK 客户端显示进度 |

---

## services/AgentSummary — Agent 摘要

| 导出 | 说明 |
|------|------|
| Agent 执行结果摘要生成 | |

---

## services/policyLimits — 策略限制

| 导出 | 类型 | 说明 |
|------|------|------|
| `loadPolicyLimits()` | `async function` | 加载组织级策略限制（API 失败时 fail-open） |
| `initializePolicyLimitsLoadingPromise()` | `function` | 初始化加载 Promise（允许其他系统等待） |
| `getPolicyRestrictions()` | `function` | 获取当前策略限制 |
| `isFeatureRestricted(feature)` | `function` | 检查功能是否被策略限制 |
| `stopBackgroundPolling()` | `function` | 停止后台轮询 |
| `_resetPolicyLimitsForTesting()` | `function` | 测试重置 |

**轮询间隔：** 1 小时。支持 ETag 缓存和指数退避重试。

---

## services/remoteManagedSettings — 远程托管设置

| 导出 | 类型 | 说明 |
|------|------|------|
| `loadRemoteManagedSettings()` | `async function` | 加载远程托管设置（企业客户） |
| `initializeRemoteManagedSettingsLoadingPromise()` | `function` | 初始化加载 Promise |
| `stopRemoteManagedSettingsPolling()` | `function` | 停止后台轮询 |
| `forceReloadRemoteManagedSettings()` | `async function` | 强制重新加载远程设置 |

**特性：**
- 基于校验和的增量更新
- ETag 缓存
- 1 小时轮询间隔
- 安全检查（`securityCheck.ts`）
- 失败时 fail-open

---

## services/mcpServerApproval.tsx — MCP 服务器审批

MCP 服务器连接时的用户审批 UI 组件。

---

## services/claudeAiLimitsHook.ts — 速率限制 Hook

React Hook，用于在 UI 中显示速率限制状态。

---

## services/mockRateLimits.ts — 模拟速率限制

`/mock-limits` 命令的支持，用于测试速率限制 UI。

---

## services/rateLimitMessages.ts — 速率限制消息

速率限制错误/警告消息的生成。

---

## services/rateLimitMocking.ts — 速率限制模拟

速率限制模拟逻辑（测试和内部调试用）。

---

## services/mcpStringUtils.ts — MCP 字符串工具

MCP 工具名构建（`mcp__<server>__<tool>`）和解析。

---

## services/envExpansion.ts — 环境变量展开

在 MCP 配置值中替换 `$VAR` 和 `${VAR}` 环境变量占位符。
