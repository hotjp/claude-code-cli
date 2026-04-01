# Coordinator 模块 (coordinator/)

## 架构概览

Coordinator 模块是 Claude Code CLI 的多代理编排核心，使主会话（coordinator）能够通过 `Agent` 工具派生多个 worker 子代理，并借助 `SendMessage` 和 `TaskStop` 工具与它们通信、协调任务。

```
用户 → Coordinator（主会话） → Agent(spawn worker) → Worker（子代理）
                              ↳ SendMessage(continue worker)
                              ↳ TaskStop(stop worker)
```

### 核心接口

- **`isCoordinatorMode(): boolean`** — 判断当前会话是否处于 coordinator 模式（通过 `COORDINATOR_MODE` 特性门控 + `CLAUDE_CODE_COORDINATOR_MODE` 环境变量）
- **`matchSessionMode(sessionMode): string | undefined`** — 恢复会话时同步 coordinator 模式状态，返回模式切换提示（如有）
- **`getCoordinatorUserContext(mcpClients, scratchpadDir?): Record<string, string>`** — 生成注入到系统提示的 worker 工具上下文
- **`getCoordinatorSystemPrompt(): string`** — 返回完整的 coordinator 系统提示（角色定义、任务流程、Worker 提示编写规范）

### Coordinator 模式特性

- 通过 `CLAUDE_CODE_COORDINATOR_MODE=1` 环境变量激活
- 由 `COORDINATOR_MODE` 特性门控（Statsig）控制功能可见性
- 支持会话恢复时自动切换模式（`matchSessionMode`）
- 提供 scratchpad 目录支持跨 worker 持久化知识共享

### Worker 管理机制

- Worker 通过 `Agent` 工具的 `subagent_type: "worker"` 派生
- Coordinator 通过 `SendMessage` 继续已有 worker（复用上下文）或通过 `Agent` 启动新 worker
- `TaskStop` 用于停止方向错误的 worker
- Worker 结果以 `<task-notification>` XML 标签形式投递到 coordinator 会话

---

## 文件系统

### coordinatorMode.ts

**用途**: Coordinator 模式的核心实现，封装所有协调逻辑和系统提示生成。

- **文件**: `coordinator/coordinatorMode.ts`

**导出成员**:
| 名称 | 类型 | 说明 |
|------|------|------|
| `INTERNAL_WORKER_TOOLS` | `Set<string>` | 对 worker 隐藏的内部工具（TeamCreate, TeamDelete, SendMessage, SyntheticOutput） |
| `isCoordinatorMode()` | `() => boolean` | 判断 coordinator 模式是否激活 |
| `matchSessionMode()` | `(sessionMode) => string \| undefined` | 同步会话模式状态，返回切换提示 |
| `getCoordinatorUserContext()` | `(mcpClients, scratchpadDir?) => Record<string, string>` | 生成 worker 工具上下文 |
| `getCoordinatorSystemPrompt()` | `() => string` | 生成完整 coordinator 系统提示 |

**内部函数**:
- `isScratchpadGateEnabled()` — 检查 scratchpad 功能门控（`tengu_scratch` Statsig gate）

---

## 核心函数详解

### isCoordinatorMode

**用途**: 判断当前会话是否运行在 coordinator 模式。

```typescript
export function isCoordinatorMode(): boolean
```

**逻辑**:
1. 检查 `COORDINATOR_MODE` bundle 特性是否启用
2. 如启用，读取 `CLAUDE_CODE_COORDINATOR_MODE` 环境变量
3. 如未启用，直接返回 `false`

**调用方**: `QueryEngine`、会话状态管理、CLI 入口层。

---

### matchSessionMode

**用途**: 恢复会话时同步 coordinator 模式状态，解决会话存储模式与当前环境不一致的问题。

```typescript
export function matchSessionMode(
  sessionMode: 'coordinator' | 'normal' | undefined,
): string | undefined
```

**参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| `sessionMode` | `'coordinator' \| 'normal' \| undefined` | 会话中存储的模式 |

**逻辑**:
1. 无存储模式（旧会话）— 直接返回 `undefined`
2. 当前模式与会话模式一致 — 返回 `undefined`
3. 不一致时：设置或删除 `CLAUDE_CODE_COORDINATOR_MODE` 环境变量
4. 发送 `tengu_coordinator_mode_switched` 分析事件
5. 返回切换提示语

