# Skills 模块 (skills/)

`screens/` 目录包含应用的核心 UI 屏幕组件，负责启动引导、会话恢复和诊断等关键用户流程。

## 文件概览

---

## 组件概览

| 组件 | 文件 | 用途 |
|------|------|------|
| `REPL` | `REPL.tsx` | 主交互界面，处理消息渲染、用户输入、工具调用 |
| `ResumeConversation` | `ResumeConversation.tsx` | 会话恢复选择器，加载历史会话 |
| `Doctor` | `Doctor.tsx` | 诊断界面，检查安装状态和环境配置 |
| `CrossProjectMessage` | `ResumeConversation.tsx`（内部函数） | 跨项目恢复提示，显示命令引导用户去正确的目录恢复 |
| `NoConversationsMessage` | `ResumeConversation.tsx`（内部函数） | 无历史会话时的空状态提示 |
| `DistTagsDisplay` | `Doctor.tsx`（本地函数，非导出） | 显示 npm 版本标签的异步组件 |
| `TranscriptModeFooter` | `REPL.tsx` | 消息模式下的底部状态栏，显示快捷键提示 |
| `TranscriptSearchBar` | `REPL.tsx` | 搜索导航栏，支持 `n/N` 跳转 |
| `AnimatedTerminalTitle` | `REPL.tsx` | 终端标题动画组件 |

---

## `Doctor` 组件

### Props

```typescript
type Props = {
  onDone: (result?: string, options?: { display?: CommandResultDisplay }) => void;
};
```

### 用途

在 CLI 启动时展示环境诊断信息，包括版本、路径、插件状态、MCP 配置、键盘绑定等。用户在诊断界面按确认键后调用 `onDone` 回调。

### 主要状态

| 状态 | 类型 | 用途 |
|------|------|------|
| `diagnostic` | `DiagnosticInfo \| null` | 安装诊断数据（版本、路径、包管理器等） |
| `agentInfo` | `AgentInfo \| null` | Agent 配置信息（活跃 Agent、目录路径） |
| `contextWarnings` | `ContextWarnings \| null` | 上下文相关警告 |
| `versionLockInfo` | `VersionLockInfo \| null` | 版本锁文件状态 |

### 辅助类型

```typescript
type AgentInfo = {
  activeAgents: Array<{
    agentType: string;
    source: SettingSource | 'built-in' | 'plugin';
  }>;
  userAgentsDir: string;
  projectAgentsDir: string;
  userDirExists: boolean;
  projectDirExists: boolean;
  failedFiles?: Array<{ path: string; error: string }>;
};

type VersionLockInfo = {
  enabled: boolean;
  locks: LockInfo[];
  locksDir: string;
  staleLocksCleaned: number;
};
```

### 事件处理

- **键盘处理**：注册 `confirm:yes` 和 `confirm:no` 两个快捷键，均触发 `handleDismiss` 回调，退出诊断界面
- **异步初始化**：通过 `useEffect` 触发 `getDoctorDiagnostic()` 获取诊断数据，同时并行检查 Agent 目录和上下文警告
- **版本锁清理**：检测 PID-based locking 是否启用，启用时清理过期锁文件

### 渲染逻辑

1. `diagnostic` 未加载完成时显示 loading 提示
2. 依次渲染安装信息（版本、包管理器、路径、调用二进制）
3. 渲染 Agent 配置区域（有 `SandboxDoctorSection`、`McpParsingWarnings`、`KeybindingWarnings` 等子组件）
4. 环境变量校验错误列表
5. 版本锁状态（如果启用）
6. 底部显示 `PressEnterToContinue` 提示（从 `../components/PressEnterToContinue.js` 导入）

---

## `ResumeConversation` 组件

### Props

```typescript
type Props = {
  commands: Command[];
  worktreePaths: string[];
  initialTools: Tool[];
  mcpClients?: MCPServerConnection[];
  dynamicMcpConfig?: Record<string, ScopedMcpServerConfig>;
  debug: boolean;
  mainThreadAgentDefinition?: AgentDefinition;
  autoConnectIdeFlag?: boolean;
  strictMcpConfig?: boolean;
  systemPrompt?: string;
  appendSystemPrompt?: string;
  initialSearchQuery?: string;
  disableSlashCommands?: boolean;
  forkSession?: boolean;
  taskListId?: string;
  filterByPr?: boolean | number | string;
  thinkingConfig: ThinkingConfig;
};
```

### 用途

会话恢复入口，提供历史会话列表供用户选择。加载并解析会话日志，支持按 PR 筛选，检测跨项目恢复场景。

### 主要状态

