# 根目录零散模块

本节文档覆盖项目根目录下不属于任何顶级目录的 5 个独立功能模块，各自实现特定功能：对话框启动器、交互式辅助函数、REPL 启动器、项目引导状态管理和费用摘要 Hook。

---

## dialogLaunchers.tsx — 对话框启动器集合

对话框启动器集合，负责动态导入并渲染各类对话框组件。每个启动器函数接收 `Root` 实例和相应参数，通过 `showSetupDialog` 或 `renderAndRun` 封装后解析 Promise。

### 导出函数

#### launchSnapshotUpdateDialog

触发 Agent 内存快照更新提示对话框。

```typescript
export async function launchSnapshotUpdateDialog(root: Root, props: {
  agentType: string;
  scope: AgentMemoryScope;
  snapshotTimestamp: string;
}): Promise<'merge' | 'keep' | 'replace'>
```

| 参数 | 类型 | 描述 |
|------|------|------|
| `root` | `Root` | Ink 根实例 |
| `props.agentType` | `string` | Agent 类型 |
| `props.scope` | `AgentMemoryScope` | 内存作用域 |
| `props.snapshotTimestamp` | `string` | 快照时间戳 |

**返回**: `'merge'` | `'keep'` | `'replace'` - 用户选择的操作

---

#### launchInvalidSettingsDialog

显示设置验证错误对话框。

```typescript
export async function launchInvalidSettingsDialog(root: Root, props: {
  settingsErrors: ValidationError[];
  onExit: () => void;
}): Promise<void>
```

| 参数 | 类型 | 描述 |
|------|------|------|
| `root` | `Root` | Ink 根实例 |
| `props.settingsErrors` | `ValidationError[]` | 验证错误列表 |
| `props.onExit` | `() => void` | 退出回调 |

---

#### launchAssistantSessionChooser

显示桥接会话选择器对话框。

```typescript
export async function launchAssistantSessionChooser(root: Root, props: {
  sessions: AssistantSession[];
}): Promise<string | null>
```

| 参数 | 类型 | 描述 |
|------|------|------|
| `root` | `Root` | Ink 根实例 |
| `props.sessions` | `AssistantSession[]` | 可用的助手会话列表 |

**返回**: 选中的会话 ID 或 `null`（用户取消）

---

#### launchAssistantInstallWizard

当 `claude assistant` 未找到任何会话时，显示安装向导对话框。

```typescript
export async function launchAssistantInstallWizard(root: Root): Promise<string | null>
```

**返回**: 安装目录路径或 `null`（取消）；安装失败时抛出错误

---

#### launchTeleportResumeWrapper

显示交互式 teleport 会话选择器。

```typescript
export async function launchTeleportResumeWrapper(root: Root): Promise<TeleportRemoteResponse | null>
```

**返回**: Teleport 远程响应或 `null`（取消）

---

#### launchTeleportRepoMismatchDialog

显示本地仓库检出声择对话框（当远程仓库与本地不一致时）。

```typescript
export async function launchTeleportRepoMismatchDialog(root: Root, props: {
  targetRepo: string;
  initialPaths: string[];
}): Promise<string | null>
```

| 参数 | 类型 | 描述 |
|------|------|------|
| `root` | `Root` | Ink 根实例 |
| `props.targetRepo` | `string` | 目标仓库 |
| `props.initialPaths` | `string[]` | 初始路径列表 |

**返回**: 选中的本地路径或 `null`（取消）

---

#### launchResumeChooser

显示交互式会话恢复选择器。使用 `renderAndRun` 而非 `showSetupDialog`，包装在 `App` + `KeybindingSetup` 中。

```typescript
export async function launchResumeChooser(
  root: Root,
  appProps: {
    getFpsMetrics: () => FpsMetrics | undefined;
    stats: StatsStore;
    initialState: AppState;
  },
  worktreePathsPromise: Promise<string[]>,
  resumeProps: Omit<ResumeConversationProps, 'worktreePaths'>
): Promise<void>
```

