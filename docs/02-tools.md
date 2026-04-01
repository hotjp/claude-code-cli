# 工具系统 (tools/)

## 架构概览

工具系统是 Claude Code CLI 的核心可扩展层，每个工具模块通过 `buildTool()` 工厂函数构造，返回符合 `Tool` 接口的对象。工具的完整生命周期如下：

```
buildTool(ToolDef) → Tool 对象 → isEnabled() → validateInput() → checkPermissions() → call() → 渲染 UI
```

### 核心接口

- **`buildTool(def: ToolDef<I, O>): Tool<I, O>`** — 工厂函数，接收工具定义并返回冻结的 Tool 对象
- **`Tool`** — 包含 `name`、`inputSchema`、`outputSchema`、`call()`、`checkPermissions()`、`isEnabled()`、`isReadOnly()`、`isConcurrencySafe()` 等属性
- **`ToolDef`** — 工具定义类型，所有字段均可选，仅 `call` 是必需的
- **`lazySchema()`** — 延迟求值的 Zod schema 包装器，避免模块加载时执行重度 schema 构建

### 权限检查流程

1. `isEnabled()` — 判断工具在当前会话是否可用（如 KAIROS 特性门控、功能开关）
2. `validateInput()` — 校验输入参数合法性（路径是否存在、文件大小限制等），返回 `ValidationResult`
3. `checkPermissions()` — 检查用户权限（allow/deny/ask），返回 `PermissionDecision`（behavior: `'allow' | 'deny' | 'ask' | 'passthrough'`）
4. `call()` — 实际执行工具逻辑

### 特殊标记

- **`isReadOnly()`** — 只读工具，不修改文件系统
- **`isConcurrencySafe()`** — 可安全并发调用
- **`isSearchOrReadCommand()`** — 标记为搜索/读取类命令（用于 UI 折叠显示）
- **`shouldDefer`** — 延迟加载工具，模型需通过 ToolSearch 激活
- **`strict`** — 启用 Zod strictObject 严格校验
- **`isMcp`** — MCP 工具标记
- **`isLsp`** — LSP 工具标记
- **`requiresUserInteraction()`** — 需要用户交互才能完成

---

## 文件系统工具

### FileReadTool

**用途**: 读取本地文件系统中的文件内容，支持文本、图像、PDF、目录列表等。

- **name**: `Read`
- **文件**: `FileReadTool/FileReadTool.ts`
- **isReadOnly**: `true`
- **isConcurrencySafe**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `file_path` | `string` | 文件绝对路径（必须） |
| `offset` | `number` | 起始行号（1-indexed） |
| `limit` | `number` | 最大读取行数 |
| `encoding` | `string` | 文件编码 |

**核心 call() 逻辑**:
1. 阻止读取设备文件（`/dev/zero`, `/dev/random` 等），防止进程挂起
2. 处理 macOS 截图路径中的特殊空格字符（U+202F）
3. 检测文件类型：文本、图像、PDF、目录、Notebook (.ipynb)
4. 图像文件：压缩并转为 Base64 传给 API
5. PDF 文件：使用 `extractPDFPages` 提取文本内容
6. 目录：列出目录内容
7. 文本文件：按 offset/limit 范围读取，添加行号，检测 token 超限
8. 激活条件技能（`activateConditionalSkillsForPaths`）

**辅助函数**:
- `isBlockedDevicePath()` — 检测危险的设备文件路径
- `getAlternateScreenshotPath()` — 处理 macOS 截图路径中的窄空格
- `registerFileReadListener()` — 注册文件读取监听器，供其他服务订阅
- `MaxFileReadTokenExceededError` — token 超限异常类

---

### FileEditTool

**用途**: 对已有文件进行精确的字符串替换编辑（非整文件覆写）。

- **name**: `Edit`
- **文件**: `FileEditTool/FileEditTool.ts`
- **isReadOnly**: `false`
- **strict**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `file_path` | `string` | 文件绝对路径 |
| `old_string` | `string` | 待替换的原始字符串 |
| `new_string` | `string` | 替换后的新字符串 |
| `replace_all` | `boolean` | 是否替换所有匹配项 |

**核心 call() 逻辑**:
1. 校验 old_string !== new_string（无变更则拒绝）
2. 检查文件大小上限（1 GiB），防止 OOM
3. 检测文件意外修改（mtime 与读取时间戳对比）
4. 查找 old_string 在文件中的位置（支持 `findActualString` 模糊匹配）
5. 执行字符串替换，写回文件
6. 记录文件历史（如启用 `fileHistory`）
7. 通知 VS Code 和 LSP 诊断追踪器

**辅助模块**:
- `FileEditTool/utils.ts` — `findActualString()`（智能字符串查找）、`getPatchForEdit()`（生成 diff）、`preserveQuoteStyle()`（保持引号风格）
- `FileEditTool/types.ts` — 输入/输出 schema 和 git diff 相关类型
- `FileEditTool/constants.ts` — `FILE_EDIT_TOOL_NAME`、`FILE_UNEXPECTEDLY_MODIFIED_ERROR`

---

### FileWriteTool