| 状态 | 类型 | 用途 |
|------|------|------|
| `logs` | `LogOption[]` | 加载的会话日志列表 |
| `loading` | `boolean` | 是否正在加载日志 |
| `resuming` | `boolean` | 是否正在恢复某个会话 |
| `showAllProjects` | `boolean` | 是否显示所有项目的会话 |
| `resumeData` | `{ messages, fileHistorySnapshots, ... } \| null` | 选中的会话数据，加载后传给 REPL |
| `crossProjectCommand` | `string \| null` | 跨项目场景下显示的引导命令 |

### 内部函数

| 函数 | 用途 |
|------|------|
| `onSelect(log)` | 用户选中某个会话后触发，加载会话数据并准备切换到 REPL（内部实现） |
| `onCancel()` | 用户取消时 `process.exit(1)`（内部实现） |
| `handleToggleAllProjects()` | 切换 `showAllProjects` 并重新加载日志（内部实现） |
| `loadMoreLogs(count)` | 分页加载更多日志条目（内部实现） |

### 会话选择流程 (`onSelect`)

1. 检查是否是跨项目恢复场景
2. 如果是跨项目且非同 repo worktree，将命令复制到剪贴板并显示 `CrossProjectMessage`
3. 调用 `loadConversationForResume()` 加载会话数据
4. 如果是协调器模式，检查会话模式匹配并发出警告
5. 切换 session ID、更新 AppState 中的 agent 定义
6. 恢复工作树状态、文件历史快照、内容替换记录
7. 设置 `resumeData`，触发 REPL 渲染

### 渲染条件

| 条件 | 渲染内容 |
|------|----------|
| `crossProjectCommand` 非空 | `CrossProjectMessage` |
| `resumeData` 非空 | `REPL` 组件 |
| `loading` 为 true | Spinner + "Loading conversations..." |
| `resuming` 为 true | Spinner + "Resuming conversation..." |
| 无日志条目 | `NoConversationsMessage` |
| 默认 | `LogSelector` 会话列表 |

### `CrossProjectMessage` 组件

```typescript
function CrossProjectMessage({ command }: { command: string }): React.ReactNode
```

提示用户当前对话来自不同目录，并显示需要在对应目录执行的恢复命令。组件挂载 100ms 后自动 `process.exit(0)`。

### `NoConversationsMessage` 组件

无历史会话时显示的空状态，提示用户按 `Ctrl+C` 退出并开始新对话。

---

## `REPL` 组件

### Props

```typescript
export type Props = {
  commands: Command[];
  debug: boolean;
  initialTools: Tool[];
  initialMessages?: MessageType[];
  pendingHookMessages?: Promise<HookResultMessage[]>;
  initialFileHistorySnapshots?: FileHistorySnapshot[];
  initialContentReplacements?: ContentReplacementRecord[];
  initialAgentName?: string;
  initialAgentColor?: AgentColorName;
  mcpClients?: MCPServerConnection[];
  dynamicMcpConfig?: Record<string, ScopedMcpServerConfig>;
  autoConnectIdeFlag?: boolean;
  strictMcpConfig?: boolean;
  systemPrompt?: string;
  appendSystemPrompt?: string;
  onBeforeQuery?: (input: string, newMessages: MessageType[]) => Promise<boolean>;
  onTurnComplete?: (messages: MessageType[]) => void | Promise<void>;
  disabled?: boolean;
  mainThreadAgentDefinition?: AgentDefinition;
  disableSlashCommands?: boolean;
  taskListId?: string;
  remoteSessionConfig?: RemoteSessionConfig;
  directConnectConfig?: DirectConnectConfig;
  sshSession?: SSHSession;
  thinkingConfig: ThinkingConfig;
};

export type Screen = 'prompt' | 'transcript';
```

### 用途

主交互界面（Read-Eval-Print Loop），负责渲染消息列表、处理用户输入、调用工具、执行 AI 查询。是整个应用最核心的 UI 组件，文件体积较大（约 895KB）。

### 屏幕类型

```typescript
export type Screen = 'prompt' | 'transcript';
```

- **`prompt`**：默认视图，显示消息列表 + 输入框
- **`transcript`**：全屏消息浏览模式，隐藏输入框，支持滚动和搜索

### 主要状态

| 状态 | 类型 | 用途 |
|------|------|------|
| `screen` | `Screen` | 当前屏幕类型 |
| `showAllInTranscript` | `boolean` | 是否在 transcript 模式显示所有消息 |
| `dumpMode` | `boolean` | 转储模式，用于终端原生搜索 |
| `mainThreadAgentDefinition` | `AgentDefinition \| undefined` | 当前 Agent 定义（可动态更新） |
| `localCommands` | `Command[]` | 本地命令列表（热更新） |
| `dynamicMcpConfig` | `Record<string, ScopedMcpServerConfig>` | 动态 MCP 配置 |
| `ideSelection` | `IDESelection \| undefined` | IDE 当前选中文本 |
| `showIdeOnboarding` | `boolean` | 是否显示 IDE onboarding 对话框 |
| `showModelSwitchCallout` | `boolean` | 是否显示模型切换提示（仅 ant 构建） |
| `showEffortCallout` | `boolean` | 是否显示 effort 提示 |

