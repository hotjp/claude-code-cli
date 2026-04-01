# 键盘绑定系统 (keybindings/)

## 架构概览

键盘绑定系统管理 Claude Code CLI 的所有键盘快捷键，支持单键绑定、多键和弦（chord）序列、上下文优先级、用户自定义配置和热重载。

### 核心数据流

```typescript
~/.claude/keybindings.json → loadUserBindings.ts
         ↓
defaultBindings.ts（默认绑定）
         ↓
parseBindings() → resolver.ts → ChordInterceptor → useKeybinding.ts → Handler
```

### 核心接口

| 接口 | 说明 |
|------|------|
| `KeybindingProvider` | React Context Provider，托管所有 keybinding 状态和解析逻辑 |
| `KeybindingSetup` | 应用入口组件，组合 Provider + ChordInterceptor |
| `resolveKeyWithChordState()` | 核心解析函数，支持多键和弦匹配 |
| `parseBindings()` | 将 KeybindingBlock 数组解析为 ParsedBinding 列表 |
| `useKeybinding()` | React Hook，注册 action → handler 映射 |

### 生命周期

1. `KeybindingSetup` 初始化，同步加载默认绑定和用户绑定
2. `ChordInterceptor` 通过 `useInput` 全局拦截所有按键事件
3. `resolveKeyWithChordState()` 根据 pending chord 状态和 active contexts 解析按键
4. 匹配成功则调用注册的 handler，否则事件继续传播

### 特性门控

- 用户 keybinding 自定义仅对 Anthropic 员工开放（`tengu_keybinding_customization_release` GrowthBook gate）
- 部分快捷键受特性开关控制（`KAIROS`、`QUICK_SEARCH`、`TERMINAL_PANEL`、`MESSAGE_ACTIONS`、`VOICE_MODE`）

---

## 核心类型

### KeybindingBlock

```typescript
type KeybindingBlock = {
  context: KeybindingContextName  // 绑定生效的 UI 上下文
  bindings: Record<string, string | null>  // 键序列 → action 映射
}
```

### ParsedBinding

```typescript
type ParsedBinding = {
  chord: Chord              // 解析后的按键序列
  action: string | null    // action 名称，或 null 表示取消绑定
  context: KeybindingContextName
}
```

### ParsedKeystroke

```typescript
type ParsedKeystroke = {
  key: string    // 键名（'a', 'enter', 'escape', 'up', 'down' 等）
  ctrl: boolean
  alt: boolean
  shift: boolean
  meta: boolean
  super: boolean
}
```

### ChordResolveResult

| 类型 | 说明 |
|------|------|
| `{ type: 'match'; action }` | 完全匹配 |
| `{ type: 'none' }` | 无匹配，继续传播 |
| `{ type: 'unbound' }` | 显式取消（null 绑定） |
| `{ type: 'chord_started'; pending }` | 和弦已开始，等待后续按键 |
| `{ type: 'chord_cancelled' }` | 和弦被取消（超时或无效按键） |

---

## 上下文（Contexts）

Keybinding 上下文定义按键生效的 UI 区域。激活多个上下文时，更具体的上下文优先于 Global。

| 上下文 | 说明 |
|--------|------|
| `Global` | 全局生效 |
| `Chat` | 聊天输入框聚焦时 |
| `Autocomplete` | 自动补全菜单可见时 |
| `Confirmation` | 确认/权限对话框显示时 |
| `Help` | 帮助浮层打开时 |
| `Transcript` | 查看转录历史时 |
| `HistorySearch` | 搜索命令历史时（ctrl+r） |
| `Task` | 前台运行任务/agent 时 |
| `ThemePicker` | 主题选择器打开时 |
| `Settings` | 设置菜单打开时 |
| `Tabs` | Tab 导航激活时 |
| `Attachments` | 选择对话框中导航图片附件时 |
| `Footer` | 底部指示器聚焦时 |
| `MessageSelector` | 消息选择器（倒带）打开时 |
| `DiffDialog` | Diff 对话框打开时 |
| `ModelPicker` | 模型选择器打开时 |
| `Select` | Select/List 组件聚焦时 |
| `Scroll` | 滚动导航时 |
| `Plugin` | 插件对话框打开时 |
| `MessageActions` | 消息操作菜单打开时（`MESSAGE_ACTIONS` 特性）【注意：此上下文不在 `KEYBINDING_CONTEXTS` schema 中，是特性门控的】 |

