# 命令系统 (commands/)

## 概述

Claude Code 的命令系统支持用户通过 `/command-name` 斜杠命令在交互式 REPL 中执行各种操作。所有命令位于 `commands/` 目录下，每个子目录（或独立 `.ts` 文件）代表一个命令模块。

### 命令类型

命令系统定义了三种命令类型：

| 类型 | 说明 |
|------|------|
| **`prompt`** | 提示型命令。通过 `getPromptForCommand()` 动态生成 prompt 内容，作为用户消息发送给 AI 模型执行。适用于需要 AI 推理能力的任务（如代码审查、提交生成）。 |
| **`local`** | 本地命令。通过 `load()` 延迟加载 `call()` 函数，直接在本地执行逻辑并返回文本结果。适用于纯客户端操作（如显示信息、切换状态）。支持 `supportsNonInteractive` 标志以兼容非交互模式。 |
| **`local-jsx`** | 本地 JSX 命令。类似 `local`，但 `call()` 函数可以返回 React 组件树，用于渲染交互式 UI 界面（如选择面板、配置对话框）。 |

### 命令注册机制

每个命令通过 `export default` 导出一个满足 `Command` 类型约束的对象（使用 `satisfies Command`）。核心字段包括：

- **`name`**: 命令名称（不含 `/` 前缀）
- **`description`**: 命令描述（显示在帮助和自动补全中）
- **`type`**: 命令类型（`prompt` | `local` | `local-jsx`）
- **`load`**: 延迟加载函数，返回命令实现模块
- **`aliases`**: 可选别名列表
- **`isEnabled`**: 可选启用条件函数（基于 feature flag、环境变量等）
- **`isHidden`**: 是否在帮助中隐藏
- **`argumentHint`**: 参数提示文本
- **`immediate`**: 是否立即执行（不等待队列中的停止点）
- **`supportsNonInteractive`**: 是否支持非交互模式（仅 `local` 类型）
- **`availability`**: 可用性限制（`claude-ai` 订阅者 / `console` API 密钥用户）

### 已废弃/存根命令

以下命令当前已禁用（`isEnabled: () => false`），仅作为存根存在：

`ant-trace`、`autofix-pr`、`backfill-sessions`、`break-cache`、`bughunter`、`ctx_viz`、`debug-tool-call`、`env`、`good-claude`、`issue`、`mock-limits`、`oauth-refresh`、`onboarding`、`perf-issue`、`reset-limits`、`share`、`summary`、`teleport`

---

## 一、Git 管理

### /commit

| 属性 | 值 |
|------|-----|
| **类型** | `prompt` |
| **描述** | 创建 git commit |
| **参数** | 无（自动分析暂存区变更） |
| **非交互** | 不适用（prompt 类型） |
| **来源** | `commands/commit.ts` |

**核心功能**：分析当前 `git status`、`git diff HEAD`、`git log` 和当前分支信息，自动生成提交信息。遵循 Git 安全协议：禁止更新 git config、禁止跳过 hooks、禁止 `--amend`、禁止提交含密钥文件。仅允许 `Bash(git add:*)`、`Bash(git status:*)`、`Bash(git commit:*)` 工具。

---

### /commit-push-pr

| 属性 | 值 |
|------|-----|
| **类型** | `prompt` |
| **描述** | 提交代码、推送并创建 Pull Request |
| **参数** | 可选附加指令 |
| **非交互** | 不适用（prompt 类型） |
| **来源** | `commands/commit-push-pr.ts` |

**核心功能**：在 `/commit` 基础上扩展，完整流程包括：自动创建分支（使用 SAFEUSER 前缀）、提交代码、推送到远端、创建或更新 PR。支持 attribution 文本和 changelog 区块。允许的额外工具包括 `gh pr create/edit/view/merge`。若 PR 已存在则更新标题和描述。

---

### /review