| 参数 | 类型 | 描述 |
|------|------|------|
| `root` | `Root` | Ink 根实例 |
| `appProps` | `object` | 应用级 props（FPS 指标、状态存储、初始状态） |
| `worktreePathsPromise` | `Promise<string[]>` | 工作树路径 Promise |
| `resumeProps` | `Omit<ResumeConversationProps, 'worktreePaths'>` | ResumeConversation 组件的其余 props |

---

## interactiveHelpers.tsx — 交互式辅助函数集合

`interactiveHelpers.tsx` 是 CLI 交互流程的核心辅助模块，提供对话框渲染、退出消息、设置屏幕初始化和渲染上下文构建等功能。

### 导出函数

#### completeOnboarding

标记用户已完成首次引导流程。

```typescript
export function completeOnboarding(): void
```

**核心流程**:
1. 调用 `saveGlobalConfig` 更新配置
2. 设置 `hasCompletedOnboarding: true`
3. 记录 `lastOnboardingVersion` 为当前版本

---

#### showDialog

通用的对话框渲染函数，创建 Promise 并渲染 React 节点。

```typescript
export function showDialog<T = void>(
  root: Root,
  renderer: (done: (result: T) => void) => React.ReactNode
): Promise<T>
```

| 参数 | 类型 | 描述 |
|------|------|------|
| `root` | `Root` | Ink 根实例 |
| `renderer` | `(done) => React.ReactNode` | 接收 done 回调的渲染函数 |

**核心流程**:
1. 创建 Promise 并将 resolve 包装为 `done` 回调
2. 调用 `root.render(renderer(done))` 渲染组件
3. 用户操作后调用 `done(result)` 解析 Promise

---

#### exitWithError

渲染错误消息后退出程序（红色文本）。

```typescript
export async function exitWithError(
  root: Root,
  message: string,
  beforeExit?: () => Promise<void>
): Promise<never>
```

| 参数 | 类型 | 描述 |
|------|------|------|
| `root` | `Root` | Ink 根实例 |
| `message` | `string` | 错误消息 |
| `beforeExit` | `() => Promise<void>` | 退出前执行的异步回调（可选） |

**核心流程**:
1. 调用 `exitWithMessage` 并指定 `color: 'error'`
2. 渲染红色错误文本
3. 执行 `beforeExit` 回调（如有）
4. 调用 `process.exit(1)`

---

#### exitWithMessage

渲染消息后退出程序，支持颜色和退出码配置。

```typescript
export async function exitWithMessage(
  root: Root,
  message: string,
  options?: {
    color?: TextProps['color'];
    exitCode?: number;
    beforeExit?: () => Promise<void>;
  }
): Promise<never>
```

| 参数 | 类型 | 描述 |
|------|------|------|
| `root` | `Root` | Ink 根实例 |
| `message` | `string` | 消息文本 |
| `options.color` | `string` | 文本颜色（如 `'error'`、`'warning'`） |
| `options.exitCode` | `number` | 退出码，默认为 `1` |
| `options.beforeExit` | `() => Promise<void>` | 退出前执行的异步回调 |

**核心流程**:
1. 动态导入 `Text` 组件
2. 调用 `root.render` 渲染带颜色的文本
3. 调用 `root.unmount()` 卸载组件
4. 执行 `beforeExit` 回调（如有）
5. 调用 `process.exit(exitCode)`

---

#### showSetupDialog

显示包装在 `AppStateProvider` + `KeybindingSetup` 中的设置对话框。

```typescript
export function showSetupDialog<T = void>(
  root: Root,
  renderer: (done: (result: T) => void) => React.ReactNode,
  options?: {
    onChangeAppState?: typeof onChangeAppState;
  }
): Promise<T>
```

| 参数 | 类型 | 描述 |
|------|------|------|
| `root` | `Root` | Ink 根实例 |
| `renderer` | `(done) => React.ReactNode` | 对话框渲染函数 |
| `options.onChangeAppState` | `function` | 应用状态变更回调 |

**核心流程**:
1. 调用 `showDialog` 渲染
2. 包装 `AppStateProvider` 提供状态上下文
3. 包装 `KeybindingSetup` 提供键盘绑定