**用途**: 创建新文件或完整覆写已有文件。

- **name**: `Write`
- **文件**: `FileWriteTool/FileWriteTool.ts`
- **isReadOnly**: `false`
- **strict**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `file_path` | `string` | 文件绝对路径 |
| `content` | `string` | 要写入的完整内容 |

**核心 call() 逻辑**:
1. 校验文件路径权限（deny rule 检查）
2. 检测 secrets 泄露（`checkTeamMemSecrets`）
3. 文件意外修改检测（mtime 对比 `readFileState`）
4. `writeTextContent()` 写入文件
5. 生成结构化 diff patch（`gitDiffSchema`）
6. 激活条件技能、通知 LSP 和 VS Code

---

### NotebookEditTool

**用途**: 编辑 Jupyter Notebook (.ipynb) 文件的单元格。

- **name**: `NotebookEdit`
- **文件**: `NotebookEditTool/NotebookEditTool.ts`
- **isReadOnly**: `false`
- **shouldDefer**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `notebook_path` | `string` | Notebook 文件绝对路径 |
| `cell_id` | `string` | 要编辑的单元格 ID |
| `new_source` | `string` | 单元格新内容 |
| `cell_type` | `'code' \| 'markdown'` | 单元格类型 |
| `edit_mode` | `'replace' \| 'insert' \| 'delete'` | 编辑模式 |

**核心 call() 逻辑**:
1. 校验文件扩展名为 `.ipynb`
2. 解析 JSON，操作 cells 数组（替换/插入/删除）
3. 通过 `parseCellId()` 定位单元格
4. 写回文件并记录文件历史

---

## 搜索工具

### GlobTool

**用途**: 使用 glob 模式匹配查找文件。

- **name**: `Glob`
- **文件**: `GlobTool/GlobTool.ts`
- **isReadOnly**: `true`
- **isConcurrencySafe**: `true`
- **isSearchOrReadCommand**: `{ isSearch: true, isRead: false }`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `pattern` | `string` | Glob 匹配模式 |
| `path` | `string` | 搜索目录（可选，默认 cwd） |

**核心 call() 逻辑**:
1. 校验搜索路径存在且为目录
2. 调用 `glob()` 函数执行搜索，默认限制 100 个结果
3. 将结果路径转换为相对路径（节省 token）
4. 如结果被截断，附加提示信息

---

### GrepTool

**用途**: 使用正则表达式在文件内容中搜索（底层调用 ripgrep）。

- **name**: `Grep`
- **文件**: `GrepTool/GrepTool.ts`
- **isReadOnly**: `true`
- **isConcurrencySafe**: `true`
- **isSearchOrReadCommand**: `{ isSearch: true, isRead: false }`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `pattern` | `string` | 正则表达式模式 |
| `path` | `string` | 搜索路径（文件或目录） |
| `glob` | `string` | 文件类型过滤（如 `*.ts`） |
| `output_mode` | `'content' \| 'files_with_matches' \| 'count'` | 输出模式 |
| `-A` / `-B` / `-C` | `number` | 上下文行数 |
| `-i` | `boolean` | 忽略大小写 |
| `head_limit` | `number` | 结果数量限制（默认 250） |
| `offset` | `number` | 跳过前 N 条结果 |
| `multiline` | `boolean` | 多行模式 |

**核心 call() 逻辑**:
1. 构建 ripgrep 参数，应用 glob 排除规则
2. 调用 `ripGrep()` 执行搜索
3. 按 output_mode 格式化输出（文件列表/匹配内容/计数）
4. 应用分页（head_limit + offset）

**辅助函数**:
- `applyHeadLimit()` — 分页截断，支持 `head_limit=0` 无限制
- `formatLimitInfo()` — 格式化分页信息

---

## Shell 工具

### BashTool

**用途**: 在持久化 shell 中执行 Bash 命令。系统中最复杂的工具之一。

- **name**: `Bash`（通过 `BASH_TOOL_NAME` 常量）
- **文件**: `BashTool/BashTool.tsx`
- **isReadOnly**: 根据命令语义动态判断
- **isConcurrencySafe**: `false`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `command` | `string` | 要执行的 Bash 命令 |
| `timeout` | `number` | 超时时间（毫秒） |
| `description` | `string` | 命令描述（5-10 词） |

**核心 call() 逻辑**:
1. AST 安全解析（`parseForSecurity`）
2. 只读命令检测（`checkReadOnlyConstraints`）
3. 权限匹配（`bashToolHasPermission`）
4. sed 编辑命令拦截（重定向到 FileEditTool）
5. 沙盒检测（`shouldUseSandbox`）
6. 通过 `exec()` 执行命令，收集 stdout/stderr
7. Git 操作追踪（`trackGitOperations`）
8. 长时间运行命令自动后台化
9. 图像输出检测与缩放
10. 大输出持久化到磁盘（`buildLargeToolResultMessage`）