**返回**: 模式切换警告消息，或 `undefined`（无需切换）

---

### getCoordinatorUserContext

**用途**: 生成注入到系统提示的 worker 工具上下文信息。

```typescript
export function getCoordinatorUserContext(
  mcpClients: ReadonlyArray<{ name: string }>,
  scratchpadDir?: string,
): { [k: string]: string }
```

**参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| `mcpClients` | `ReadonlyArray<{ name: string }>` | 已连接的 MCP 服务器列表 |
| `scratchpadDir` | `string` (可选) | Scratchpad 目录路径 |

**返回键**: `workerToolsContext` — 包含 worker 可用工具列表的字符串

**逻辑**:
1. 非 coordinator 模式返回空对象
2. `CLAUDE_CODE_SIMPLE` 模式：仅提供 `Bash`、`Read`、`Edit` 工具
3. 标准模式：使用 `ASYNC_AGENT_ALLOWED_TOOLS` 完整列表，排除内部工具（`TEAM_CREATE`、`TEAM_DELETE`、`SEND_MESSAGE`、`SYNTHETIC_OUTPUT`）
4. 追加 MCP 服务器工具上下文（如已连接）
5. 如启用了 scratchpad 特性门控（`tengu_scratch`），追加 scratchpad 目录信息

---

### getCoordinatorSystemPrompt

**用途**: 返回完整的 coordinator 系统提示，定义协调者行为规范。

```typescript
export function getCoordinatorSystemPrompt(): string
```

**系统提示结构**:

| 章节 | 内容 |
|------|------|
| **1. Your Role** | Coordinator 职责定义：帮助用户达成目标、指导 worker、汇总结果 |
| **2. Your Tools** | `Agent`（启动 worker）、`SendMessage`（继续 worker）、`TaskStop`（停止 worker）使用规范 |
| **3. Workers** | Worker 的工具池定义（取决于 `CLAUDE_CODE_SIMPLE` 模式） |
| **4. Task Workflow** | 四阶段工作流：Research → Synthesis → Implementation → Verification |
| **5. Writing Worker Prompts** | 如何撰写高质量的 worker 提示词 |
| **6. Example Session** | 完整的 coordinator 会话示例 |

**关键行为规范**:
- Worker 结果以 `<task-notification>` XML 格式到达
- 使用 `subagent_type: "worker"` 启动 worker
- 优先并行启动独立任务
- 始终综合（synthesize）worker 研究结果后再指导实现
- 使用 `SendMessage` 继续同一 worker，使用 `Agent` 启动新 worker

---

## Worker 工具池

Coordinator 根据 `CLAUDE_CODE_SIMPLE` 环境变量决定暴露给 worker 的工具集：

| 模式 | 工具集 |
|------|--------|
| `CLAUDE_CODE_SIMPLE=1` | Bash, Read, Edit（精简集） |
| 默认 | `ASYNC_AGENT_ALLOWED_TOOLS` 减去 `INTERNAL_WORKER_TOOLS` |

### INTERNAL_WORKER_TOOLS

```typescript
const INTERNAL_WORKER_TOOLS = new Set([
  TEAM_CREATE_TOOL_NAME,
  TEAM_DELETE_TOOL_NAME,
  SEND_MESSAGE_TOOL_NAME,
  SYNTHETIC_OUTPUT_TOOL_NAME,
])
```

**用途**: 仅供 coordinator 内部使用的工具集，从 worker 工具列表中排除。这些工具控制团队生命周期管理，不应暴露给 worker。

### 标准模式 worker 工具列表

以下是 `ASYNC_AGENT_ALLOWED_TOOLS` 中的工具常量名称（并非人类可读名称）：

```
FILE_READ_TOOL_NAME, WEB_SEARCH_TOOL_NAME, TODO_WRITE_TOOL_NAME, GREP_TOOL_NAME,
WEB_FETCH_TOOL_NAME, GLOB_TOOL_NAME, BASH_TOOL_NAME, POWERSHELL_TOOL_NAME,
FILE_EDIT_TOOL_NAME, FILE_WRITE_TOOL_NAME, NOTEBOOK_EDIT_TOOL_NAME,
SKILL_TOOL_NAME, SYNTHETIC_OUTPUT_TOOL_NAME, TOOL_SEARCH_TOOL_NAME,
ENTER_WORKTREE_TOOL_NAME, EXIT_WORKTREE_TOOL_NAME
```