---

#### renderAndRun

渲染主 UI 并等待其退出。

```typescript
export async function renderAndRun(
  root: Root,
  element: React.ReactNode
): Promise<void>
```

| 参数 | 类型 | 描述 |
|------|------|------|
| `root` | `Root` | Ink 根实例 |
| `element` | `React.ReactNode` | 要渲染的 React 节点 |

**核心流程**:
1. 调用 `root.render(element)` 渲染元素
2. 调用 `startDeferredPrefetches()` 启动预取
3. 调用 `await root.waitUntilExit()` 等待退出
4. 调用 `await gracefulShutdown(0)` 优雅关闭

---

#### showSetupScreens

按顺序显示所有设置屏幕（引导、信任、自定义 API 密钥、权限模式等）。

```typescript
export async function showSetupScreens(
  root: Root,
  permissionMode: PermissionMode,
  allowDangerouslySkipPermissions: boolean,
  commands?: Command[],
  claudeInChrome?: boolean,
  devChannels?: ChannelEntry[]
): Promise<boolean>
```

| 参数 | 类型 | 描述 |
|------|------|------|
| `root` | `Root` | Ink 根实例 |
| `permissionMode` | `PermissionMode` | 权限模式 |
| `allowDangerouslySkipPermissions` | `boolean` | 是否允许跳过权限提示 |
| `commands` | `Command[]` | 可用命令列表 |
| `claudeInChrome` | `boolean` | 是否为 Chrome 版本 |
| `devChannels` | `ChannelEntry[]` | 开发通道列表 |

**返回**: `boolean` - 是否显示了引导界面

**核心流程**:

1. **跳过条件**：测试环境（`"production" === 'test'`）、`IS_DEMO` 模式直接返回 false
2. **首次引导**：若无主题设置或未完成引导，显示 `Onboarding` 对话框，标记 `onboardingShown = true`
3. **信任对话框**（非 `CLAUBBIT` 环境）：若 `checkHasTrustDialogAccepted()` 返回 false，显示 `TrustDialog`
   - 验证后调用 `setSessionTrustAccepted(true)` 并重置 GrowthBook
   - 信任建立后调用 `getSystemContext()` 预取系统上下文
4. **MCP 服务器审批**：若设置无错误（`allErrors.length === 0`），调用 `handleMcpjsonServerApprovals(root)`
5. **CLAUDE.md 外部引用警告**：若存在外部引用需审批，显示 `ClaudeMdExternalIncludesDialog`
6. **GitHub Repo 路径映射**：信任后调用 `updateGithubRepoPathMapping()`（fire-and-forget）
7. **深度链接终端偏好**：`LODESTONE` 特性开启时调用 `updateDeepLinkTerminalPreference()`
8. **环境变量应用**：信任对话框接受后调用 `applyConfigEnvironmentVariables()`
9. **遥测初始化**：`setImmediate(() => initializeTelemetryAfterTrust())` 延迟初始化
10. **Grove 策略**：若 `isQualifiedForGrove()` 返回 true，显示 `GroveDialog`；用户选择 `escape` 则直接 `gracefulShutdownSync(0)` 退出
11. **自定义 API Key**：若设置了 `ANTHROPIC_API_KEY` 且不在 Homespace，`keyStatus === 'new'` 时显示 `ApproveApiKey`
12. **Bypass 权限模式**：`permissionMode === 'bypassPermissions' || allowDangerouslySkipPermissions` 时显示 `BypassPermissionsModeDialog`
13. **Auto Mode opt-in**：`TRANSCRIPT_CLASSIFIER` 开启、权限模式为 `auto`、且未 opt-in 时显示 `AutoModeOptInDialog`
14. **Dev Channels**：`KAIROS` 或 `KAIROS_CHANNELS` 开启且 `devChannels` 非空时，显示 `DevChannelsDialog` 并更新通道列表
15. **Claude in Chrome 引导**：首次使用 Chrome 版本时显示 `ClaudeInChromeOnboarding`

---

#### getRenderContext

获取渲染上下文（渲染选项、FPS 指标、状态存储）。

