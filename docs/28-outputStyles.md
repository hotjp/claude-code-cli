# OutputStyles 模块 (outputStyles/)

## 文件概览

`outputStyles/` 目录负责从磁盘加载自定义 output style 配置文件。Output style 本质上是一段系统提示词（system prompt），用于控制 Claude Code 的输出行为和风格。

## 核心文件

- `loadOutputStylesDir.ts` — 从文件系统加载 output style 配置的唯一入口

## 导出内容

### `getOutputStyleDirStyles(cwd: string)`

从项目目录和用户目录加载自定义 output style。

**加载来源（优先级从低到高）：**

1. `~/.claude/output-styles/*.md` — 用户级样式
2. 项目 `.claude/output-styles/*.md` — 项目级样式（会覆盖用户级同名样式）

**文件名规范：** 每个 `.md` 文件的文件名（不含扩展名）即为 style 的标识名。

**Frontmatter 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `string` | 样式显示名称，默认使用文件名 |
| `description` | `string` | 样式描述，供用户选择时参考 |
| `keep-coding-instructions` | `boolean` | 是否保留 coding instructions，标准化后恒为 `true \| false \| undefined` |
| `force-for-plugin` | `any` | 仅对插件样式有效，此处会忽略并输出警告 |

**返回值类型：**

```typescript
type OutputStyleConfig = {
  name: string
  description: string
  prompt: string      // 文件正文内容（trim 后）
  source: SettingSource | 'built-in' | 'plugin'      // 'built-in' 和 'plugin' 来源仅由 getAllOutputStyles() 返回
  keepCodingInstructions?: boolean
  forceForPlugin?: boolean
}
```

**特点：** 结果经过 `memoize` 缓存，同一 `cwd` 重复调用直接返回缓存。

### `clearOutputStyleCaches()`

清除所有 output style 相关的缓存，包括：

- `getOutputStyleDirStyles` 的 memoize 缓存
- `loadMarkdownFilesForSubdir` 的 memoize 缓存
- 插件 output style 的缓存（`clearPluginOutputStyleCache`）

## 与其他模块的关系

```
loadOutputStylesDir.ts
├── constants/outputStyles.ts     — 定义 OutputStyleConfig 类型及内置样式
│   └── getAllOutputStyles()       — 合并内置 + 插件 + 磁盘加载的样式
└── utils/plugins/loadPluginOutputStyles.ts — 插件样式的独立加载逻辑
```

**调用链：**

1. `constants/outputStyles.ts` 中的 `getAllOutputStyles()` 调用 `getOutputStyleDirStyles()`
2. `getOutputStyleDirStyles()` 通过 `loadMarkdownFilesForSubdir()` 扫描目录
3. 加载结果与内置样式（`Explanatory`、`Learning`）以及插件样式合并，以 `policySettings > projectSettings > userSettings > plugin > built-in` 的优先级覆盖（policySettings 最高）

## 样式优先级

参见 `constants/outputStyles.ts` 中的 `getAllOutputStyles()`：

```
built-in < plugin < userSettings < projectSettings < policySettings
```

同名样式会被高优先级来源覆盖。

## 缓存失效

`clearOutputStyleCaches()` 在以下场景被调用以确保配置变更生效：

- 用户修改了 `.claude/output-styles/` 下的文件
- 插件 output style 需要重新加载