**辅助模块**（`BashTool/` 子目录下）:
- `readOnlyValidation.ts` — 只读命令判定
- `pathValidation.ts` — 路径安全校验
- `bashPermissions.ts` — 权限规则匹配（`matchWildcardPattern`、`permissionRuleExtractPrefix`）
- `bashSecurity.ts` — 安全检查（禁止命令、危险操作）
- `commandSemantics.ts` — 命令语义解释（`interpretCommandResult`）
- `sedEditParser.ts` — 解析 sed 编辑命令
- `shouldUseSandbox.ts` — 沙盒决策
- `destructiveCommandWarning.ts` — 危险命令警告
- `modeValidation.ts` — 模式校验
- `bashCommandHelpers.ts` — 命令辅助函数
- `commentLabel.ts` — 注释标签处理

**关键导出函数**:
- `isSearchOrReadBashCommand()` — 判断命令是否为搜索/读取操作（用于 UI 折叠）

---

### PowerShellTool

**用途**: 在 Windows 上执行 PowerShell 命令（BashTool 的 Windows 对应工具）。

- **name**: `PowerShell`（通过 `POWERSHELL_TOOL_NAME`）
- **文件**: `PowerShellTool/PowerShellTool.tsx`

**结构与 BashTool 高度镜像**，包含类似的权限检查、只读检测、命令语义分析，但针对 PowerShell cmdlet 语法适配。

**辅助模块**:
- `readOnlyValidation.ts` — 只读命令检测（`isReadOnlyCommand`、`hasSyncSecurityConcerns`）
- `powershellPermissions.ts` — 权限规则匹配
- `powershellSecurity.ts` — PowerShell 安全检查
- `commandSemantics.ts` — 命令语义解释
- `pathValidation.ts` — 路径安全
- `modeValidation.ts` — 模式校验
- `destructiveCommandWarning.ts` — 危险命令警告
- `gitSafety.ts` — Git 安全检查
- `clmTypes.ts` — CLM 类型定义
- `commonParameters.ts` — 公共参数处理

**关键导出函数**:
- `detectBlockedSleepPattern()` — 检测阻塞式 sleep 命令

---

## 智能代理工具

### AgentTool

**用途**: 创建和管理子代理（sub-agent），支持同步/异步/远程/多代理等多种模式。系统中最复杂的工具。

- **name**: `Agent`（通过 `AGENT_TOOL_NAME`）
- **文件**: `AgentTool/AgentTool.tsx`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `description` | `string` | 任务简短描述（3-5 词） |
| `prompt` | `string` | 代理要执行的任务提示 |
| `subagent_type` | `string` | 特化代理类型 |
| `model` | `'sonnet' \| 'opus' \| 'haiku'` | 模型覆盖 |
| `run_in_background` | `boolean` | 后台运行 |
| `name` | `string` | 代理名称（用于寻址） |
| `team_name` | `string` | 团队名 |
| `mode` | `PermissionMode` | 权限模式 |
| `isolation` | `'worktree' \| 'remote'` | 隔离模式 |
| `cwd` | `string` | 工作目录覆盖 |

**核心 call() 逻辑**:
1. 验证代理类型（内置代理 vs 自定义代理）
2. 判断运行模式：同步前台 / 异步后台 / fork 子代理 / 远程代理 / 多代理 teammate
3. 为代理组装独立的工具池（`assembleToolPool`）
4. 构建系统提示（`buildEffectiveSystemPrompt`）
5. 通过 `runAgent()` 或 `runAsyncAgentLifecycle()` 执行
6. 支持 worktree 隔离（`createAgentWorktree`）
7. 进度追踪与输出文件生成
8. 结果摘要化（`startAgentSummarization`）

**辅助模块**:
- `AgentTool/agentToolUtils.ts` — 代理工具辅助函数（结果分类、进度发射等）
- `AgentTool/forkSubagent.ts` — Fork 子代理逻辑
- `AgentTool/runAgent.ts` — 代理运行入口
- `AgentTool/loadAgentsDir.ts` — 加载自定义代理定义
- `AgentTool/agentColorManager.ts` — 代理颜色管理
- `AgentTool/built-in/generalPurposeAgent.ts` — 通用代理定义

---

### SkillTool

**用途**: 执行技能（Skills）命令，支持内置命令、自定义命令和 MCP 技能。

- **name**: `Skill`
- **文件**: `SkillTool/SkillTool.ts`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `skill` | `string` | 技能/命令名称 |
| `args` | `string` | 命令参数 |

**核心 call() 逻辑**:
1. 查找匹配的命令（本地命令 + MCP 技能）
2. 支持 fork 子代理执行模式（`executeForkedSkill`）
3. 解析命令 frontmatter（`parseFrontmatter`）
4. 支持远程技能搜索与加载（`EXPERIMENTAL_SKILL_SEARCH` 特性门控）
5. 记录技能使用（`recordSkillUsage`）

---

## 计划模式工具

### EnterPlanModeTool

**用途**: 进入计划模式，切换到只读探索和设计阶段。

- **name**: `EnterPlanMode`
- **文件**: `EnterPlanModeTool/EnterPlanModeTool.ts`
- **isReadOnly**: `true`
- **shouldDefer**: `true`
- **isEnabled**: 在 `--channels` 模式下禁用（无法显示审批对话框）