```typescript
export function getRenderContext(exitOnCtrlC: boolean): {
  renderOptions: RenderOptions;
  getFpsMetrics: () => FpsMetrics | undefined;
  stats: StatsStore;
}
```

| 参数 | 类型 | 描述 |
|------|------|------|
| `exitOnCtrlC` | `boolean` | 是否在 Ctrl+C 时退出 |

**返回对象**:
| 字段 | 类型 | 描述 |
|------|------|------|
| `renderOptions` | `RenderOptions` | Ink 渲染选项 |
| `getFpsMetrics` | `() => FpsMetrics \| undefined` | 获取 FPS 指标的函数 |
| `stats` | `StatsStore` | 统计状态存储 |

**Bench 模式**

`CLAUDE_CODE_FRAME_TIMING_LOG` 环境变量设为文件路径时，每帧追加一行 JSONL（同步写入，确保异常退出时不丢帧）：

```json
{"total": 16.5, "yoga": 2.1, "screen": 1.2, "diff": 0.8, "optimize": 0.3, "stdout": 12.1, "rss": 50000000, "cpu": {"user": 100000, "system": 20000}}
```

**onFrame 回调特性**

- 跳过同步输出支持的终端的 flicker 上报（DEC 2026 协议保证原子性）
- 其余终端每秒最多上报一次 flicker 事件（通过 `lastFlickerTime` 节流）
- stdin override 激活时记录 `tengu_stdin_interactive` 分析事件

**核心流程**:
1. 调用 `getBaseRenderOptions(exitOnCtrlC)` 获取基础选项
2. 若启用 stdin override，记录 `tengu_stdin_interactive` 分析事件
3. 创建 `FpsTracker` 实例用于帧率跟踪
4. 创建 `StatsStore` 实例并调用 `setStatsStore(stats)` 设为全局
5. 配置 `onFrame` 回调：
   - `fpsTracker.record(event.durationMs)` 记录帧时长
   - `stats.observe('frame_duration_ms', event.durationMs)` 写入 Stats Store
   - 若设置 `CLAUDE_CODE_FRAME_TIMING_LOG`，同步追加 JSONL
   - flicker 检测与节流上报
6. 返回 `{ renderOptions, getFpsMetrics, stats }`

---

## replLauncher.tsx — REPL 主界面动态启动

`replLauncher.tsx` 是 REPL 主界面的动态启动函数，将 REPL 组件挂载到 Ink 根节点。

### 导出函数

#### launchRepl

启动 REPL 主界面。

```typescript
export async function launchRepl(
  root: Root,
  appProps: AppWrapperProps,
  replProps: REPLProps,
  renderAndRun: (root: Root, element: React.ReactNode) => Promise<void>
): Promise<void>
```

| 参数 | 类型 | 描述 |
|------|------|------|
| `root` | `Root` | Ink 根实例 |
| `appProps` | `AppWrapperProps` | 应用级 props |
| `replProps` | `REPLProps` | REPL 组件 props |
| `renderAndRun` | `(root, element) => Promise<void>` | 渲染并运行函数 |

**AppWrapperProps 类型**:
```typescript
type AppWrapperProps = {
  getFpsMetrics: () => FpsMetrics | undefined;
  stats?: StatsStore;
  initialState: AppState;
};
```

**核心流程**:
1. 动态导入 `App` 组件
2. 动态导入 `REPL` 组件
3. 调用 `renderAndRun` 渲染 `<App><REPL {...replProps} /></App>`

---

## projectOnboardingState.ts — 项目引导状态管理

`projectOnboardingState.ts` 管理新项目创建或克隆后的引导流程状态，判断是否需要显示项目引导 UI。

### 导出类型

#### Step

引导步骤类型定义。

```typescript
export type Step = {
  key: string;
  text: string;
  isComplete: boolean;
  isCompletable: boolean;
  isEnabled: boolean;
}
```