| 属性 | 值 |
|------|-----|
| **类型** | `prompt` |
| **描述** | 审查 Pull Request |
| **参数** | `[PR 编号或空]` |
| **非交互** | 不适用（prompt 类型） |
| **来源** | `commands/review.ts` |

**核心功能**：若未提供 PR 编号则列出开放的 PR；若提供了编号，使用 `gh pr view` 和 `gh pr diff` 获取详情和 diff，然后进行全面的代码审查，包括代码正确性、项目规范遵循、性能影响、测试覆盖和安全考虑。

---

### /ultrareview

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | Finds and verifies bugs in your branch. Runs in Claude Code on the web. |
| **来源** | `commands/review.ts` → `review/ultrareviewCommand.tsx` |
| **启用条件** | `isUltrareviewEnabled()` |

**核心功能**：远程执行深度代码审查，通过 CCR（Claude Code on the web）运行。当免费额度用完时弹出超额权限对话框。

---

### /security-review

| 属性 | 值 |
|------|-----|
| **类型** | `prompt`（已迁移至 plugin） |
| **描述** | 对当前分支的待提交变更执行安全审查 |
| **来源** | `commands/security-review.ts` |
| **工具权限** | `Bash(git diff:*)`、`Bash(git status:*)`、`Bash(git log:*)`、`Bash(git show:*)`、`Bash(git remote show:*)`、`Read`、`Glob`、`Grep`、`LS`、`Task` |

**核心功能**：作为高级安全工程师执行聚焦安全审查。分三阶段进行：仓库上下文研究、对比分析、漏洞评估。仅报告高置信度（>80%）的可利用漏洞，并排除 DoS、磁盘密钥存储、速率限制等低影响发现。

---

### /diff

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 查看未提交的变更和每轮对话的 diff |
| **来源** | `commands/diff/index.ts` |

**核心功能**：展示当前工作区的未提交变更，以及每个对话轮次产生的文件差异对比。

---

### /branch

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 在当前对话节点创建分支 |
| **参数** | `[name]` |
| **别名** | `fork`（当 FORK_SUBAGENT feature 未启用时） |
| **来源** | `commands/branch/index.ts` |

**核心功能**：在对话历史中的当前节点创建一个分支，允许用户在不影响主对话的情况下探索不同方向。

---

## 二、会话管理

### /clear

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 清除对话历史并释放上下文 |
| **别名** | `reset`、`new` |
| **非交互** | 不支持 |
| **来源** | `commands/clear/index.ts` |

**核心功能**：完全清除当前对话历史，释放上下文窗口空间，相当于开始一个全新会话。

---

### /compact

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 清除对话历史但保留摘要到上下文中 |
| **参数** | `<可选的自定义摘要指令>` |
| **非交互** | 支持 |
| **启用条件** | 未设置 `DISABLE_COMPACT` 环境变量 |
| **来源** | `commands/compact/index.ts` |

**核心功能**：对长对话进行压缩。AI 先生成对话摘要，然后清除原始历史但保留摘要，使上下文窗口得到释放同时不丢失关键信息。用户可提供自定义指令控制摘要方式。

---

### /resume

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 恢复之前的对话 |
| **参数** | `[对话 ID 或搜索词]` |
| **别名** | `continue` |
| **来源** | `commands/resume/index.ts` |

**核心功能**：列出历史对话并允许用户选择恢复一个之前的会话，继续之前的上下文和对话。

---

### /rewind

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 恢复代码和/或对话到之前的状态 |
| **别名** | `checkpoint` |
| **非交互** | 不支持 |
| **来源** | `commands/rewind/index.ts` |

**核心功能**：回溯对话和文件变更到一个先前的检查点，撤销后续的修改。

---

### /rename

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 重命名当前对话 |
| **参数** | `[name]` |
| **immediate** | 是 |
| **来源** | `commands/rename/index.ts` |

**核心功能**：为当前会话设置一个可读的名称，便于在历史列表中识别。

---

### /export

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 导出当前对话到文件或剪贴板 |
| **参数** | `[filename]` |
| **来源** | `commands/export/index.ts` |