**注意**: async agent 实际获得的工具列表为 `ASYNC_AGENT_ALLOWED_TOOLS` 减去 `INTERNAL_WORKER_TOOLS`（即 `TEAM_CREATE_TOOL_NAME`、`TEAM_DELETE_TOOL_NAME`、`SEND_MESSAGE_TOOL_NAME`、`SYNTHETIC_OUTPUT_TOOL_NAME`）。

---

## 协作流程

### 任务分派阶段

1. Coordinator 分析任务，拆分为独立研究单元
2. 并发启动多个 `Agent(subagent_type: "worker")` 进行研究
3. 向用户报告启动的工作项

### 结果聚合阶段

1. Worker 结果以 `<task-notification>` 消息投递
2. Coordinator 解析结果，综合理解问题
3. 撰写自包含的实现规范（文件路径、行号、具体修改内容）

### 执行阶段

| 场景 | 机制 | 原因 |
|------|------|------|
| 研究文件 = 实现文件 | `SendMessage` 继续 | Worker 已有文件上下文 |
| 研究广泛，实现狭窄 | `Agent` 新建 | 避免探索噪声带入实现 |
| 修正失败 | `SendMessage` 继续 | Worker 有错误上下文 |
| 验证他人代码 | `Agent` 新建 | 验证者应独立审视 |
| 完全不相关 | `Agent` 新建 | 无可复用上下文 |

### 验证标准

- 测试需在功能启用状态下运行
- 类型错误需逐一调查，不能忽略
- 主动怀疑可疑之处
- 独立证明变更有效，不替实现 worker 背书

---

## Scratchpad 目录

Scratchpad 是 worker 间共享知识的持久化目录，通过 `tengu_scratch` Statsig 特性门控启用。

**条件**:
- Coordinator 模式已启用
- 提供了 `scratchpadDir` 参数
- `tengu_scratch` 特性门控返回 true

**注入内容**: `Scratchpad directory: <path>\nWorkers can read and write here without permission prompts. Use this for durable cross-worker knowledge — structure files however fits the work.`

---

## 核心类型

```typescript
// 会话模式
type SessionMode = 'coordinator' | 'normal' | undefined

// Worker 通知格式 (XML)
interface TaskNotification {
  'task_id': string                     // Agent ID，用于 SendMessage(to: <task_id>)
  'tool_use_id'?: string                // 可选，工具使用 ID
  'output_file': string                 // 输出文件路径
  'status': 'completed' | 'failed' | 'stopped'  // 任务状态
  'usage'?: {                           // 可选，使用统计
    'total_tokens': number
    'tool_uses': number
    'duration_ms': number
  }
  'summary': string                    // 可读状态摘要，格式：Task "{description}" {statusText}
}
```

---

## 环境变量

| 变量 | 说明 |
|------|------|
| `CLAUDE_CODE_COORDINATOR_MODE` | 设为 `1` 激活 coordinator 模式 |
| `CLAUDE_CODE_SIMPLE` | 设为 `1` 使用精简 worker 工具集（Bash/Read/Edit） |

---

## 与其他模块的关系

- **依赖 `constants/tools.ts`** — `ASYNC_AGENT_ALLOWED_TOOLS` 定义 worker 工具列表
- **依赖 `services/analytics`** — 发送 `tengu_coordinator_mode_switched` 分析事件
- **依赖 `tools/AgentTool`** — `AGENT_TOOL_NAME` 常量
- **依赖 `tools/SendMessageTool`** — `SEND_MESSAGE_TOOL_NAME` 常量
- **依赖 `tools/TaskStopTool`** — `TASK_STOP_TOOL_NAME` 常量
- **被 `QueryEngine` 调用** — 模式检测和系统提示注入

---

## 文件索引

| 文件 | 用途 |
|------|------|
| `coordinatorMode.ts` | 单一文件，包含所有 coordinator 模式逻辑：模式检测、会话同步、上下文构建、系统提示生成 |
