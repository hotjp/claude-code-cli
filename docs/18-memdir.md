# Memdir 模块 (memdir/)

## 架构概览

Memdir 是 Claude Code 的持久化文件内存系统，支持私有（个人）和团队两种作用域。内存以 Markdown 文件形式存储在磁盘，每个文件使用 frontmatter 头部的 `type` 字段标记类型（user / feedback / project / reference），通过 `MEMORY.md` 索引文件组织。

### 核心概念

- **私有内存 (auto memory)**: 存储在 `~/.claude/projects/<project>/memory/`，仅当前用户可见
- **团队内存 (team memory)**: 存储在 `<auto_mem_path>/team/`，项目内所有用户共享
- **四类类型**: user（用户信息）、feedback（指导反馈）、project（项目上下文）、reference（外部系统指针）
- **索引文件**: `MEMORY.md`，每行一条 `-[Title](file.md) — one-line hook` 格式的引用

### 核心流程

```typescript
用户对话 → 判断是否应访问内存 → 扫描目录/读取索引 → AI 选择相关记忆 → 返回文件路径+mtime
```

---

## 核心接口

| 函数/类型 | 说明 |
|-----------|------|
| `loadMemoryPrompt()` | 加载内存提示词（系统级入口），根据功能门控返回不同提示 |
| `buildMemoryPrompt()` | 构建包含 MEMORY.md 内容的完整内存提示（agent 级使用） |
| `buildMemoryLines()` | 构建纯行为指令（不含 MEMORY.md 内容） |
| `buildCombinedMemoryPrompt()` | 构建 auto + team 双目录联合提示 |
| `findRelevantMemories()` | 根据查询语句 AI 选取最相关的记忆文件（最多 5 个） |
| `scanMemoryFiles()` | 扫描目录返回所有 .md 文件的 frontmatter 头部信息（排除 MEMORY.md），先按 mtime 降序排列全部结果，再截取前 200 个文件 |
| `formatMemoryManifest()` | 将内存头部列表格式化为供 AI 读取的清单文本 |
| `MemoryHeader` | 内存文件头部类型：`{ filename, filePath, mtimeMs, description, type }` |
| `MemoryType` | 类型枚举：`'user' \| 'feedback' \| 'project' \| 'reference'` |
| `RelevantMemory` | 相关记忆返回类型：`{ path: string, mtimeMs: number }` |
| `MEMORY_TYPES` | 类型常量数组：`['user', 'feedback', 'project', 'reference']` |

---

## 路径管理

### paths.ts — 私有内存路径

**用途**: 解析和验证私有内存目录路径。

**核心函数**:

| 函数 | 说明 |
|------|------|
| `getAutoMemPath()` | 返回私有内存根目录（带 memoize，按 projectRoot 缓存） |
| `getAutoMemEntrypoint()` | 返回 `MEMORY.md` 完整路径 |
| `getAutoMemDailyLogPath(date?)` | 返回按日期的日志文件路径（`.../logs/YYYY/MM/YYYY-MM-DD.md`） |
| `isAutoMemPath(absolutePath)` | 判断路径是否在私有内存目录内 |
| `isAutoMemoryEnabled()` | 判断自动内存功能是否启用 |
| `isExtractModeActive()` | 判断后台记忆提取 agent 是否运行 |
| `hasAutoMemPathOverride()` | 判断是否通过 `CLAUDE_COWORK_MEMORY_PATH_OVERRIDE` 覆盖路径 |
| `getMemoryBaseDir()` | 返回内存基准目录（默认 `~/.claude`） |

**路径解析优先级**（getAutoMemPath）:
1. `CLAUDE_COWORK_MEMORY_PATH_OVERRIDE` 环境变量（全路径覆盖）
2. `settings.json` 中 `autoMemoryDirectory`（policy/flag/local/user 配置源，依次查询）
3. `<memoryBase>/projects/<sanitized-git-root>/memory/`

**安全特性**:
- `validateMemoryPath()` 拒绝相对路径、Windows 盘符根、UNC 路径、null 字节
- 支持 `~/` 展开（仅限 settings.json）
- `isAutoMemPath()` 使用 `normalize()` 防止路径遍历

---

### teamMemPaths.ts — 团队内存路径

**用途**: 解析团队共享内存目录路径，提供写路径安全验证。

**核心函数**:

| 函数 | 说明 |
|------|------|
| `getTeamMemPath()` | 返回团队内存根目录 `<auto_mem_path>/team/` |
| `getTeamMemEntrypoint()` | 返回 `MEMORY.md` 完整路径 |
| `isTeamMemPath(filePath)` | 判断路径是否在团队内存目录内（resolve 化后前缀匹配） |
| `isTeamMemFile(filePath)` | 判断路径在团队内存目录且团队内存已启用 |
| `isTeamMemoryEnabled()` | 判断团队内存功能是否启用 |
| `validateTeamMemWritePath(filePath)` | 验证写入路径安全（双次 realpath 检查，防符号链接逃逸） |
| `validateTeamMemKey(relativeKey)` | 验证相对路径 key 安全（清洗 + 验证） |
| `PathTraversalError` | 路径遍历攻击时抛出的错误类 |

