# Remote 模块 (remote/)

Skills 是内置在 CLI 中的可复用提示模板，用户可通过 `/skill-name` 方式调用。Skills 模块负责从多种来源发现、加载、去重和激活技能。

## 文件概览

---

## 目录结构

```
skills/
├── bundledSkills.ts       # 内置技能注册表与文件提取逻辑
├── loadSkillsDir.ts      # 核心加载逻辑，支持多源与动态发现
├── mcpSkillBuilders.ts   # MCP 技能构建器的注册表（解决循环依赖）
└── bundled/
    ├── index.ts          # 统一初始化所有内置技能
    ├── batch.ts
    ├── claudeApi.ts      # (BUILDING_CLAUDE_APPS)
    ├── claudeApiContent.ts
    ├── claudeInChrome.ts # (shouldAutoEnableClaudeInChrome())
    ├── debug.ts
    ├── keybindings.ts
    ├── loop.ts           # (AGENT_TRIGGERS)
    ├── loremIpsum.ts
    ├── remember.ts
    ├── scheduleRemoteAgents.ts # (AGENT_TRIGGERS_REMOTE)
    ├── simplify.ts
    ├── skillify.ts
    ├── stuck.ts
    ├── updateConfig.ts
    ├── verify.ts
    ├── verifyContent.ts
    └── ...
```

> **Note**: The following skill files are conditionally loaded via feature flags and may not exist in all builds: `dream.ts` (KAIROS || KAIROS_DREAM), `hunter.ts` (REVIEW_ARTIFACT), `runSkillGenerator.ts` (RUN_SKILL_GENERATOR). They are registered conditionally in `bundled/index.ts` but the source files are not present in the repository.

## 技能发现与加载

### 加载来源

`getSkillDirCommands()` 从以下来源并行加载技能（见 `loadSkillsDir.ts:638`）：

| 来源 | 路径 | 来源标识 |
|------|------|---------|
| Managed（策略设置） | `<managed>/.claude/skills` | `policySettings` |
| User（用户配置） | `~/.claude/skills` | `userSettings` |
| Project（项目配置） | `<project>/.claude/skills` | `projectSettings` |
| Additional dirs（`--add-dir`） | `<dir>/.claude/skills` | `projectSettings` |
| Legacy commands | `<project>/.claude/commands` | `commands_DEPRECATED` |

`--bare` 模式下跳过自动发现，只加载 `--add-dir` 指定的路径。

### 目录格式

`/skills/` 目录**只支持目录格式**：

```
skills/
└── my-skill/
    └── SKILL.md      # 必须名为 SKILL.md
```

Legacy `/commands/` 目录同时支持两种格式：

```
commands/
├── standalone.md                    # 单文件，名为命令名
└── my-command/
    └── SKILL.md                     # 目录格式
```

### 加载流程 (`loadSkillsFromSkillsDir`)

对每个目录条目（`loadSkillsDir.ts:407`）：

1. 必须是目录或符号链接，否则跳过
2. 查找 `<entry>/SKILL.md`，不存在则跳过
3. 解析 frontmatter 和 markdown 内容
4. 调用 `parseSkillFrontmatterFields()` 提取字段
5. 调用 `createSkillCommand()` 创建 `Command` 对象

### 去重机制

通过 `realpath()` 解析符号链接，获取规范路径（`loadSkillsDir.ts:118`）。同一文件通过不同路径访问时只保留第一个加载的实例。

## 动态技能发现

### 发现目录 (`discoverSkillDirsForPaths`)

当文件被 Read/Write/Edit 时，从文件路径向上遍历到 cwd，查找 `.claude/skills` 目录（`loadSkillsDir.ts:861`）：

```
file: /project/src/components/Button.tsx
  → /project/src/components/.claude/skills
  → /project/src/.claude/skills
  → /project/.claude/skills      # 到达 cwd，停止
```

已检查过的目录记录在 `dynamicSkillDirs` Set 中，避免重复 stat。

### 加载目录 (`addSkillDirectories`)

找到新目录后调用 `loadSkillsFromSkillsDir()` 加载技能，深层路径的技能覆盖浅层路径（`loadSkillsDir.ts:923`）。

### 条件技能激活 (`activateConditionalSkillsForPaths`)

具有 `paths` frontmatter 的技能为"条件技能"（`loadSkillsDir.ts:997`）：

```yaml
---
paths:
  - src/**/*.tsx
  - components/**
---
```

使用 `ignore` 库（gitignore 风格）匹配文件路径。当匹配的文件被访问时，将技能从 `conditionalSkills` Map 移入 `dynamicSkills`，触发 `onDynamicSkillsLoaded` 信号。

## Bundled Skills（内置技能）

### 注册机制

内置技能通过 `registerBundledSkill(definition)` 注册（`bundledSkills.ts:53`），definition 类型为 `BundledSkillDefinition`（定义于 `bundledSkills.ts:15`）：

```typescript
export type BundledSkillDefinition = {
  name: string
  description: string
  aliases?: string[]
  whenToUse?: string
  argumentHint?: string
  allowedTools?: string[]
  model?: string
  disableModelInvocation?: boolean
  userInvocable?: boolean
  isEnabled?: () => boolean       // 运行时决定是否可见
  hooks?: HooksSettings
  context?: 'inline' | 'fork'
  agent?: string
  files?: Record<string, string>  // 参考文件，提取到磁盘
  getPromptForCommand: (args: string, context: ToolUseContext) => Promise<ContentBlockParam[]>
}
```

### 文件提取