**核心功能**：将对话内容导出为文件或复制到剪贴板，用于分享或存档。

---

### /tag

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 在当前会话上切换可搜索标签 |
| **参数** | `<tag-name>` |
| **启用条件** | `USER_TYPE === 'ant'` |
| **来源** | `commands/tag/index.ts` |

**核心功能**：为会话添加或移除标签，用于会话分类和搜索。仅内部用户可用。

---

## 三、配置设置

### /config

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 打开配置面板 |
| **别名** | `settings` |
| **来源** | `commands/config/index.ts` |

**核心功能**：打开交互式配置界面，可调整 Claude Code 的各项设置，包括输出风格、主题、模型选择等。

---

### /model

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 设置 AI 模型（显示当前使用的模型） |
| **参数** | `[model]` |
| **immediate** | 条件性（取决于 `shouldInferenceConfigCommandBeImmediate()`） |
| **来源** | `commands/model/index.ts` |

**核心功能**：查看或切换当前使用的 AI 模型。描述中动态显示当前模型名称。

---

### /effort

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 设置模型使用的努力级别 |
| **参数** | `[low\|medium\|high\|max\|auto]` |
| **immediate** | 条件性 |
| **来源** | `commands/effort/index.ts` |

**核心功能**：控制 AI 模型回答时的推理深度和详细程度。`low` 表示快速简答，`max` 表示深度推理。

---

### /fast

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 切换快速模式（仅使用快速模型） |
| **参数** | `[on\|off]` |
| **可用性** | `claude-ai`、`console` |
| **启用条件** | `isFastModeEnabled()` |
| **immediate** | 条件性 |
| **来源** | `commands/fast/index.ts` |

**核心功能**：快速模式开关。启用后仅使用速度更快的模型，适合简单任务。对非 ant 用户隐藏。

---

### /advisor

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 配置 advisor 模型 |
| **参数** | `[<model>\|off]` |
| **非交互** | 支持 |
| **启用条件** | `canUserConfigureAdvisor()` |
| **来源** | `commands/advisor.ts` |

**核心功能**：设置或关闭 advisor 模型。Advisor 是一个额外的 AI 模型，在主模型生成响应时提供审查和建议。支持 `unset`/`off` 关闭。会验证模型是否有效且支持 advisor 功能。

---

### /theme

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 更改主题 |
| **来源** | `commands/theme/index.ts` |

**核心功能**：切换 Claude Code 的终端 UI 主题配色方案。

---

### /color

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 设置当前会话的提示栏颜色 |
| **参数** | `<color\|default>` |
| **immediate** | 是 |
| **来源** | `commands/color/index.ts` |

**核心功能**：自定义输入提示栏的颜色，支持特定颜色名称或恢复默认。

---

### /vim

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 在 Vim 和普通编辑模式之间切换 |
| **非交互** | 不支持 |
| **来源** | `commands/vim/index.ts` |

**核心功能**：切换输入模式的 Vim 键绑定支持。

---

### /keybindings

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 打开或创建键绑定配置文件 |
| **非交互** | 不支持 |
| **启用条件** | `isKeybindingCustomizationEnabled()` |
| **来源** | `commands/keybindings/index.ts` |

**核心功能**：打开用户的键绑定自定义配置文件，允许修改快捷键映射。

---

### /output-style

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 已废弃：请使用 `/config` 更改输出风格 |
| **隐藏** | 是 |
| **来源** | `commands/output-style/index.ts` |

**核心功能**：已废弃命令，功能已合并到 `/config` 中。

---

### /terminal-setup

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 安装 Shift+Enter 换行键绑定（Apple Terminal 下为 Option+Enter） |
| **隐藏** | Ghostty、Kitty、iTerm2、WezTerm 等原生支持终端 |
| **来源** | `commands/terminalSetup/index.ts` |

**核心功能**：为不支持 Shift+Enter 原生换行的终端安装键绑定配置。自动检测终端类型并调整描述。

---