**安全特性**（PSR M22186）:
1. 第一遍：`resolve()` 消除 `..` 段后做字符串前缀检查
2. 第二遍：`realpathDeepestExisting()` 解析最深已有祖先的真实路径，再与真实 team dir 比较
3. 检测并拒绝：null 字节、URL 编码遍历、Unicode 归一化攻击（NFKC）、反斜杠、悬空符号链接

---

## 内存类型定义

### memoryTypes.ts — 类型系统

**用途**: 定义四类记忆的 taxonomy、prompt 文案和 frontmatter 格式。

**导出内容**:

| 导出 | 说明 |
|------|------|
| `MEMORY_TYPES` | 常量数组：`['user', 'feedback', 'project', 'reference']` |
| `MemoryType` | 类型别名 |
| `parseMemoryType(raw)` | 解析 frontmatter 中的 type 字段 |
| `TYPES_SECTION_COMBINED` | 联合模式（含 `<scope>` 标签）下的类型说明段落 |
| `TYPES_SECTION_INDIVIDUAL` | 单目录模式下的类型说明段落 |
| `WHAT_NOT_TO_SAVE_SECTION` | "不应保存什么" 的指南 |
| `MEMORY_DRIFT_CAVEAT` | 记忆可能过时的警告 |
| `TRUSTING_RECALL_SECTION` | "引用前验证" 指南 |
| `WHEN_TO_ACCESS_SECTION` | "何时访问记忆" 指南 |
| `MEMORY_FRONTMATTER_EXAMPLE` | frontmatter 格式示例 |

**四类记忆**:

| 类型 | scope | 说明 |
|------|-------|------|
| `user` | always private | 用户角色、目标、知识储备 |
| `feedback` | 默认为 private，团队仅用于项目级公约 | 用户的指导/纠正/偏好 |
| `project` | private 或 team（强烈倾向 team） | 项目上下文、正在进行的工作、目标/截止日期/决策 |
| `reference` | 通常为 team | 外部系统指针（Linear 项目、Dashboard URL 等） |

**不应保存的内容**:
- 代码模式、架构、文件路径（可从代码推导）
- Git 历史（`git log`/`git blame` 权威）
- 调试方案（修复代码在代码库中）
- 已记录在 CLAUDE.md 的内容
- 临时任务细节

---

## 记忆新鲜度

### memoryAge.ts — 记忆时效性

**用途**: 计算记忆文件的年龄，生成人类可读的过时警告。

**核心函数**:

| 函数 | 说明 |
|------|------|
| `memoryAgeDays(mtimeMs)` | 返回距离修改的天数（地板取整，最小为 0） |
| `memoryAge(mtimeMs)` | 返回 `'today'` / `'yesterday'` / `'N days ago'` |
| `memoryFreshnessText(mtimeMs)` | 返回过时期望警告文本（>1 天才返回，非空字符串） |
| `memoryFreshnessNote(mtimeMs)` | 返回 `<system-reminder>` 包装的过时警告（≤1 天返回空） |

---

## 记忆扫描

### memoryScan.ts — 目录扫描

**用途**: 扫描内存目录中的 `.md` 文件，提取 frontmatter 头部信息。

**核心函数**:

| 函数 | 说明 |
|------|------|
| `scanMemoryFiles(memoryDir, signal)` | 扫描目录返回所有 .md 文件头部（排除 MEMORY.md），按 mtime 降序 |
| `formatMemoryManifest(memories)` | 将头部列表格式化为 AI 可读的清单文本 |

**MemoryHeader 类型**:
```typescript
{
  filename: string       // 相对路径
  filePath: string       // 绝对路径
  mtimeMs: number        // 修改时间戳
  description: string | null  // frontmatter.description
  type: MemoryType | undefined // frontmatter.type
}
```

**扫描策略**: 单次读取全部匹配文件后统一排序（避免双重 stat），最后截取前 200 个文件返回。

---

## 相关记忆查找

### findRelevantMemories.ts — AI 驱动的记忆选择

**用途**: 根据当前查询，使用 Sonnet 模型从内存目录中选取最相关的记忆文件。

**核心函数**:

| 函数 | 说明 |
|------|------|
| `findRelevantMemories(query, memoryDir, signal, recentTools?, alreadySurfaced?)` | 返回最多 5 个相关记忆的路径 + mtime。recentTools 用于排除最近使用的工具文档；alreadySurfaced 过滤已展示的记忆 |

