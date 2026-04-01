# Assistant 模块 (assistant/)

> 内置插件注册与管理系统

## 概述

`plugins/` 模块负责管理 Claude Code CLI 的内置插件（Built-in Plugins）。内置插件是随 CLI 打包的功能模块，用户可以通过 `/plugin` 命令 UI 来启用或禁用它们。

**注意**：当前内置插件系统仍为脚手架阶段，尚未注册任何插件。该系统旨在为未来从 `bundled skills` 迁移过来的功能提供用户可控的开关能力。

## 目录结构

```
plugins/
├── builtinPlugins.ts   # 内置插件初始化入口
└── bundled/
    └── index.ts        # 内置插件注册表核心实现
```

## 核心类型

### BuiltinPluginDefinition

定义一个内置插件的结构：

```typescript
type BuiltinPluginDefinition = {
  name: string                      // 插件名称（用于生成 {name}@builtin ID）
  description: string              // 在 /plugin UI 中显示的描述
  version?: string                  // 版本号
  skills?: BundledSkillDefinition[] // 插件提供的技能列表
  hooks?: HooksSettings             // 插件提供的钩子配置
  mcpServers?: Record<string, McpServerConfig>  // 插件提供的 MCP 服务器
  isAvailable?: () => boolean       // 可用性检查（返回 false 时插件隐藏）
  defaultEnabled?: boolean           // 用户未设置时的默认启用状态（默认 true）
}
```

### LoadedPlugin

插件加载后的状态对象：

```typescript
type LoadedPlugin = {
  name: string
  manifest: PluginManifest
  path: string           // 文件系统路径（内置插件为 sentinel 值 'builtin'）
  source: string         // 插件源标识符，格式为 {name}@builtin
  repository: string     // 仓库标识符
  enabled?: boolean
  isBuiltin?: boolean    // 标识是否为内置插件
  sha?: string            // Git commit SHA for version pinning (from marketplace entry source)
  commandsPath?: string   // 主命令路径
  commandsPaths?: string[] // 清单中的其他命令路径
  commandsMetadata?: Record<string, CommandMetadata> // 对象映射格式的命令元数据
  agentsPath?: string     // 主代理路径
  agentsPaths?: string[]  // 清单中的其他代理路径
  skillsPath?: string     // 主技能路径
  skillsPaths?: string[]  // 清单中的其他技能路径
  outputStylesPath?: string    // 主输出样式路径
  outputStylesPaths?: string[] // 清单中的其他输出样式路径
  hooksConfig?: HooksSettings
  mcpServers?: Record<string, McpServerConfig>
  lspServers?: Record<string, LspServerConfig>
  settings?: Record<string, unknown>
}
```

## 内置插件注册机制

### 注册流程

1. **初始化阶段**：`initBuiltinPlugins()` 在 CLI 启动时被调用
2. **注册插件**：调用 `registerBuiltinPlugin(definition)` 将插件定义加入注册表
3. **加载插件**：调用 `getBuiltinPlugins()` 获取所有已注册插件（按启用/禁用分组）

### 插件 ID 格式

内置插件使用 `@builtin` 后缀区分于市场插件：

```
{pluginName}@builtin
```

例如：`code-review@builtin`、`git-hooks@builtin`

### 启用状态确定逻辑

插件的启用状态按以下优先级确定：

```
用户设置 > defaultEnabled > true（默认）
```

即：
- 如果用户明确设置过启用/禁用偏好，使用用户设置
- 否则使用插件定义的 `defaultEnabled` 值
- 如果均未设置，默认为启用（`true`）

## bundled/index.ts 核心函数

### registerBuiltinPlugin(definition)

将插件定义注册到内置插件注册表。

```typescript
export function registerBuiltinPlugin(
  definition: BuiltinPluginDefinition,
): void {
  BUILTIN_PLUGINS.set(definition.name, definition)
}
```

### isBuiltinPluginId(pluginId)

判断一个插件 ID 是否为内置插件：

```typescript
export function isBuiltinPluginId(pluginId: string): boolean {
  return pluginId.endsWith(`@${BUILTIN_MARKETPLACE_NAME}`)
}
```