### /brief

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 切换简短模式 |
| **immediate** | 是 |
| **启用条件** | KAIROS/KAIROS_BRIEF feature flag 且 `enable_slash_command` 为 true |
| **来源** | `commands/brief.ts` |

**核心功能**：切换 Brief-Only 模式。启用后，模型使用 `BriefTool` 工具输出精简内容，普通文本被隐藏。关闭时恢复正常的文本输出模式。切换时会注入系统提醒以告知模型状态变更。

---

### /sandbox

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 显示沙箱状态并配置沙箱选项 |
| **参数** | `exclude "command pattern"` |
| **immediate** | 是 |
| **隐藏** | 不支持的平台或未在启用列表中的平台 |
| **来源** | `commands/sandbox-toggle/index.ts` |

**核心功能**：显示当前沙箱启用状态（包括 auto-allow 和 fallback 设置），并允许切换和配置沙箱行为。描述中动态显示沙箱状态图标和配置信息。

---

## 四、MCP / 插件

### /mcp

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 管理 MCP 服务器 |
| **参数** | `[enable\|disable [server-name]]` |
| **immediate** | 是 |
| **来源** | `commands/mcp/index.ts` |

**核心功能**：查看已配置的 MCP（Model Context Protocol）服务器状态，启用或禁用特定服务器。

---

### /plugin

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 管理 Claude Code 插件 |
| **别名** | `plugins`、`marketplace` |
| **immediate** | 是 |
| **来源** | `commands/plugin/index.tsx` |

**核心功能**：管理插件的安装、卸载、列表查看。插件可以扩展 Claude Code 的功能，包括自定义工具、MCP 服务器和技能。

---

### /reload-plugins

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 在当前会话中激活待生效的插件变更 |
| **非交互** | 不支持（SDK 使用 `query.reloadPlugins()` 替代） |
| **来源** | `commands/reload-plugins/index.ts` |

**核心功能**：Layer-3 刷新，将已安装或更新的插件变更应用到当前运行的会话中，无需重启。

---

### /skills

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 列出可用的技能 |
| **来源** | `commands/skills/index.ts` |

**核心功能**：显示所有已安装的自定义技能列表，包括项目级和全局技能。

---

### /hooks

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 查看工具事件的 hook 配置 |
| **immediate** | 是 |
| **来源** | `commands/hooks/index.ts` |

**核心功能**：显示当前配置的所有 hooks（在工具事件触发时自动执行的 shell 命令）。

---

### /pr-comments

| 属性 | 值 |
|------|-----|
| **类型** | `prompt`（已迁移至 plugin） |
| **描述** | 从 GitHub Pull Request 获取评论 |
| **来源** | `commands/pr_comments/index.ts` |

**核心功能**：使用 `gh` CLI 获取 PR 的评论和代码审查评论，格式化显示包含作者、文件位置、diff 上下文和评论线程。对于 ant 用户会引导安装 plugin 版本。

---

## 五、工具诊断

### /doctor

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 诊断和验证 Claude Code 安装及设置 |
| **启用条件** | 未设置 `DISABLE_DOCTOR_COMMAND` 环境变量 |
| **来源** | `commands/doctor/index.ts` |

**核心功能**：全面检查 Claude Code 的安装状态、API 连接、配置完整性、工具可用性等，帮助排查常见问题。

---

### /status

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 显示 Claude Code 状态（版本、模型、账户、API 连接、工具状态） |
| **immediate** | 是 |
| **来源** | `commands/status/index.ts` |

**核心功能**：快速显示当前会话的关键状态信息，包括运行版本、当前模型、账户类型、API 连接状态等。

---