**核心 call() 逻辑**:
1. 切换权限模式为 `plan`
2. 运行分类器激活副作用（`prepareContextForPlanMode`）
3. 返回计划模式指令

---

### ExitPlanModeV2Tool

**用途**: 退出计划模式，展示计划供用户审批。

- **name**: `ExitPlanMode`
- **文件**: `ExitPlanModeTool/ExitPlanModeV2Tool.ts`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `allowedPrompts` | `AllowedPrompt[]` | 请求的基于提示的权限 |

**核心 call() 逻辑**:
1. 读取磁盘上的计划文件
2. 设置计划审批状态（`setAwaitingPlanApproval`）
3. 支持 teammate 请求 leader 审批
4. 支持 auto-mode 权限更新（`TRANSCRIPT_CLASSIFIER` 特性）
5. 返回计划内容及审批状态

---

## Worktree 工具

### EnterWorktreeTool

**用途**: 创建隔离的 git worktree 并切换工作目录。

- **name**: `EnterWorktree`
- **文件**: `EnterWorktreeTool/EnterWorktreeTool.ts`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `string` | Worktree 名称（可选，自动生成） |

**核心 call() 逻辑**:
1. 校验不在已有 worktree 中
2. 解析到主仓库根目录
3. 调用 `createWorktreeForSession()` 创建 worktree
4. 切换 `process.chdir`、更新 session 状态
5. 清除系统提示缓存和内存文件缓存

---

### ExitWorktreeTool

**用途**: 退出 worktree 会话，恢复到原始目录。

- **name**: `ExitWorktree`
- **文件**: `ExitWorktreeTool/ExitWorktreeTool.ts`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `action` | `'keep' \| 'remove'` | 保留或删除 worktree |
| `discard_changes` | `boolean` | 强制删除时的确认 |

**核心 call() 逻辑**:
1. 统计 worktree 中的变更（`countWorktreeChanges`）
2. 如有未提交变更且未确认，拒绝删除
3. 执行 `cleanupWorktree()` 或 `keepWorktree()`
4. 调用 `restoreSessionToOriginalCwd()` 恢复会话状态

**辅助函数** (私有):
- `countWorktreeChanges()` — 统计未提交文件数和提交数（fail-closed 策略，内部使用）
- `restoreSessionToOriginalCwd()` — 恢复 CWD、projectRoot、hooks 快照等（内部使用）

---

## MCP 工具

### MCPTool

**用途**: MCP (Model Context Protocol) 工具的基础模板。实际的 MCP 工具在 `mcpClient.ts` 中动态创建，覆盖 `name`、`description`、`call()` 等方法。

- **name**: `mcp`（被覆盖为 `mcp__<server>__<tool>`）
- **文件**: `MCPTool/MCPTool.ts`
- **isMcp**: `true`
- **inputSchema**: `z.object({}).passthrough()`（接受任意输入，实际 schema 由 MCP server 定义）

**特殊行为**: `checkPermissions()` 返回 `passthrough`，权限由 MCP 客户端单独处理。

---

### McpAuthTool

**用途**: 为需要 OAuth 认证的 MCP 服务器提供认证工具（伪工具，认证完成后被真实工具替换）。

- **文件**: `McpAuthTool/McpAuthTool.ts`
- **工厂函数**: `createMcpAuthTool(serverName, config)`

**核心 call() 逻辑**:
1. 检查传输类型（仅 SSE/HTTP 支持 OAuth）
2. 调用 `performMCPOAuthFlow()` 启动 OAuth 流程
3. 返回授权 URL 供用户浏览器打开
4. 后台等待 OAuth 完成，然后重新连接服务器并替换工具

---

### ListMcpResourcesTool

**用途**: 列出已连接 MCP 服务器提供的资源。

- **name**: `ListMcpResourcesTool`
- **文件**: `ListMcpResourcesTool/ListMcpResourcesTool.ts`
- **isReadOnly**: `true`
- **shouldDefer**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `server` | `string` | 过滤指定服务器（可选） |

**核心 call() 逻辑**:
1. 按 server 过滤 MCP 客户端
2. 调用 `ensureConnectedClient()` 确保连接
3. 调用 `fetchResourcesForClient()` 获取资源列表（LRU 缓存）

---

### ReadMcpResourceTool

**用途**: 读取指定 MCP 服务器的特定资源。

- **name**: `ReadMcpResourceTool`
- **文件**: `ReadMcpResourceTool/ReadMcpResourceTool.ts`
- **isReadOnly**: `true`
- **shouldDefer**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `server` | `string` | MCP 服务器名 |
| `uri` | `string` | 资源 URI |

**核心 call() 逻辑**:
1. 查找并验证 MCP 客户端连接
2. 调用 `resources/read` MCP 方法
3. 处理 blob 内容：解码 Base64，持久化到磁盘，返回文件路径

---

## LSP 工具

### LSPTool

**用途**: 通过 Language Server Protocol 执行代码智能操作（跳转定义、查找引用、符号搜索等）。