### getBuiltinPlugins()

返回所有已注册的内置插件，分为启用和禁用两组：

```typescript
export function getBuiltinPlugins(): {
  enabled: LoadedPlugin[]
  disabled: LoadedPlugin[]
}
```

### getBuiltinPluginSkillCommands()

从已启用的内置插件中提取所有技能，以 `Command` 对象形式返回。这些技能会出现在 `/skills` 命令列表中。

### getBuiltinPluginDefinition(name)

根据名称获取特定的内置插件定义。用于 `/plugin` UI 显示技能/钩子/MCP 列表，无需进行市场查找。

```typescript
export function getBuiltinPluginDefinition(
  name: string,
): BuiltinPluginDefinition | undefined
```

### clearBuiltinPlugins()

清空内置插件注册表（用于测试）。

```typescript
export function clearBuiltinPlugins(): void
```

## 常量

```typescript
export const BUILTIN_MARKETPLACE_NAME = 'builtin'
```

内置插件的市场名称标识符，用于生成 `{name}@builtin` 格式的插件 ID。

## 内置插件与 Bundled Skills 的区别

| 特性 | 内置插件 (plugins/) | Bundled Skills (src/skills/bundled/) |
|------|---------------------|--------------------------------------|
| 用户可见性 | 在 `/plugin` UI 中显示 | 不显示 |
| 启用控制 | 用户可启用/禁用 | 自动启用，不可控制 |
| 可提供组件 | 技能、钩子、MCP 服务器 | 仅技能 |
| 用途 | 需要用户可控的功能 | 始终启用的内置功能 |

## 插件系统错误类型

`types/plugin.ts` 定义了完整的插件错误类型体系：

- `path-not-found` - 路径不存在
- `git-auth-failed` / `git-timeout` - Git 操作失败
- `network-error` - 网络错误
- `manifest-parse-error` / `manifest-validation-error` - 清单文件错误
- `plugin-not-found` - 插件未找到
- `mcp-config-invalid` - MCP 服务器配置无效
- `mcp-server-suppressed-duplicate` - MCP 服务器因重复被抑制
- `lsp-config-invalid` - LSP 服务器配置无效
- `lsp-server-start-failed` - LSP 服务器启动失败
- `lsp-server-crashed` - LSP 服务器崩溃
- `lsp-request-timeout` - LSP 请求超时
- `lsp-request-failed` - LSP 请求失败
- `mcpb-download-failed` - MCPB 下载失败
- `mcpb-extract-failed` - MCPB 提取失败
- `mcpb-invalid-manifest` - MCPB 清单无效
- `hook-load-failed` - 钩子加载失败
- `component-load-failed` - 组件加载失败
- `dependency-unsatisfied` - 依赖未满足
- `plugin-cache-miss` - 插件缓存未命中
- `marketplace-not-found` - 市场未找到
- `marketplace-load-failed` - 市场加载失败
- `marketplace-blocked-by-policy` - 市场被策略阻止
- `generic-error` - 通用错误

## 添加新内置插件

如需添加新的内置插件：

1. 在 `plugins/builtinPlugins.ts` 的 `initBuiltinPlugins()` 函数中调用 `registerBuiltinPlugin()`
2. 传入 `BuiltinPluginDefinition` 对象，包含插件的所有元数据和组件

```typescript
import { registerBuiltinPlugin } from '../bundled/index.js'

export function initBuiltinPlugins(): void {
  registerBuiltinPlugin({
    name: 'my-plugin',
    description: '我的插件功能描述',
    version: '1.0.0',
    skills: [...],
    hooks: {...},
    mcpServers: {...},
    defaultEnabled: true,
  })
}
```

## 相关文件

| 文件路径 | 用途 |
|----------|------|
| `types/plugin.ts` | 插件类型定义 |
| `utils/plugins/pluginLoader.ts` | 插件加载器（包含市场插件和内置插件的完整加载逻辑） |
| `utils/plugins/marketplaceManager.ts` | 市场插件管理器 |
| `utils/plugins/pluginOptionsStorage.ts` | 插件配置存储 |
| `commands/plugin/ManagePlugins.tsx` | `/plugin` 命令 UI |