### /context

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx`（交互式）/ `local`（非交互式） |
| **描述** | 以彩色网格可视化当前上下文使用情况 / 显示上下文使用信息 |
| **来源** | `commands/context/index.ts` |

**核心功能**：以可视化方式展示当前上下文窗口的使用情况。交互模式下显示彩色网格，非交互模式下输出文本摘要。

---

### /cost

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 显示当前会话的总成本和时长 |
| **非交互** | 支持 |
| **隐藏** | claude.ai 订阅者（ant 用户除外） |
| **来源** | `commands/cost/index.ts` |

**核心功能**：统计并展示当前会话消耗的 token 数量、总费用和运行时长。

---

### /files

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 列出当前上下文中的所有文件 |
| **非交互** | 支持 |
| **启用条件** | `USER_TYPE === 'ant'` |
| **来源** | `commands/files/index.ts` |

**核心功能**：列出所有已加载到上下文窗口中的文件。仅内部用户可用。

---

### /copy

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 将 Claude 的最新回复复制到剪贴板（或 `/copy N` 复制倒数第 N 条） |
| **来源** | `commands/copy/index.ts` |

**核心功能**：将 AI 回复内容复制到系统剪贴板，支持指定回复编号。

---

### /version

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 打印当前会话运行的版本 |
| **非交互** | 支持 |
| **启用条件** | `USER_TYPE === 'ant'` |
| **来源** | `commands/version.ts` |

**核心功能**：显示当前正在运行的 Claude Code 版本号（非自动更新下载的版本）。

---

### /heapdump

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 将 JS 堆转储到 ~/Desktop |
| **非交互** | 支持 |
| **隐藏** | 是 |
| **来源** | `commands/heapdump/index.ts` |

**核心功能**：调试工具，将 JavaScript 运行时堆内存转储到桌面文件中，用于内存泄漏分析。

---

## 六、模式切换

### /plan

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 启用计划模式或查看当前会话计划 |
| **参数** | `[open\|<description>]` |
| **来源** | `commands/plan/index.ts` |

**核心功能**：启用计划模式（AI 先制定计划再执行），查看当前计划，或根据描述创建新计划。

---

### /ultraplan

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | ~10-30 分钟，在 Claude Code on the web 上使用最强模型（Opus）生成高级计划 |
| **参数** | `<prompt>` |
| **启用条件** | 仅 ant 用户 |
| **来源** | `commands/ultraplan.tsx` |

**核心功能**：远程多代理规划模式。启动 CCR 远程会话，使用 Opus 模型进行深度分析和规划。计划完成后用户可选择在远端执行或将计划带回本地。支持种子计划（seedPlan）和关键词触发。后台轮询任务状态并通过 UI 通知进度。

---

### /voice

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 切换语音模式 |
| **可用性** | `claude-ai` |
| **非交互** | 不支持 |
| **启用条件** | `isVoiceGrowthBookEnabled()` |
| **隐藏** | 语音模式未启用时 |
| **来源** | `commands/voice/index.ts` |

**核心功能**：开关语音交互模式，允许通过语音与 Claude Code 交互。

---

### /exit

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 退出 REPL |
| **别名** | `quit` |
| **immediate** | 是 |
| **来源** | `commands/exit/index.ts` |

**核心功能**：退出 Claude Code 交互式 REPL 循环。

---

## 七、账户与认证

### /login

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 使用 Anthropic 账户登录 / 切换账户（已登录时） |
| **启用条件** | 未设置 `DISABLE_LOGIN_COMMAND` 环境变量 |
| **来源** | `commands/login/index.ts` |

**核心功能**：启动 OAuth 登录流程。若已使用 API Key 登录则显示"切换账户"。

---

### /logout

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 退出 Anthropic 账户 |
| **启用条件** | 未设置 `DISABLE_LOGOUT_COMMAND` 环境变量 |
| **来源** | `commands/logout/index.ts` |

**核心功能**：清除认证信息，退出当前账户。

---

### /upgrade

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 升级到 Max 以获得更高的速率限制和更多 Opus |
| **可用性** | `claude-ai` |
| **启用条件** | 非企业用户且未禁用 |
| **来源** | `commands/upgrade/index.ts` |

**核心功能**：引导用户升级订阅计划以获取更高级别的使用配额。

---

### /usage

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 显示计划使用限制 |
| **可用性** | `claude-ai` |
| **来源** | `commands/usage/index.ts` |

**核心功能**：显示当前订阅计划的使用配额和剩余量。

---

### /extra-usage

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx`（交互）/ `local`（非交互） |
| **描述** | 配置超额使用以在达到限制后继续工作 |
| **启用条件** | 允许超额配置 |
| **来源** | `commands/extra-usage/index.ts` |