| 字段 | 类型 | 描述 |
|------|------|------|
| `key` | `string` | 步骤唯一标识符 |
| `text` | `string` | 步骤描述文本 |
| `isComplete` | `boolean` | 步骤是否已完成 |
| `isCompletable` | `boolean` | 步骤是否可完成 |
| `isEnabled` | `boolean` | 步骤是否启用 |

### 导出函数

#### getSteps

获取当前项目的引导步骤列表。

```typescript
export function getSteps(): Step[]
```

**返回**: `Step[]` - 引导步骤数组

**核心流程**:
1. 调用 `getFsImplementation().existsSync(join(getCwd(), 'CLAUDE.md'))` 检测 `CLAUDE.md` 是否存在
2. 调用 `isDirEmpty(getCwd())` 检测工作区是否为空
3. 返回两个步骤定义：
   - `workspace`：`isEnabled = isWorkspaceDirEmpty`，工作区为空时让用户创建新应用或克隆仓库（不可直接完成）
   - `claudemd`：`isEnabled = !isWorkspaceDirEmpty`，提示运行 `/init` 创建 CLAUDE.md（文件存在时 `isComplete = true`）

---

#### isProjectOnboardingComplete

判断项目引导是否完成。

```typescript
export function isProjectOnboardingComplete(): boolean
```

**返回**: `boolean` - 所有可完成且已启用的步骤是否都已完成

**核心流程**:
1. 调用 `getSteps()` 获取步骤列表
2. 筛选 `isCompletable && isEnabled` 的步骤
3. 检查所有筛选步骤的 `isComplete` 是否都为 `true`

---

#### maybeMarkProjectOnboardingComplete

若项目引导已完成，标记为完成状态。

```typescript
export function maybeMarkProjectOnboardingComplete(): void
```

**核心流程**:

1. **短路检查**：若缓存的 `getCurrentProjectConfig().hasCompletedProjectOnboarding === true`，直接返回（避免文件系统访问）
2. 调用 `isProjectOnboardingComplete()` 判断
3. 若完成，调用 `saveCurrentProjectConfig` 将 `hasCompletedProjectOnboarding: true` 写入配置

---

#### shouldShowProjectOnboarding

判断是否应显示项目引导提示（带记忆化）。

```typescript
export const shouldShowProjectOnboarding = memoize((): boolean => {
  const projectConfig = getCurrentProjectConfig()
  // ...
})
```

**返回**: `boolean` - 是否应显示引导（已 memoized）

**显示条件**（全部满足才返回 true）：

- `hasCompletedProjectOnboarding` 为 false
- `projectOnboardingSeenCount` < 4
- 非 `IS_DEMO` 模式
- `!isProjectOnboardingComplete()`（存在未完成的引导步骤）

短路逻辑：先读缓存配置，避免调用 `isProjectOnboardingComplete()` 时的文件系统访问。

---

#### incrementProjectOnboardingSeenCount

增加项目引导已显示次数。

```typescript
export function incrementProjectOnboardingSeenCount(): void
```

**核心流程**:
1. 调用 `saveCurrentProjectConfig`
2. 增加 `projectOnboardingSeenCount` 字段值

---

## costHook.ts — 费用摘要 Hook

`costHook.ts` 提供了一个 React Hook，在进程退出时输出当前会话的费用摘要，并将费用数据持久化。

### 导出函数

#### useCostSummary

React Hook，在组件卸载时输出成本摘要。

```typescript
export function useCostSummary(
  getFpsMetrics?: () => FpsMetrics | undefined,
): void
```

| 参数 | 类型 | 描述 |
|------|------|------|
| `getFpsMetrics` | `() => FpsMetrics \| undefined` | 获取 FPS 指标的函数（可选） |

**核心流程**:
1. 在 `useEffect` 中注册进程 `exit` 事件监听器
2. 退出时执行回调函数 `f`:
   - 若用户有控制台计费访问权限，调用 `formatTotalCost()` 输出成本摘要到 stdout
   - 调用 `saveCurrentSessionCosts(getFpsMetrics?.())` 保存当前会话成本
3. 在清理函数中移除事件监听器

**使用场景**: 通常在 CLI 主组件的顶层调用，用于在会话结束时自动输出成本信息。