---

## 默认绑定 (defaultBindings.ts)

**用途**: 定义所有默认键盘快捷键，按上下文分组。

### 特性开关控制的绑定

| 特性 | 绑定 | 动作 |
|------|------|------|
| `KAIROS` / `KAIROS_BRIEF` | `ctrl+shift+b` | `app:toggleBrief` |
| `QUICK_SEARCH` | `ctrl+shift+f` / `cmd+shift+f` | `app:globalSearch` |
| `QUICK_SEARCH` | `ctrl+shift+p` / `cmd+shift+p` | `app:quickOpen` |
| `TERMINAL_PANEL` | `meta+j` | `app:toggleTerminal` |
| `MESSAGE_ACTIONS` | `shift+up` | `chat:messageActions` |
| `VOICE_MODE` | `space` | `voice:pushToTalk` |

### 平台适配

| 快捷键 | 平台差异 |
|--------|----------|
| 图像粘贴 | Windows 用 `alt+v`，其他用 `ctrl+v`（避免系统粘贴冲突） |
| 模式切换 | 无 VT mode 的 Windows 用 `meta+m`，其他用 `shift+tab` |

### 保留绑定（不可重绑定）

| 快捷键 | 动作 | 原因 |
|--------|------|------|
| `ctrl+c` | `app:interrupt` | 双按机制，硬编码 |
| `ctrl+d` | `app:exit` | 硬编码 |

---

## 解析器 (parser.ts)

**用途**: 解析快捷键字符串为内部数据结构。

### 核心函数

| 函数 | 说明 |
|------|------|
| `parseKeystroke(input)` | 解析 `ctrl+shift+k` 为 `ParsedKeystroke` |
| `parseChord(input)` | 解析 `ctrl+x ctrl+k` 为 `Chord` |
| `keystrokeToString(ks)` | `ParsedKeystroke` 转规范化字符串 |
| `keystrokeToDisplayString(ks, platform)` | 转平台适配的显示字符串 |
| `chordToString(chord)` | `Chord` 转规范化字符串 |
| `chordToDisplayString(chord, platform)` | `Chord` 转平台显示字符串 |
| `parseBindings(blocks)` | 解析 `KeybindingBlock[]` 为 `ParsedBinding[]` |

### 修饰符别名

| 别名 | 标准化为 |
|------|----------|
| `ctrl` / `control` | `ctrl` |
| `alt` / `opt` / `option` / `meta` | `alt`（终端无法区分 Alt 和 Meta） |
| `cmd` / `command` / `super` / `win` | `super`（仅 kitty 键盘协议支持） |

### 特殊键名映射

| 字符串 | 转换为 |
|--------|---------|
| `esc` | `escape` |
| `return` | `enter` |
| `space` | 空格键 `' '` |
| `↑↓←→` | `up` / `down` / `left` / `right` |

---

## 匹配器 (match.ts)

**用途**: 将 Ink 的 `Key` 对象与解析后的绑定进行匹配。

### 核心函数

| 函数 | 说明 |
|------|------|
| `getKeyName(input, key)` | 从 Ink Key + input 提取规范化的键名 |
| `matchesKeystroke(input, key, target)` | 检查单个按键是否匹配 |
| `matchesBinding(input, key, binding)` | 检查绑定（单键）的第一按键是否匹配 |

### 修饰符处理