**核心功能**：配置超额使用选项，允许在达到计划限制后通过额外付费继续使用。

---

### /rate-limit-options

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 达到速率限制时显示选项 |
| **启用条件** | claude.ai 订阅者 |
| **隐藏** | 是（仅内部使用） |
| **来源** | `commands/rate-limit-options/index.ts` |

**核心功能**：当 API 速率限制被触发时显示可用的处理选项。不在帮助中显示。

---

### /privacy-settings

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 查看和更新隐私设置 |
| **启用条件** | 消费者订阅者 |
| **来源** | `commands/privacy-settings/index.ts` |

**核心功能**：管理隐私相关设置，如数据收集和遥测偏好。

---

### /permissions

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 管理允许和拒绝的工具权限规则 |
| **别名** | `allowed-tools` |
| **来源** | `commands/permissions/index.ts` |

**核心功能**：管理工具的权限规则，包括允许列表和拒绝列表的配置。

---

## 八、远程与连接

### /session

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 显示远程会话 URL 和二维码 |
| **别名** | `remote` |
| **启用条件** | 远程模式已启用 |
| **隐藏** | 远程模式未启用时 |
| **来源** | `commands/session/index.ts` |

**核心功能**：在远程模式下显示当前会话的 URL 和二维码，方便从其他设备访问。

---

### /remote-control (别名 /rc)

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 连接此终端进行远程控制会话 |
| **参数** | `[name]` |
| **别名** | `rc` |
| **immediate** | 是 |
| **启用条件** | BRIDGE_MODE feature flag 且 bridge 已启用 |
| **隐藏** | 未启用时 |
| **来源** | `commands/bridge/index.ts` |

**核心功能**：启动 Bridge 模式，将该终端注册为可被远程控制的工作节点。

---

### /bridge-kick

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 注入 Bridge 故障状态用于手动恢复测试 |
| **非交互** | 不支持 |
| **启用条件** | `USER_TYPE === 'ant'` |
| **来源** | `commands/bridge-kick.ts` |

**核心功能**：内部调试工具，用于模拟 Bridge 连接中的各种故障场景（如 WebSocket 关闭、poll 错误、注册失败等），测试恢复机制。支持多种子命令：`close`、`poll`、`register`、`heartbeat`、`reconnect`、`status`。

---

### /remote-env

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 配置 teleport 会话的默认远程环境 |
| **启用条件** | claude.ai 订阅者且策略允许远程会话 |
| **隐藏** | 不符合条件时 |
| **来源** | `commands/remote-env/index.ts` |

**核心功能**：配置用于远程 teleport 会话的默认开发环境设置。

---

### /web-setup

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 在 Web 上设置 Claude Code（需连接 GitHub 账户） |
| **可用性** | `claude-ai` |
| **启用条件** | `tengu_cobalt_lantern` feature flag 且策略允许远程会话 |
| **隐藏** | 策略不允许远程会话时 |
| **来源** | `commands/remote-setup/index.ts` |

**核心功能**：引导用户在 Web 端设置 Claude Code，需要关联 GitHub 账户。

---

## 九、项目管理

### /init

| 属性 | 值 |
|------|-----|
| **类型** | `prompt` |
| **描述** | 初始化 CLAUDE.md 文件（新版支持 skills/hooks） |
| **来源** | `commands/init.ts` |

**核心功能**：分析代码库并创建 `CLAUDE.md` 配置文件。新版（NEW_INIT feature）支持 8 个阶段：询问设置范围 → 探索代码库 → 填补信息缺口 → 写 CLAUDE.md → 写 CLAUDE.local.md → 创建 skills → 建议 hooks → 总结和后续步骤。旧版仅生成 CLAUDE.md。