- **name**: `LSP`
- **文件**: `LSPTool/LSPTool.ts`
- **isReadOnly**: `true`
- **isConcurrencySafe**: `true`
- **isLsp**: `true`
- **isEnabled**: `isLspConnected()`（需要 LSP 服务器已连接）
- **shouldDefer**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `operation` | `enum` | 操作类型（见下表） |
| `filePath` | `string` | 文件路径 |
| `line` | `number` | 行号（1-based） |
| `character` | `number` | 列号（1-based） |

**支持的 operation**:
| 操作 | 说明 |
|------|------|
| `goToDefinition` | 跳转到定义 |
| `findReferences` | 查找所有引用 |
| `hover` | 获取悬停信息 |
| `documentSymbol` | 文档符号列表 |
| `workspaceSymbol` | 工作区符号搜索 |
| `goToImplementation` | 跳转到实现 |
| `prepareCallHierarchy` | 准备调用层次 |
| `incomingCalls` | 传入调用 |
| `outgoingCalls` | 传出调用 |

**辅助模块**:
- `LSPTool/formatters.ts` — 格式化各种 LSP 操作结果
- `LSPTool/schemas.ts` — 鉴别联合 schema（更好的错误提示）
- `LSPTool/symbolContext.ts` — 符号上下文信息

---

## 任务管理工具

### TodoWriteTool

**用途**: 管理会话级的待办清单（V1 版本，已被 TaskV2 替代）。

- **name**: `TodoWrite`
- **isEnabled**: `!isTodoV2Enabled()`（V2 启用时禁用）
- **shouldDefer**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `todos` | `TodoList` | 更新后的待办列表 |

**核心 call() 逻辑**: 更新 AppState 中的 todos，当所有任务完成时清空列表。支持验证代理提示（`verificationNudgeNeeded`）。

---

### TaskCreateTool

**用途**: 创建新任务（TaskV2）。

- **name**: `TaskCreate`
- **isEnabled**: `isTodoV2Enabled()`
- **shouldDefer**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `subject` | `string` | 任务标题 |
| `description` | `string` | 任务描述 |
| `activeForm` | `string` | 进行时形式（如 "Running tests"） |
| `metadata` | `Record<string, unknown>` | 附加元数据 |

**核心 call() 逻辑**:
1. 调用 `createTask()` 创建任务
2. 执行 `TaskCreated` hooks
3. 如 hook 返回 blocking error，删除任务并抛出异常
4. 自动展开任务列表视图

---

### TaskGetTool

**用途**: 按 ID 获取单个任务详情。

- **name**: `TaskGet`
- **isReadOnly**: `true`
- **isEnabled**: `isTodoV2Enabled()`

---

### TaskListTool

**用途**: 列出所有任务。

- **name**: `TaskList`
- **isReadOnly**: `true`
- **isEnabled**: `isTodoV2Enabled()`

**核心 call() 逻辑**: 获取所有任务，过滤内部任务，过滤已完成的 blockedBy 引用。

---

### TaskUpdateTool

**用途**: 更新任务属性（状态、标题、描述、依赖关系等）。

- **name**: `TaskUpdate`
- **isEnabled**: `isTodoV2Enabled()`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `taskId` | `string` | 任务 ID |
| `status` | `TaskStatus \| 'deleted'` | 新状态（`deleted` 为特殊删除操作） |
| `subject` | `string` | 新标题 |
| `addBlocks` / `addBlockedBy` | `string[]` | 任务依赖关系 |
| `owner` | `string` | 任务负责人 |

**核心 call() 逻辑**: 支持 `deleted` 状态作为删除操作。完成/删除时执行 hooks。支持验证代理提示。

---

### TaskStopTool

**用途**: 停止运行中的后台任务。

- **name**: `TaskStop`
- **aliases**: `['KillShell']`（向后兼容）
- **shouldDefer**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `task_id` | `string` | 任务 ID |
| `shell_id` | `string` | 已弃用，使用 task_id |

---

### TaskOutputTool

**用途**: 获取后台任务的输出（已弃用，推荐使用 Read 工具直接读取输出文件）。

- **name**: `TaskOutput`
- **aliases**: `['AgentOutputTool', 'BashOutputTool']`
- **isReadOnly**: `true`
- **shouldDefer**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `task_id` | `string` | 任务 ID |
| `block` | `boolean` | 是否等待完成（默认 true） |
| `timeout` | `number` | 最大等待时间（默认 30s，上限 600s） |

**核心 call() 逻辑**:
1. 支持所有任务类型（bash、agent、remote）
2. `block=true` 时轮询等待任务完成（100ms 间隔）
3. 返回任务输出、状态、退出码等

---

## 团队协作工具

### TeamCreateTool

**用途**: 创建多代理 swarm 团队。

- **name**: `TeamCreate`
- **isEnabled**: `isAgentSwarmsEnabled()`
- **shouldDefer**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `team_name` | `string` | 团队名 |
| `description` | `string` | 团队描述 |
| `agent_type` | `string` | Leader 类型/角色 |

**核心 call() 逻辑**:
1. 校验不重复创建团队
2. 生成唯一团队名（`generateUniqueTeamName`）
3. 创建团队文件、分配颜色
4. 注册会话清理回调