- **Alt/Meta 等价**: 终端历史上无法区分，`alt` 和 `meta` 互为别名
- **Super 独立**: 仅在支持 kitty 键盘协议的终端到达
- **Escape 特殊情况**: Ink 按下 escape 时设置 `key.meta=true`（遗留行为），匹配时需忽略

---

## 动作解析器 (resolver.ts)

**用途**: 将按键解析为动作，支持和弦（chord）状态管理。

### 核心函数

| 函数 | 说明 |
|------|------|
| `resolveKey(input, key, contexts, bindings)` | 解析单键绑定（纯函数） |
| `resolveKeyWithChordState(input, key, contexts, bindings, pending)` | 解析带和弦状态的绑定 |
| `getBindingDisplayText(action, context, bindings)` | 获取动作对应的快捷键显示文本 |
| `keystrokesEqual(a, b)` | 比较两个按键是否相等（Alt/Meta 合并） |

### 解析算法

1. 收到按键事件，构造 `ParsedKeystroke`
2. 检查是否有更长的 chord 以此为前缀（优先长匹配）
3. 检查精确匹配（last wins，用户覆盖优先）
4. 根据匹配结果返回 `ChordResolveResult`

---

## React 上下文 (KeybindingContext.tsx)

**用途**: React Context 提供者，管理全局按键解析状态和处理器注册。

### 上下文值

| 属性 | 类型 | 说明 |
|------|------|------|
| `resolve` | `(input, key, contexts) => ChordResolveResult` | 解析按键 |
| `setPendingChord` | `(pending) => void` | 更新待处理和弦 |
| `getDisplayText` | `(action, context) => string \| undefined` | 获取动作的显示文本 |
| `bindings` | `ParsedBinding[]` | 所有解析后的绑定 |
| `pendingChord` | `ParsedKeystroke[] \| null` | 当前待处理和弦 |
| `activeContexts` | `Set<KeybindingContextName>` | 当前激活的上下文 |
| `registerHandler` | `(registration) => () => void` | 注册动作处理器 |
| `invokeAction` | `(action) => boolean` | 调用动作的所有处理器 |

### Hooks

| Hook | 说明 |
|------|------|
| `useKeybindingContext()` | 获取上下文（必须在 Provider 内） |
| `useOptionalKeybindingContext()` | 获取上下文（可在 Provider 外返回 null） |
| `useRegisterKeybindingContext(context, isActive)` | 注册上下文为激活状态（自动取消注册） |

---

## 提供者设置 (KeybindingProviderSetup.tsx)

**用途**: 组合 `KeybindingProvider` + 文件监听 + 和弦拦截 + 警告通知。

### 组件

| 组件 | 说明 |
|------|------|
| `KeybindingSetup` | 主入口，包装整个应用 |
| `ChordInterceptor` | 全局和弦拦截器，通过 `useInput` 在所有子组件之前处理按键 |

### ChordInterceptor 职责

- 拦截组成 chord 序列的按键，防止 PromptInput 等组件提前捕获
- 管理 pending chord 状态和超时（1000ms）
- 调用 `resolveKeyWithChordState()` 解析按键

### 关键常量

| 常量 | 值 | 说明 |
|------|------|------|
| `CHORD_TIMEOUT_MS` | `1000` | chord 完成超时时间（毫秒） |

---

## 用户绑定加载 (loadUserBindings.ts)

**用途**: 加载和缓存用户自定义绑定，支持热重载。

### 核心函数

| 函数 | 说明 |
|------|------|
| `isKeybindingCustomizationEnabled()` | 检查用户定制是否启用（GrowthBook gate） |
| `getKeybindingsPath()` | 返回 `~/.claude/keybindings.json` |
| `loadKeybindings()` | 异步加载（首次和热重载） |
| `loadKeybindingsSync()` | 同步加载（React useState 初始化） |
| `loadKeybindingsSyncWithWarnings()` | 同步加载并返回验证警告 |
| `initializeKeybindingWatcher()` | 启动文件监听（导出函数，支持热重载） |
| `subscribeToKeybindingChanges(callback)` | 订阅配置变更事件（导出函数，供外部使用） |