若定义了 `files`，首次调用技能时将文件提取到 `getBundledSkillExtractDir()` 目录（`bundledSkills.ts:60`）：

```typescript
// 提取 promise 在进程内只执行一次
extractionPromise ??= extractBundledSkillFiles(definition.name, files)
const extractedDir = await extractionPromise
```

提取时使用 `O_NOFOLLOW | O_EXCL` 防止符号链接攻击，文件权限 `0o600`，目录 `0o700`。

### 初始化

`skills/bundled/index.ts` 的 `initBundledSkills()` 在启动时调用，注册所有内置技能。部分技能受 Feature Flag 控制：

```typescript
if (feature('KAIROS') || feature('KAIROS_DREAM')) registerDreamSkill()    // dream.ts
if (feature('REVIEW_ARTIFACT')) registerHunterSkill()                      // hunter.ts
if (feature('AGENT_TRIGGERS')) registerLoopSkill()                         // loop.ts
if (feature('AGENT_TRIGGERS_REMOTE')) registerScheduleRemoteAgentsSkill() // scheduleRemoteAgents.ts
if (feature('BUILDING_CLAUDE_APPS')) registerClaudeApiSkill()               // claudeApi.ts
if (shouldAutoEnableClaudeInChrome()) registerClaudeInChromeSkill()       // claudeInChrome.ts
if (feature('RUN_SKILL_GENERATOR')) registerRunSkillGeneratorSkill()       // runSkillGenerator.ts
```

## mcpSkillBuilders（解决循环依赖）

`mcpSkillBuilders.ts` 是一个写一次注册表（`mcpSkillBuilders.ts:26`）：

```typescript
export type MCPSkillBuilders = {
  createSkillCommand: typeof createSkillCommand
  parseSkillFrontmatterFields: typeof parseSkillFrontmatterFields
}

let builders: MCPSkillBuilders | null = null

export function registerMCPSkillBuilders(b: MCPSkillBuilders): void { ... }
export function getMCPSkillBuilders(): MCPSkillBuilders { ... }
```

**为什么需要这个中间层？** MCP 技能发现模块需要调用 `loadSkillsDir.ts` 中的函数，但动态 `import(variable)` 在 Bun 打包的二进制中无法正确解析（路径基于 `$bunfs/root` 而非源码树）。改用字面量动态导入会触发大量循环依赖检测违规。注册表模式绕过了这两个问题。

## 主要类型

### Command（技能表示）

`Command` 是交叉类型，由 `CommandBase` 联合三种命令变体之一组成（`types/command.ts:205`）：

```typescript
export type Command = CommandBase &
  (PromptCommand | LocalCommand | LocalJSXCommand)
```

变体类型定义各自的 `type` 字段和特定字段：

- **`PromptCommand`**：`type: 'prompt'`，含 `getPromptForCommand` 方法
- **`LocalCommand`**：`type: 'local'`，含 `handler` 回调
- **`LocalJSXCommand`**：`type: 'local_jsx'`，含 JSX 渲染函数

`CommandBase` 包含共享字段：`name`、`description`、`aliases`、`argumentHint`、`whenToUse`、`version`、`allowedTools`、`loadedFrom`、`hooks`、`isEnabled`、`isHidden`、`userFacingName` 等。

### LoadedFrom

```typescript
export type LoadedFrom =
  | 'commands_DEPRECATED'  // Legacy /commands/ 目录
  | 'skills'              // /skills/ 目录
  | 'plugin'              // 插件
  | 'managed'             // Managed 配置
  | 'bundled'             // 内置技能
  | 'mcp'                 // MCP 服务器
```

## 主要函数签名

### loadSkillsDir.ts

```typescript
export function getSkillsPath(source: SettingSource | 'plugin', dir: 'skills' | 'commands'): string

export function parseSkillFrontmatterFields(
  frontmatter: FrontmatterData,
  markdownContent: string,
  resolvedName: string,
  descriptionFallbackLabel?: 'Skill' | 'Custom command'
): ParsedFields

export function createSkillCommand(params: CreateSkillCommandParams): Command

export const getSkillDirCommands: (cwd: string) => Promise<Command[]>

export async function discoverSkillDirsForPaths(
  filePaths: string[],
  cwd: string
): Promise<string[]>

export async function addSkillDirectories(dirs: string[]): Promise<void>

export function activateConditionalSkillsForPaths(
  filePaths: string[],
  cwd: string
): string[]

export function onDynamicSkillsLoaded(callback: () => void): () => void

export function getDynamicSkills(): Command[]

export function getConditionalSkillCount(): number

export function clearSkillCaches(): void
```

### bundledSkills.ts

```typescript
export function registerBundledSkill(definition: BundledSkillDefinition): void
export function getBundledSkills(): Command[]
export function clearBundledSkills(): void
export function getBundledSkillExtractDir(skillName: string): string
```

### mcpSkillBuilders.ts

```typescript
export function registerMCPSkillBuilders(b: MCPSkillBuilders): void
export function getMCPSkillBuilders(): MCPSkillBuilders
```

## 缓存清除

```typescript
// 清除所有技能缓存（用于测试或配置变更后）
export function clearSkillCaches() {
  getSkillDirCommands.cache?.clear?.()
  loadMarkdownFilesForSubdir.cache?.clear?.()
  conditionalSkills.clear()
  activatedConditionalSkillNames.clear()
}

// 清除动态技能状态
export function clearDynamicSkills(): void {
  dynamicSkillDirs.clear()
  dynamicSkills.clear()
  conditionalSkills.clear()
  activatedConditionalSkillNames.clear()
}
```