---

### TeamDeleteTool

**用途**: 解散团队并清理资源。

- **name**: `TeamDelete`
- **isEnabled**: `isAgentSwarmsEnabled()`
- **shouldDefer**: `true`

**核心 call() 逻辑**:
1. 检查是否有活跃成员，有则拒绝清理
2. 调用 `cleanupTeamDirectories()` 清理目录和 worktree
3. 清除颜色分配、leader team name
4. 清空 AppState 中的团队上下文和收件箱

---

### SendMessageTool

**用途**: 在团队成员间发送消息（点对点、广播、结构化消息）。

- **name**: `SendMessage`
- **shouldDefer**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `to` | `string` | 接收者（队友名 / `*` 广播 / `uds:<path>` / `bridge:<session>`） |
| `message` | `string \| StructuredMessage` | 消息内容 |
| `summary` | `string` | 消息摘要（5-10 词） |

**StructuredMessage 类型**:
- `shutdown_request` — 请求关闭
- `shutdown_response` — 关闭响应（approve/reject）
- `plan_approval_response` — 计划审批响应

**核心 call() 逻辑**:
1. 解析接收者地址（`parseAddress`）
2. 区分本地队友/广播/UDS peer/bridge peer
3. 通过邮箱系统投递（`writeToMailbox`）
4. 支持关闭协商协议

---

## Web 工具

### WebFetchTool

**用途**: 获取 URL 内容并对内容执行提示处理。

- **name**: `Fetch`
- **文件**: `WebFetchTool/WebFetchTool.ts`
- **isReadOnly**: `true`
- **isConcurrencySafe**: `true`
- **shouldDefer**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `url` | `string` | 要获取的 URL |
| `prompt` | `string` | 对获取内容执行的提示 |

**核心 call() 逻辑**:
1. URL 有效性校验
2. 检查预批准域名（`isPreapprovedHost`）
3. 获取 URL 内容并转为 Markdown（`getURLMarkdownContent`）
4. 将 prompt 应用于内容（`applyPromptToMarkdown`）

**辅助模块**:
- `WebFetchTool/utils.ts` — URL 获取、Markdown 转换、预批准检测
- `WebFetchTool/preapproved.ts` — 预批准域名列表

---

### WebSearchTool

**用途**: 使用 Anthropic 内置 Web Search 功能进行网络搜索。

- **name**: `WebSearch`
- **文件**: `WebSearchTool/WebSearchTool.ts`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `query` | `string` | 搜索查询 |
| `allowed_domains` | `string[]` | 白名单域名 |
| `blocked_domains` | `string[]` | 黑名单域名 |

**核心 call() 逻辑**:
1. 构建 `BetaWebSearchTool20250305` schema
2. 通过 `queryModelWithStreaming()` 发起带 web_search 工具的 API 请求
3. 解析搜索响应（`server_tool_use` + `web_search_tool_result` + `text` blocks）
4. 每次最多 8 次搜索

---

## 计划调度工具

### CronCreateTool

**用途**: 创建定时任务（cron jobs）。

- **name**: `CronCreate`
- **isEnabled**: `isKairosCronEnabled()`
- **shouldDefer**: `true`

| 字段 | 类型 | 说明 |
|------|------|------|
| `cron` | `string` | 标准 5 字段 cron 表达式 |
| `prompt` | `string` | 触发时的提示 |
| `recurring` | `boolean` | 是否循环（默认 true） |
| `durable` | `boolean` | 是否持久化到磁盘（默认 false） |

### CronListTool

**用途**: 列出所有定时任务。

### CronDeleteTool

**用途**: 删除定时任务。

---

## 其他工具

### BriefTool

**用途**: 向用户发送消息（Kairos 模式下的主要输出通道），支持附件和主动通知。

- **name**: `Brief`（别名：`SendUserMessage`）
- **isEnabled**: `isBriefEnabled()`（需要 KAIROS/KAIROS_BRIEF 特性 + 用户选择加入）
- **isReadOnly**: `true`
- **isConcurrencySafe**: `true`

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `message` | `string` | 消息内容（支持 Markdown） |
| `attachments` | `string[]` | 附件文件路径 |
| `status` | `'normal' \| 'proactive'` | 消息状态 |

**辅助函数**:
- `isBriefEntitled()` — 检查用户是否有权使用 Brief
- `isBriefEnabled()` — 检查 Brief 是否激活（entitled + opted-in）

---

### AskUserQuestionTool

**用途**: 向用户展示多选题问卷，收集用户选择。

- **name**: `AskUserQuestion`
- **isReadOnly**: `true`
- **isConcurrencySafe**: `true`
- **requiresUserInteraction**: `true`
- **isEnabled**: `--channels` 模式下禁用

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `questions` | `Question[]` | 问题列表（1-4 个） |

**Question 结构**: `{ question, header, options: Option[], multiSelect }`
**Option 结构**: `{ label, description, preview }`

---

### ConfigTool

**用途**: 获取或设置 Claude Code 配置项。