### 文件格式

```json
{
  "$schema": "https://www.schemastore.org/claude-code-keybindings.json",
  "$docs": "https://code.claude.com/docs/en/keybindings",
  "bindings": [
    { "context": "Chat", "bindings": { "ctrl+b": "chat:stash" } }
  ]
}
```

### 验证流程

1. JSON 解析
2. 结构校验（必须有 `bindings` 数组）
3. 每个 block 校验 context 和 bindings 结构
4. JSON 内重复键检测（JSON.parse 静默使用最后一个值）
5. 用户绑定与默认绑定合并（用户覆盖默认）

### 热重载配置

| 配置 | 值 |
|------|------|
| 文件稳定等待 | 500ms |
| 轮询间隔 | 200ms |
| 删除文件行为 | 重置为默认绑定 |

---

## 保留快捷键 (reservedShortcuts.ts)

**用途**: 定义不可重绑或终端保留的快捷键。

### 保留快捷键

| 快捷键 | 原因 | 严重性 |
|--------|------|--------|
| `ctrl+c` | 不可重绑定 — 用于中断/退出（硬编码） | error |
| `ctrl+d` | 不可重绑定 — 用于退出（硬编码） | error |
| `ctrl+m` | 不可重绑定 — 与 Enter 等价（都发送 CR） | error |
| `ctrl+z` | Unix 进程挂起（SIGTSTP） | warning |
| `ctrl+\` | 终端退出信号（SIGQUIT） | error |

### macOS 保留

| 快捷键 | 原因 |
|--------|------|
| `cmd+c` / `cmd+v` / `cmd+x` | 系统复制/粘贴/剪切 |
| `cmd+q` | 系统退出应用 |
| `cmd+w` | 系统关闭窗口/标签 |
| `cmd+tab` | 系统应用切换器 |
| `cmd+space` | Spotlight 搜索 |

### 规范化

`normalizeKeyForComparison()` 将快捷键字符串规范化用于比较，包括修饰符排序和别名标准化。

---

## Schema (schema.ts)

**用途**: Zod schema 定义，用于验证和生成 `keybindings.json` 的 JSON Schema。

### 常量

| 常量 | 说明 |
|------|------|
| `KEYBINDING_CONTEXTS` | 所有有效的上下文名称数组 |
| `KEYBINDING_CONTEXT_DESCRIPTIONS` | 每个上下文的描述映射 |
| `KEYBINDING_ACTIONS` | 所有有效的动作名称数组 |

### Schema

| Schema | 说明 |
|--------|------|
| `KeybindingBlockSchema` | 单个上下文块的 schema |
| `KeybindingsSchema` | 整个配置文件的 schema |

### 支持的 action 类型

| 类型 | 格式 | 说明 |
|------|------|------|
| 枚举值 | 任意 `KEYBINDING_ACTIONS` | 预定义动作（如 `diff:back`、`diff:dismiss` 等） |
| 命令绑定 | `command:<name>` | 执行斜杠命令 |
| 解绑 | `null` | 显式取消绑定 |

---

## 快捷键显示 (shortcutFormat.ts)

**用途**: 格式化快捷键为人类可读的显示文本。

### 核心函数

| 函数 | 说明 |
|------|------|
| `keystrokeToDisplayString(ks, platform)` | 平台适化的单按键显示 |
| `chordToDisplayString(chord, platform)` | 平台适化的和弦显示 |
| `keyToDisplayName(key)` | 内部键名到显示名 |

### 平台差异

- macOS: `opt` 显示为 alt，`cmd` 显示为 cmd
- 其他平台: `alt` 显示为 alt，`super` 显示为 super

---

## 模板生成 (template.ts)

**用途**: 生成 `keybindings.json` 模板文件。

### 核心函数

| 函数 | 说明 |
|------|------|
| `generateKeybindingsTemplate()` | 生成完整的模板 JSON，过滤保留快捷键 |

### 过滤逻辑

模板自动排除 `NON_REBINDABLE` 快捷键，避免用户设置后收到警告。

---

## Hook (useKeybinding.ts)

**用途**: React Hook，用于组件中注册和处理键盘绑定。

### Hooks

| Hook | 说明 |
|------|------|
| `useKeybinding(action, handler, options)` | 处理单个动作的快捷键 |
| `useKeybindings(handlers, options)` | 在一个 Hook 中处理多个快捷键 |

### Options

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `context` | `KeybindingContextName` | `'Global'` | 所属上下文 |
| `isActive` | `boolean` | `true` | 是否处理输入 |

### Handler 返回值

| 返回值 | 行为 |
|--------|------|
| `void` / `Promise<void>` | 消费事件，阻止传播 |
| `false` | 未消费，允许传播到其他处理器 |

### 和弦支持

自动管理待处理和弦状态，当 `resolve()` 返回 `chord_started` 时更新状态。

---

## 非 React 显示 (useShortcutDisplay.ts)

**用途**: 在非 React 上下文中获取快捷键显示文本。

### 核心函数

| 函数 | 说明 |
|------|------|
| `getShortcutDisplay(action, context, fallback)` | 获取动作的快捷键显示文本，不存在则返回 fallback |

**用途**: 命令、服务等非 React 代码中使用，避免引入 React 依赖。

---

## 验证 (validate.ts)

**用途**: 验证用户 `keybindings.json` 配置，发现问题并生成警告。

### 警告类型

| 类型 | 严重性 | 说明 |
|------|--------|------|
| `parse_error` | error | JSON 解析或结构错误 |
| `duplicate` | warning | 同一上下文中重复的绑定 |
| `reserved` | error/warning | 保留快捷键（如 macOS cmd+c） |
| `invalid_context` | error | 上下文名称无效 |
| `invalid_action` | error/warning | 动作名称或格式无效 |

### 核心函数

| 函数 | 说明 |
|------|------|
| `validateBindings(userBlocks, parsedBindings)` | 运行所有验证并返回警告 |
| `validateUserConfig(userBlocks)` | 验证用户配置结构 |
| `checkDuplicates(blocks)` | 检查同一上下文中的重复绑定 |
| `checkReservedShortcuts(bindings)` | 检查保留快捷键 |
| `checkDuplicateKeysInJson(jsonString)` | 检查 JSON 中的重复键 |
| `formatWarning(warning)` | 格式化单个警告 |
| `formatWarnings(warnings)` | 格式化多个警告 |

### 特殊验证

- **命令绑定**: 必须在 `Chat` 上下文中
- **语音绑定**: bare 字母键会打印到输入框，建议用 space 或 modifier 组合
- **JSON 重复键**: 检测并警告（JSON.parse 只会保留最后一个值）

---

## 文件索引

| 文件 | 说明 |
|------|------|
| `defaultBindings.ts` | 默认快捷键定义（按上下文分组） |
| `parser.ts` | 快捷键字符串解析为结构化数据 |
| `match.ts` | Ink Key 对象与 ParsedKeystroke 的匹配 |
| `resolver.ts` | 按键到动作的解析（含和弦支持） |
| `KeybindingContext.tsx` | React Context 提供者 |
| `KeybindingProviderSetup.tsx` | 提供者设置、文件监听、和弦拦截 |
| `loadUserBindings.ts` | 用户绑定加载和热重载 |
| `reservedShortcuts.ts` | 不可重绑/终端保留快捷键 |
| `schema.ts` | Zod schema 和有效值常量 |
| `shortcutFormat.ts` | 快捷键显示格式化 |
| `template.ts` | keybindings.json 模板生成 |
| `useKeybinding.ts` | React Hook 注册快捷键处理 |
| `useShortcutDisplay.ts` | 非 React 上下文的快捷键显示 |
| `validate.ts` | 配置验证和警告 |
