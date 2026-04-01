# Moreright 模块 (moreright/)

## 架构概览

Moreright 模块是 Claude Code CLI 的一个实验性内部钩子模块，用于在 REPL 会话中提供增强的用户交互能力。该模块在外部构建（external）中为存根（stub）实现，真实逻辑为内部专用。

核心入口为 `useMoreRight` 钩子，在 `screens/REPL.tsx` 中被调用。

### 激活条件

```typescript
const moreRightEnabled = useMemo(() => "external" === 'ant' && isEnvTruthy(process.env.CLAUDE_MORERIGHT), []);
```

由于 `"external" === 'ant'` 始终为 `false`（字面量字符串比较），该功能在当前代码库中**永远不会被激活**。这是一个编译时特性门控的占位实现。

### 核心接口

| 接口 | 类型 | 说明 |
|------|------|------|
| `useMoreRight(args)` | `(args: HookArgs) => Hook` | 主钩子，接收参数并返回三个处理函数 |
| `Hook.onBeforeQuery` | `(input, all, n) => Promise<boolean>` | 查询前回调，返回 `true` 表示放行 |
| `Hook.onTurnComplete` | `(all, aborted) => Promise<void>` | 轮次完成回调 |
| `Hook.render` | `() => null` | 渲染函数，当前返回 `null` |

### HookArgs 入参结构

| 字段 | 类型 | 说明 |
|------|------|------|
| `enabled` | `boolean` | 是否启用（当前始终为 `false`） |
| `setMessages` | `(action: M[] \| ((prev: M[]) => M[])) => void` | 设置消息列表 |
| `inputValue` | `string` | 当前输入值 |
| `setInputValue` | `(s: string) => void` | 设置输入值 |
| `setToolJSX` | `(args: M) => void` | 设置工具 JSX |

> 注: `M` 是文件内部类型别名，定义为 `type M = any`（用于stub构建兼容性，见 `moreright/useMoreRight.tsx:8`）。

---

## 文件索引

### useMoreRight.tsx

**用途**: `useMoreRight` 钩子的存根实现，供外部构建使用。

- **文件**: `moreright/useMoreRight.tsx`
- **类型**: 存根（stub）
- **特性**: 自包含，无相对导入

**实现逻辑**:
- `onBeforeQuery: async () => true` — 不拦截任何查询
- `onTurnComplete: async () => {}` — 空操作
- `render: () => null` — 不渲染任何 UI

**设计目的**:
- 该 stub 确保外部构建系统的模块解析完整性
- 文件注释明确说明：真正的钩子实现是 internal only
- 内联 base64 source map 允许调试时还原源码

---

## 在 REPL 中的调用

**调用位置**: `screens/REPL.tsx:1665`

```typescript
const {
  onBeforeQuery: mrOnBeforeQuery,
  onTurnComplete: mrOnTurnComplete,
  render: mrRender
} = useMoreRight({
  enabled: moreRightEnabled,
  setMessages,
  inputValue,
  setInputValue,
  setToolJSX
});
```

返回值被重命名（`mr*` 前缀）以与 REPL 内部其他同名变量区分。

---

## 模块依赖关系

```
REPL.tsx 的 moreright 依赖

screens/REPL.tsx
    ├── 导入 moreright/useMoreRight.tsx（作为 stub）
    └── 其他依赖:
        ├── hooks/useAssistantHistory.ts
        ├── hooks/useSSHSession.ts
        ├── components/Spinner.ts
        └── components/SkillImprovementSurvey.ts
```

---

## 注意事项

- 该模块在外部构建中始终为存根，真实增强逻辑属于内部实现
- 由于特性门控 `"external" === 'ant'` 永远为 `false`，该功能在当前代码库中不可用
- 存根的 `onBeforeQuery` 始终返回 `true`，`onTurnComplete` 为空操作
- `render()` 返回 `null`，不渲染任何 UI