- **name**: `Config`
- **shouldDefer**: `true`
- **isConcurrencySafe**: `true`
- **isReadOnly**: `input.value === undefined`（只读判断基于是否有 value）

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `setting` | `string` | 配置键名（如 `theme`、`model`、`permissions.defaultMode`） |
| `value` | `string \| boolean \| number` | 新值（省略则为读取操作） |

**核心 call() 逻辑**:
1. 检查 setting 是否支持（`isSupported`）
2. GET 操作：读取当前值，支持 `formatOnRead` 格式化
3. SET 操作：类型强制转换（如字符串 `"true"` → 布尔值），保存到配置文件
4. 特殊处理 `remoteControlAtStartup` 的 `"default"` 值

**辅助模块**: `ConfigTool/supportedSettings.ts` — 支持的配置项定义

---

### ToolSearchTool

**用途**: 搜索和激活延迟加载的工具（ToolSearch 机制）。

- **name**: `ToolSearch`
- **isReadOnly**: `true`
- **shouldDefer**: 由工具自身管理

**inputSchema 主要字段**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `query` | `string` | 搜索查询（`select:<name>` 直接选择，关键词搜索） |
| `max_results` | `number` | 最大结果数（默认 5） |

**核心 call() 逻辑**:
1. 支持精确名称匹配（fast path）
2. 支持 `select:` 前缀直接选择
3. 关键词搜索：解析工具名（MCP `mcp__server__action`、CamelCase 拆分）+ 描述匹配
4. 描述缓存（`getToolDescriptionMemoized`），LRU 失效策略

**辅助函数**:
- `clearToolSearchDescriptionCache()` — 清除描述缓存

**内部 helper 函数**:
- `parseToolName()` — 将工具名解析为可搜索的部分（内部使用，非导出）
- `compileTermPatterns()` — 预编译搜索项正则（内部使用，非导出）

---

### SleepTool

**用途**: 等待指定时长（替代 `Bash(sleep ...)`，不占用 shell 进程）。

- **name**: `Sleep`
- **isConcurrencySafe**: `true`
- **isReadOnly**: `true`

支持接收 `<tick>` 定期检查提示。每次唤醒消耗一次 API 调用。

---

### SyntheticOutputTool

**用途**: 用于非交互式 SDK/CLI 模式下返回结构化 JSON 输出。

- **name**: `StructuredOutput`
- **isEnabled**: 仅在非交互式会话中创建
- **isReadOnly**: `true`
- **isConcurrencySafe**: `true`

**工厂函数**: `createSyntheticOutputTool(jsonSchema)` — 根据 JSON Schema 创建实例，使用 Ajv 校验输出。

---

### RemoteTriggerTool

**用途**: 管理远程代理触发器（CCR triggers）。

- **name**: `RemoteTrigger`
- **isEnabled**: 需要特性门控 + `allow_remote_sessions` 策略
- **shouldDefer**: `true`

| 操作 | 说明 |
|------|------|
| `list` | 列出所有触发器 |
| `get` | 获取单个触发器 |
| `create` | 创建触发器 |
| `update` | 更新触发器 |
| `run` | 手动触发执行 |

---

### REPLTool

**用途**: REPL 模式下的原语工具集合。

- **文件**: `REPLTool/primitiveTools.ts`

**`getReplPrimitiveTools()`** 返回 REPL 虚拟机可用的基础工具列表：FileRead、FileWrite、FileEdit、Glob、Grep、Bash、NotebookEdit、Agent。延迟初始化以避免循环依赖。

---

## 共享模块 (shared/)

### gitOperationTracking.ts

**用途**: Shell 无关的 Git 操作追踪，用于使用指标统计。

**追踪的操作**:
- Git commit / amend / cherry-pick
- Git push
- Git merge / rebase
- `gh pr create/edit/merge/comment/close/ready`
- `glab mr create`
- curl-based PR 创建

**导出函数**:
- `trackGitOperations()` — 分析命令和输出，更新 OTLP 计数器和分析事件

### spawnMultiAgent.ts

**用途**: 共享的 teammate 创建模块，被 AgentTool 和 TeammateTool 复用。

**关键导出函数**:
- `resolveTeammateModel()` — 解析 teammate 模型值（支持 `inherit` 别名）

**内部函数**:
- `getDefaultTeammateModel()` — 获取默认 teammate 模型（私有，仅供内部使用）

---

## 测试工具 (testing/)

### TestingPermissionTool

**用途**: 端到端测试专用的权限工具，始终弹出权限对话框。

- **name**: `TestingPermission`
- **isEnabled**: 仅在测试环境（`"production" === 'test'`）
- **checkPermissions**: 始终返回 `{ behavior: 'ask' }`

---

## 工具模块索引