---

### /init-verifiers

| 属性 | 值 |
|------|-----|
| **类型** | `prompt` |
| **描述** | 创建验证器技能用于自动化验证代码变更 |
| **来源** | `commands/init-verifiers.ts` |

**核心功能**：自动检测项目类型并创建验证器技能。支持 Playwright（Web UI）、Tmux（CLI）、HTTP（API）三种验证器类型。5 个阶段：自动检测 → 工具设置 → 交互问答 → 生成技能 → 确认创建。

---

### /add-dir

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 添加新的工作目录 |
| **参数** | `<path>` |
| **来源** | `commands/add-dir/index.ts` |

**核心功能**：将一个额外的目录添加到当前会话的工作目录列表中。

---

### /memory

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 编辑 Claude 记忆文件 |
| **来源** | `commands/memory/index.ts` |

**核心功能**：打开并编辑 Claude 的记忆文件（CLAUDE.md 等持久化配置）。

---

### /agents

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 管理代理配置 |
| **来源** | `commands/agents/index.ts` |

**核心功能**：管理和配置 AI 代理（Agent）的行为和参数。

---

### /tasks

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 列出和管理后台任务 |
| **别名** | `bashes` |
| **来源** | `commands/tasks/index.ts` |

**核心功能**：显示当前正在运行的后台 Bash 任务列表，并提供管理操作。

---

## 十、信息查看

### /help

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 显示帮助和可用命令 |
| **来源** | `commands/help/index.ts` |

**核心功能**：列出所有可用的斜杠命令及其描述。

---

### /stats

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 显示 Claude Code 使用统计和活动 |
| **来源** | `commands/stats/index.ts` |

**核心功能**：展示用户的使用统计信息，包括会话数量、使用频率等。

---

### /insights

| 属性 | 值 |
|------|-----|
| **类型** | `prompt` |
| **描述** | Generate a report analyzing your Claude Code sessions |
| **来源** | `commands/insights.ts` |

**核心功能**：收集所有历史会话数据（包括远程 homespace），使用 AI 模型进行多维分析。包括项目领域分析、交互风格描述、成功工作流识别、摩擦分析、改进建议和未来机会。生成 6-8 个并行的洞察部分。支持 facet 缓存和增量更新。

---

### /release-notes

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 查看发行说明 |
| **非交互** | 支持 |
| **来源** | `commands/release-notes/index.ts` |

**核心功能**：显示最近版本的发行说明和更新日志。

---

### /think-back

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 2025 Claude Code 年度回顾 |
| **启用条件** | `tengu_thinkback` feature flag |
| **来源** | `commands/thinkback/index.ts` |

**核心功能**：生成用户 2025 年使用 Claude Code 的年度回顾报告。

---

### /thinkback-play

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 播放 thinkback 动画 |
| **启用条件** | `tengu_thinkback` feature flag |
| **隐藏** | 是 |
| **非交互** | 不支持 |
| **来源** | `commands/thinkback-play/index.ts` |

**核心功能**：播放年度回顾的动画效果。由 thinkback 技能在生成完成后调用。

---

### /sticksers

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 订购 Claude Code 贴纸 |
| **非交互** | 不支持 |
| **来源** | `commands/stickers/index.ts` |

**核心功能**：提供 Claude Code 品牌贴纸的订购入口。

---

## 十一、集成与平台

### /ide

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 管理 IDE 集成并显示状态 |
| **参数** | `[open]` |
| **来源** | `commands/ide/index.ts` |

**核心功能**：查看和管理 IDE（如 VS Code、JetBrains）的 Claude Code 扩展集成状态。

---

### /desktop

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 在 Claude Desktop 中继续当前会话 |
| **别名** | `app` |
| **可用性** | `claude-ai` |
| **启用条件** | macOS 或 Windows x64 |
| **隐藏** | 不支持的平台 |
| **来源** | `commands/desktop/index.ts` |