### 状态管理

大量使用 `useAppState` 和 `useSetAppState` 与全局状态交互：

- `toolPermissionContext`：工具权限上下文
- `mcp`：MCP 服务器连接
- `plugins`：插件状态
- `agentDefinitions`：所有可用 Agent 定义
- `fileHistory`：文件历史记录
- `tasks`：任务列表
- `elicitation`：工具使用确认请求
- `teamContext`：团队协作上下文
- `viewingAgentTaskId`：当前查看的子 Agent 任务 ID

### 条件特性（编译时特性开关）

通过 `feature()` 编译时常量实现 dead code elimination：

| 特性 | 条件 | 用途 |
|------|------|------|
| `VOICE_MODE` | Feature flag | 语音集成 |
| `COORDINATOR_MODE` | Feature flag | 协调器多 Agent 模式 |
| `MESSAGE_ACTIONS` | Feature flag | 消息操作栏 |
| `CONTEXT_COLLAPSE` | Feature flag | 上下文折叠 |
| `PROACTIVE` / `KAIROS` | Feature flag | 主动模式 |
| `AGENT_TRIGGERS` | Feature flag | 定时任务 |
| `WEB_BROWSER_TOOL` | Feature flag | Web 浏览器工具 |
| Ant-only | `"external" === 'ant'` | 模型切换提示、沮丧检测、组织警告等 |

### 核心子组件

`REPL` 渲染时挂载了大量子组件和服务：

- **消息渲染**：`Messages`、`VirtualMessageList`
- **输入框**：`PromptInput`
- **任务列表**：`TaskListV2`
- **权限请求**：`PermissionRequest`
- **MCP 集成**：`ElicitationDialog`
- **反馈调查**：`FeedbackSurvey`
- **IDE 集成**：`IdeOnboardingDialog`
- **桌面升级提示**：`DesktopUpsellStartup`
- **伴侣精灵**：`CompanionSprite`

### 辅助组件

#### `TranscriptModeFooter`

在 transcript 模式下显示底部状态栏，动态显示切换快捷键和搜索导航信息。

#### `TranscriptSearchBar`

搜索导航栏组件，支持：
- 增量搜索高亮
- `n/N` 跳转下一个/上一个匹配
- 索引状态显示（`indexed in Xms`）
- 搜索结果计数

#### `AnimatedTerminalTitle`

纯副作用组件，负责更新终端标题。动画帧在独立组件中更新，避免触发整个 REPL 重新渲染。

---

## 模块间依赖关系

```
main.tsx
  ├── <Doctor />          启动诊断
  │     └── 完成后调用 onDone，进入 REPL 或 ResumeConversation
  ├── <ResumeConversation />  会话恢复选择
  │     ├── 加载 LogSelector
  │     ├── 用户选中 → <REPL /> + initialMessages
  │     └── 跨项目 → CrossProjectMessage
  └── <REPL />            主交互界面
        ├── Messages（消息列表）
        ├── PromptInput（输入框）
        ├── TaskListV2（任务列表）
        └── 各类 Dialog 和 Survey 组件
```

---

## 关键设计模式

### 1. 编译时特性开关

使用 `feature('FEATURE_NAME')` 和 `feature('EXPERIMENT') === 'ant'` 等编译时常量实现 tree-shaking，将 ant-only 或 experiment-only 的代码从外部构建中完全剔除。

### 2. 状态提升

`ResumeConversation` 在选中会话后，将 `initialMessages` 等数据作为 props 传给 `REPL`，而非通过全局状态传递，确保数据流清晰。

### 3. Ref 用于非渲染数据

如 `sessionLogResultRef` 和 `logCountRef` 用于存储不影响渲染但需要持久化的数据。

### 4. 条件 Hook 调用

部分 hook（如 `useVoiceIntegration`）仅在特定特性启用时调用，通过 `biome-ignore` 注释绕过 lint 规则。

### 5. AppState 全局状态

大量 UI 状态（IDE 选中文本、插件状态、MCP 连接）通过 `useAppState` 全局管理，而非 props层层传递。

### 6. 远程会话通过 Hook 访问

Screens 组件（如 `REPL`）需要远程会话功能时，应通过 `useRemoteSession` 或 `useDirectConnect` 等 Hook 获取，而非直接实例化 `RemoteSessionManager` 或 `DirectConnectSessionManager`。这些 Hook 内部封装了管理器的创建和生命周期管理，确保资源正确初始化和清理。