| 工具名 | name | 只读 | 可并发 | 延迟加载 | 文件 |
|--------|------|------|--------|----------|------|
| AgentTool | `Agent` | - | - | - | `AgentTool/AgentTool.tsx` |
| AskUserQuestionTool | `AskUserQuestion` | ✓ | ✓ | - | `AskUserQuestionTool/AskUserQuestionTool.tsx` |
| BashTool | `Bash` | 动态 | ✗ | - | `BashTool/BashTool.tsx` |
| BriefTool | `Brief` | ✓ | ✓ | - | `BriefTool/BriefTool.ts` |
| ConfigTool | `Config` | 动态 | ✓ | ✓ | `ConfigTool/ConfigTool.ts` |
| CronCreateTool | `CronCreate` | - | - | ✓ | `ScheduleCronTool/CronCreateTool.ts` |
| CronListTool | `CronList` | ✓ | - | ✓ | `ScheduleCronTool/CronListTool.ts` |
| CronDeleteTool | `CronDelete` | - | - | ✓ | `ScheduleCronTool/CronDeleteTool.ts` |
| EnterPlanModeTool | `EnterPlanMode` | ✓ | ✓ | ✓ | `EnterPlanModeTool/EnterPlanModeTool.ts` |
| EnterWorktreeTool | `EnterWorktree` | - | - | ✓ | `EnterWorktreeTool/EnterWorktreeTool.ts` |
| ExitPlanModeTool | `ExitPlanMode` | - | - | - | `ExitPlanModeTool/ExitPlanModeV2Tool.ts` |
| ExitWorktreeTool | `ExitWorktree` | - | - | - | `ExitWorktreeTool/ExitWorktreeTool.ts` |
| FileEditTool | `Edit` | ✗ | - | - | `FileEditTool/FileEditTool.ts` |
| FileReadTool | `Read` | ✓ | ✓ | - | `FileReadTool/FileReadTool.ts` |
| FileWriteTool | `Write` | ✗ | - | - | `FileWriteTool/FileWriteTool.ts` |
| GlobTool | `Glob` | ✓ | ✓ | - | `GlobTool/GlobTool.ts` |
| GrepTool | `Grep` | ✓ | ✓ | - | `GrepTool/GrepTool.ts` |
| ListMcpResourcesTool | `ListMcpResourcesTool` | ✓ | ✓ | ✓ | `ListMcpResourcesTool/ListMcpResourcesTool.ts` |
| LSPTool | `LSP` | ✓ | ✓ | ✓ | `LSPTool/LSPTool.ts` |
| MCPTool | `mcp` (动态) | - | - | - | `MCPTool/MCPTool.ts` |
| McpAuthTool | `mcp__<server>__authenticate` | - | - | - | `McpAuthTool/McpAuthTool.ts` |
| NotebookEditTool | `NotebookEdit` | ✗ | - | ✓ | `NotebookEditTool/NotebookEditTool.ts` |
| PowerShellTool | `PowerShell` | 动态 | ✗ | - | `PowerShellTool/PowerShellTool.tsx` |
| ReadMcpResourceTool | `ReadMcpResourceTool` | ✓ | ✓ | ✓ | `ReadMcpResourceTool/ReadMcpResourceTool.ts` |
| RemoteTriggerTool | `RemoteTrigger` | 动态 | ✓ | ✓ | `RemoteTriggerTool/RemoteTriggerTool.ts` |
| SendMessageTool | `SendMessage` | - | - | ✓ | `SendMessageTool/SendMessageTool.ts` |
| SkillTool | `Skill` | - | - | - | `SkillTool/SkillTool.ts` |
| SleepTool | `Sleep` | ✓ | ✓ | - | `SleepTool/` (prompt only) |
| SyntheticOutputTool | `StructuredOutput` | ✓ | ✓ | - | `SyntheticOutputTool/SyntheticOutputTool.ts` |
| TaskCreateTool | `TaskCreate` | - | ✓ | ✓ | `TaskCreateTool/TaskCreateTool.ts` |
| TaskGetTool | `TaskGet` | ✓ | ✓ | ✓ | `TaskGetTool/TaskGetTool.ts` |
| TaskListTool | `TaskList` | ✓ | ✓ | ✓ | `TaskListTool/TaskListTool.ts` |
| TaskOutputTool | `TaskOutput` | ✓ | 动态 | ✓ | `TaskOutputTool/TaskOutputTool.tsx` |
| TaskStopTool | `TaskStop` | - | ✓ | ✓ | `TaskStopTool/TaskStopTool.ts` |
| TaskUpdateTool | `TaskUpdate` | - | ✓ | ✓ | `TaskUpdateTool/TaskUpdateTool.ts` |
| TeamCreateTool | `TeamCreate` | - | - | ✓ | `TeamCreateTool/TeamCreateTool.ts` |
| TeamDeleteTool | `TeamDelete` | - | - | ✓ | `TeamDeleteTool/TeamDeleteTool.ts` |
| TodoWriteTool | `TodoWrite` | - | - | ✓ | `TodoWriteTool/TodoWriteTool.ts` |
| ToolSearchTool | `ToolSearch` | ✓ | - | - | `ToolSearchTool/ToolSearchTool.ts` |
| WebFetchTool | `Fetch` | ✓ | ✓ | ✓ | `WebFetchTool/WebFetchTool.ts` |
| WebSearchTool | `WebSearch` | - | - | - | `WebSearchTool/WebSearchTool.ts` |