**选择流程**:
1. `scanMemoryFiles()` 扫描目录（排除 `alreadySurfaced` 中已展示的）
2. `formatMemoryManifest()` 生成供模型阅读的清单
3. 若 `recentTools` 非空，附加最近使用的工具列表（避免选中这些工具的使用文档）
4. 通过 `sideQuery()` 调用 Sonnet，传入 `SELECT_MEMORIES_SYSTEM_PROMPT`（内部常量，不导出）
5. 解析 JSON 响应 `{ selected_memories: string[] }`，过滤无效文件名
6. 按文件名查找对应 `MemoryHeader`，返回 `{ path, mtimeMs }[]`

**遥测**: 若 `feature('MEMORY_SHAPE_TELEMETRY')` 启用，记录选择率（已选/总数）

**Select System Prompt 策略**:
- 仅选取文件名和描述与查询明确相关的记忆
- 不确定时倾向于不选（保守策略）
- 若最近使用了某工具，跳过该工具的 API 文档（已 actively using），但仍选警告/已知问题类记忆

---

## 主模块

### memdir.ts — 提示词构建与加载

**用途**: 核心入口，构建和加载内存系统提示词，管理多种内存模式。

**核心函数**:

| 函数 | 说明 |
|------|------|
| `loadMemoryPrompt()` | 主入口：返回内存系统提示词（按功能门控分发），auto 禁用时返回 null |
| `buildMemoryPrompt({ displayName, memoryDir, extraGuidelines })` | 构建含 MEMORY.md 内容的完整提示（agent 使用） |
| `buildMemoryLines(displayName, memoryDir, extraGuidelines?, skipIndex?)` | 构建纯指令（不含 MEMORY.md 内容） |
| `buildSearchingPastContextSection(autoMemDir)` | 若 `tengu_coral_fern` 启用，附加搜索指南 |
| `ensureMemoryDirExists(memoryDir)` | 确保内存目录存在（幂等） |
| `truncateEntrypointContent(raw)` | 截断 MEMORY.md（行数/字节数双重限制） |
| `DIR_EXISTS_GUIDANCE` | 提示文本：目录已存在，直接写入 |
| `DIRS_EXIST_GUIDANCE` | 联合模式：两个目录均已存在 |
| `ENTRYPOINT_NAME` | 索引文件名：`MEMORY.md` |
| `MAX_ENTRYPOINT_LINES` | 索引最大行数：200 |
| `MAX_ENTRYPOINT_BYTES` | 索引最大字节数：25000 |

**loadMemoryPrompt() 分发逻辑**:
```typescript
autoEnabled?
├── KAIROS 模式 → buildAssistantDailyLogPrompt（每日日志追加模式，内部函数）
├── TEAMMEM 启用 → buildCombinedMemoryPrompt（auto + team 联合）
└── 仅 auto → buildMemoryLines.join('\n')
```

**日志提示模式**（KAIROS）:
- 会话长期运行，新记忆追加到 `.../logs/YYYY/MM/YYYY-MM-DD.md`
- 不维护 `MEMORY.md` 活索引（由 `/dream` 技能定期蒸馏）
- `MEMORY.md` 仍加载为已蒸馏的索引

**搜索历史上下文**（tengu_coral_fern）:
- 嵌入搜索工具时使用 shell `grep` 命令
- 标准模式下使用 `Grep` 工具

---

## 团队内存提示

### teamMemPrompts.ts — 联合提示构建

**用途**: 构建 auto + team 双目录联合模式下的内存提示词。

**核心函数**:

| 函数 | 说明 |
|------|------|
| `buildCombinedMemoryPrompt(extraGuidelines?, skipIndex?)` | 构建双目录联合提示 |

**与单目录模式的区别**:
- 包含 `## Memory scope` 章节（private vs team）
- 每类记忆包含 `<scope>` 标签
- `## How to save memories` 中 Step 2 提到两个独立的 `MEMORY.md` 索引
- 强调团队记忆中禁止保存敏感数据（API key、凭证等）

---

## 文件索引

| 文件 | 作用 |
|------|------|
| `memdir.ts` | 主模块：提示词构建与加载、目录保障、截断逻辑 |
| `findRelevantMemories.ts` | AI 驱动的相关记忆选取（调用 sideQuery） |
| `memoryScan.ts` | 内存目录扫描（.md 文件 + frontmatter 解析） |
| `memoryTypes.ts` | 四类记忆类型定义、prompt 文案片、frontmatter 格式 |
| `memoryAge.ts` | 记忆新鲜度计算与警告文本生成 |
| `paths.ts` | 私有内存路径解析、验证、功能门控 |
| `teamMemPaths.ts` | 团队内存路径解析、双次 realpath 安全验证 |
| `teamMemPrompts.ts` | auto + team 联合模式提示词构建 |