**核心功能**：将当前 CLI 会话无缝转移到 Claude Desktop 应用程序继续。

---

### /chrome

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | Claude in Chrome (Beta) 设置 |
| **可用性** | `claude-ai` |
| **启用条件** | 非交互会话 |
| **来源** | `commands/chrome/index.ts` |

**核心功能**：管理 Chrome 浏览器扩展的 Claude 集成设置。

---

### /mobile

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 显示二维码以下载 Claude 移动应用 |
| **别名** | `ios`、`android` |
| **来源** | `commands/mobile/index.ts` |

**核心功能**：显示下载 Claude 移动应用的二维码。

---

### /feedback

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 提交关于 Claude Code 的反馈 |
| **参数** | `[report]` |
| **别名** | `bug` |
| **启用条件** | 非 Bedrock/Vertex/Foundry 用户，且未禁用反馈功能 |
| **来源** | `commands/feedback/index.ts` |

**核心功能**：提交 bug 报告或功能反馈。不适用于使用第三方 API 提供商的用户。

---

### /install

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 安装 Claude Code 原生构建 |
| **参数** | `[options]`（`--force`、`latest`、`stable` 或版本号） |
| **来源** | `commands/install.tsx` |

**核心功能**：安装或更新 Claude Code 的原生构建版本。包含完整的安装流程：检查安装状态 → 下载安装 → 设置启动器和 shell 集成 → 清理旧 npm 安装 → 清理旧 shell 别名。支持 `--force` 强制重装和指定版本/通道。注意：这不是斜杠命令，仅从 `cli.tsx` 调用。

---

### /statusline

| 属性 | 值 |
|------|-----|
| **类型** | `prompt` |
| **描述** | 设置 Claude Code 状态栏 UI |
| **非交互** | 禁用 |
| **来源** | `commands/statusline.tsx` |

**核心功能**：配置终端状态栏的显示内容，可从 shell PS1 配置中读取。

---

### /install-github-app

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 为仓库设置 Claude GitHub Actions |
| **可用性** | `claude-ai`、`console` |
| **启用条件** | 未设置 `DISABLE_INSTALL_GITHUB_APP_COMMAND` |
| **来源** | `commands/install-github-app/index.ts` |

**核心功能**：在 GitHub 仓库中安装和配置 Claude Code 的 GitHub Actions 集成。

---

### /install-slack-app

| 属性 | 值 |
|------|-----|
| **类型** | `local` |
| **描述** | 安装 Claude Slack 应用 |
| **可用性** | `claude-ai` |
| **非交互** | 不支持 |
| **来源** | `commands/install-slack-app/index.ts` |

**核心功能**：引导用户安装 Claude 的 Slack 工作区集成。

---

### /passes

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 与朋友分享一周免费 Claude Code 使用 |
| **隐藏** | 不符合资格时 |
| **来源** | `commands/passes/index.ts` |

**核心功能**：推荐计划相关功能，分享免费的 Claude Code 体验。根据推荐状态显示不同描述。

---

## 十二、内部/调试命令

### /btw

| 属性 | 值 |
|------|-----|
| **类型** | `local-jsx` |
| **描述** | 快速提一个附带问题而不打断主对话 |
| **参数** | `<question>` |
| **immediate** | 是 |
| **来源** | `commands/btw/index.ts` |

**核心功能**：在不中断当前主对话流程的情况下，快速提出一个附带问题。

---

### /createMovedToPluginCommand

| 属性 | 值 |
|------|-----|
| **类型** | 工厂函数（特殊类型，用于生成命令兼容层，非直接可调用命令） |
| **描述** | 创建已迁移至插件的命令的兼容层 |
| **来源** | `commands/createMovedToPluginCommand.ts` |

**核心功能**：为已从核心迁移到插件的命令创建兼容层。对 ant 用户提示安装插件；对外部用户提供 fallback prompt。被 `/pr-comments`、`/security-review` 等命令使用。
