# UI 组件、React Hooks 与终端渲染引擎

本文档涵盖三个核心前端目录：`components/`（UI 组件）、`hooks/`（React Hooks）和 `ink/`（终端渲染引擎）。

---

# UI 组件 (components/)

所有终端 UI 的 React 组件，按子目录分组。

---

## design-system/ — 设计系统基础组件

主题感知的可复用 UI 原语，提供一致的视觉体验。

### ThemeProvider

**文件**: `components/design-system/ThemeProvider.tsx`

主题上下文提供者，管理主题设置的保存、预览和自动切换。

| Props | 类型 | 说明 |
|---|---|---|
| `children` | `React.ReactNode` | 子组件 |
| `initialState` | `ThemeSetting` | 初始主题设置（可选） |
| `onThemeSave` | `(setting: ThemeSetting) => void` | 主题保存回调（可选） |

**上下文值** (`ThemeContextValue`):
- `themeSetting` — 用户保存的主题偏好（可能为 `'auto'`）
- `setThemeSetting` / `setPreviewTheme` — 设置/预览主题
- `savePreview` / `cancelPreview` — 保存/取消预览
- `currentTheme` — 解析后的实际主题（永远不是 `'auto'`）

**关联 Hook**: `useTheme()` / `usePreviewTheme()` / `useThemeSetting()`

---

### ThemedText

**文件**: `components/design-system/ThemedText.tsx`

主题感知的文本组件，自动将主题键解析为实际颜色值。支持 `TextHoverColorContext` 跨 Box 边界传递颜色。

| Props | 类型 | 说明 |
|---|---|---|
| `color` | `keyof Theme \| Color` | 文本颜色，接受主题键或原始颜色 |
| `backgroundColor` | `keyof Theme` | 背景色（仅主题键） |
| `dimColor` | `boolean` | 使用主题的 inactive 颜色 |
| `bold` | `boolean` | 粗体 |
| `italic` | `boolean` | 斜体 |
| `underline` | `boolean` | 下划线 |
| `strikethrough` | `boolean` | 删除线 |
| `inverse` | `boolean` | 前景/背景反色 |
| `wrap` | `Styles['textWrap']` | 换行/截断模式 |
| `children` | `ReactNode` | 子内容 |

---

### ThemedBox

**文件**: `components/design-system/ThemedBox.tsx`

主题感知的 Box 容器组件，自动将主题颜色键解析为原始颜色值，用于边框色和背景色。

| Props | 类型 | 说明 |
|---|---|---|
| `borderColor` | `keyof Theme \| Color` | 边框颜色 |
| `borderTopColor` / `borderBottomColor` / `borderLeftColor` / `borderRightColor` | `keyof Theme \| Color` | 各方向边框色 |
| `backgroundColor` | `keyof Theme \| Color` | 背景色 |
| `tabIndex` | `number` | Tab 导航索引 |
| `autoFocus` | `boolean` | 自动聚焦 |
| `onClick` / `onFocus` / `onBlur` / `onKeyDown` | 事件回调 | 交互事件 |
| `onMouseEnter` / `onMouseLeave` | `() => void` | 鼠标进出 |

---

### color()

**文件**: `components/design-system/color.ts`

柯里化主题感知颜色函数。接受主题键或原始颜色值，返回文本着色函数。

```ts
function color(c: keyof Theme | Color | undefined, theme: ThemeName, type?: ColorType): (text: string) => string
```

---

### StatusIcon

**文件**: `components/design-system/StatusIcon.tsx`

渲染状态指示图标，自动匹配颜色和图标。

| Props | 类型 | 说明 |
|---|---|---|
| `status` | `'success' \| 'error' \| 'warning' \| 'info' \| 'pending' \| 'loading'` | 状态类型 |
| `withSpace` | `boolean` | 图标后添加空格（默认 `false`） |

状态映射：`success`→✓/绿, `error`→✗/红, `warning`→⚠/黄, `info`→ℹ/蓝, `pending`→○/暗淡, `loading`→…/暗淡

---

### LoadingState

**文件**: `components/design-system/LoadingState.tsx`

带加载动画的异步操作状态指示器。

| Props | 类型 | 说明 |
|---|---|---|
| `message` | `string` | 加载提示文本 |
| `bold` | `boolean` | 粗体显示（默认 `false`） |
| `dimColor` | `boolean` | 暗淡显示（默认 `false`） |
| `subtitle` | `string` | 副标题（可选） |

---

### Tabs / Tab

**文件**: `components/design-system/Tabs.tsx`

选项卡容器组件，支持受控/非受控模式、键盘导航和内容固定高度。

| Tabs Props | 类型 | 说明 |
|---|---|---|
| `children` | `React.ReactElement<TabProps>[]` | Tab 子组件数组 |
| `title` | `string` | 标题 |
| `color` | `keyof Theme` | 主题色 |
| `defaultTab` | `string` | 默认选中 Tab |
| `selectedTab` | `string` | 受控模式当前 Tab |
| `onTabChange` | `(tabId: string) => void` | Tab 切换回调 |
| `banner` | `React.ReactNode` | Tab 栏下方的横幅 |
| `disableNavigation` | `boolean` | 禁用键盘导航 |
| `initialHeaderFocused` | `boolean` | 初始焦点在 Tab 栏（默认 `true`） |
| `contentHeight` | `number` | 内容区固定高度 |
| `navFromContent` | `boolean` | 允许从内容区用 Tab/箭头切换 |
| `hidden` | `boolean` | 隐藏 Tab（可选） |
| `useFullWidth` | `boolean` | 全宽模式（可选） |

---

### FuzzyPicker\<T\>

**文件**: `components/design-system/FuzzyPicker.tsx`

通用模糊搜索选择器，支持预览、多操作键和方向控制。

| Props | 类型 | 说明 |
|---|---|---|
| `title` | `string` | 标题 |
| `placeholder` | `string` | 占位文本 |
| `items` | `readonly T[]` | 数据源 |
| `getKey` | `(item: T) => string` | 唯一键提取 |
| `renderItem` | `(item: T, isFocused: boolean) => ReactNode` | 渲染列表项 |
| `renderPreview` | `(item: T) => ReactNode` | 渲染预览（可选） |
| `previewPosition` | `'bottom' \| 'right'` | 预览位置（默认 `'bottom'`） |
| `direction` | `'down' \| 'up'` | 列表方向 |
| `onQueryChange` | `(query: string) => void` | 查询变更回调 |
| `onSelect` | `(item: T) => void` | Enter 选择回调 |
| `onTab` / `onShiftTab` | `PickerAction<T>` | Tab/Shift+Tab 操作 |
| `onFocus` | `(item: T \| undefined) => void` | 焦点变更回调 |
| `onCancel` | `() => void` | 取消回调 |
| `emptyMessage` | `string \| ((query: string) => string)` | 空列表消息 |
| `initialQuery` | `string` | 初始查询文本（可选） |
| `visibleCount` | `number` | 可见项数量（可选） |
| `matchLabel` | `string` | 标签匹配（可选） |
| `selectAction` | `string` | 选择操作（可选） |
| `extraHints` | `React.ReactNode` | 额外提示（可选） |

---

### Dialog

**文件**: `components/design-system/Dialog.tsx`

确认/取消对话框，自动注册 Esc 取消和 Ctrl+C/D 退出键绑定。

| Props | 类型 | 说明 |
|---|---|---|
| `title` | `React.ReactNode` | 标题 |
| `subtitle` | `React.ReactNode` | 副标题 |
| `children` | `React.ReactNode` | 对话框内容 |
| `onCancel` | `() => void` | 取消回调 |
| `color` | `keyof Theme` | 主题色（默认 `'permission'`） |
| `hideInputGuide` | `boolean` | 隐藏输入提示 |
| `hideBorder` | `boolean` | 隐藏边框 |
| `inputGuide` | `(exitState: ExitState) => ReactNode` | 自定义输入提示 |
| `isCancelActive` | `boolean` | 是否激活取消键绑定（默认 `true`） |

---

### Pane

**文件**: `components/design-system/Pane.tsx`

面板容器——出现在 REPL 提示符下方的区域，顶部有彩色分割线。用于所有斜杠命令界面（`/config`、`/help` 等）。

| Props | 类型 | 说明 |
|---|---|---|
| `children` | `React.ReactNode` | 子内容 |
| `color` | `keyof Theme` | 顶部边框线颜色 |

---

### Divider

**文件**: `components/design-system/Divider.tsx`

水平分割线，支持居中标题。

| Props | 类型 | 说明 |
|---|---|---|
| `width` | `number` | 宽度（字符数），默认终端宽度 |
| `color` | `keyof Theme` | 颜色 |
| `char` | `string` | 分割线字符（默认 `'─'`） |
| `padding` | `number` | 缩进宽度（默认 `0`） |
| `title` | `string` | 居中标题文本 |

---

### ListItem

**文件**: `components/design-system/ListItem.tsx`

列表选择项，自动显示焦点指示符（❯）、选中标记（✓）和滚动提示（↓↑）。

| Props | 类型 | 说明 |
|---|---|---|
| `isFocused` | `boolean` | 是否聚焦 |
| `isSelected` | `boolean` | 是否选中 |
| `children` | `ReactNode` | 内容 |
| `description` | `string` | 描述文本 |
| `showScrollDown` / `showScrollUp` | `boolean` | 滚动提示 |
| `styled` | `boolean` | 自动应用焦点/选中样式（默认 `true`） |
| `disabled` | `boolean` | 禁用状态 |
| `declareCursor` | `boolean` | 声明终端光标位置 |

---

### ProgressBar

**文件**: `components/design-system/ProgressBar.tsx`

Unicode 块状进度条，支持亚字符精度。

| Props | 类型 | 说明 |
|---|---|---|
| `ratio` | `number` | 进度比例 [0, 1] |
| `width` | `number` | 字符宽度 |
| `fillColor` | `keyof Theme` | 填充色 |
| `emptyColor` | `keyof Theme` | 空白色 |

---

### Ratchet

**文件**: `components/design-system/Ratchet.tsx`

"棘轮"布局组件——内容高度只增不减，防止内容缩小导致的布局跳动。

| Props | 类型 | 说明 |
|---|---|---|
| `children` | `React.ReactNode` | 子内容 |
| `lock` | `'always' \| 'offscreen'` | 锁定模式（默认 `'always'`） |

---

### KeyboardShortcutHint

**文件**: `components/design-system/KeyboardShortcutHint.tsx`

渲染键盘快捷键提示文本，如 "ctrl+o to expand"。

| Props | 类型 | 说明 |
|---|---|---|
| `shortcut` | `string` | 按键名称 |
| `action` | `string` | 操作描述 |
| `parens` | `boolean` | 括号包裹 |
| `bold` | `boolean` | 快捷键加粗 |

---

### Byline

**文件**: `components/design-system/Byline.tsx`

用中间点分隔符（`·`）连接子元素的内联元数据组件。自动过滤 null/undefined/false 子元素。

| Props | 类型 | 说明 |
|---|---|---|
| `children` | `React.ReactNode` | 要连接的元素 |

---

## CustomSelect/ — 自定义选择组件

### Select\<T\>

**文件**: `CustomSelect/select.tsx`

功能完整的单选列表组件，支持文本输入选项、分页、描述和禁用状态。

| Props | 类型 | 说明 |
|---|---|---|
| `options` | `OptionWithDescription<T>[]` | 选项列表 |
| `onChange` | `(value: T) => void` | 选择变更回调 |
| `onCancel` | `() => void` | 取消回调 |
| `isDisabled` | `boolean` | 是否禁用 |
| `visibleOptionCount` | `number` | 可见选项数量 |
| `defaultValue` | `T` | 默认值 |
| `onFocus` | `(value: T) => void` | 焦点变更回调 |
| `focusValue` | `T` | 受控焦点值 |

`OptionWithDescription` 支持两种类型：
- `type: 'text'` — 纯文本选项
- `type: 'input'` — 带内联文本输入的选项

---

### SelectMulti\<T\>

**文件**: `CustomSelect/SelectMulti.tsx`

多选列表组件，支持 Space 切换选择、提交按钮和图片粘贴。

| Props | 类型 | 说明 |
|---|---|---|
| `options` | `OptionWithDescription<T>[]` | 选项列表 |
| `defaultValue` | `T[]` | 默认选中值 |
| `onChange` | `(values: T[]) => void` | 选择变更回调 |
| `onSubmit` | `(values: T[]) => void` | 提交回调 |
| `submitButtonText` | `string` | 提交按钮文本 |
| `hideIndexes` | `boolean` | 隐藏序号 |
| `initialFocusLast` | `boolean` | 初始聚焦最后一项 |
| `onOpenEditor` | `(currentValue: string, setValue: (value: string) => void) => void` | 打开编辑器回调 |

---

### 辅助 Hooks（CustomSelect/）

| Hook | 文件 | 用途 |
|---|---|---|
| `useSelectInput` | `use-select-input.ts` | 处理选择列表的键盘输入 |
| `useSelectState` | `use-select-state.ts` | 单选状态管理 |
| `useMultiSelectState` | `use-multi-select-state.ts` | 多选状态管理 |
| `useSelectNavigation` | `use-select-navigation.ts` | 上下箭头导航逻辑 |
| `optionMap` | `option-map.ts` | 选项索引和值映射 |

---

## PromptInput/ — 提示输入组件

### PromptInput

**文件**: `PromptInput/PromptInput.tsx`（~2339 行）

主输入组件，处理用户输入的完整生命周期：多行编辑、历史搜索、粘贴处理、图片粘贴、Vim 模式、自动补全等。

核心功能：
- 多模式输入（`prompt` / `multiline` / `vim` 等）
- 历史记录浏览与搜索
- 图片粘贴与预览
- 命令队列处理
- 快捷模式选择器
- Tab 自动补全（文件、命令、@提及）
- Agent/Swarm 任务管理

---

### PromptInput 子组件

| 组件 | 文件 | 用途 |
|---|---|---|
| `PromptInputFooter` | `PromptInputFooter.tsx` | 输入框底部栏 |
| `PromptInputFooterLeftSide` | `PromptInputFooterLeftSide.tsx` | 底部栏左侧（模型、模式指示） |
| `PromptInputFooterSuggestions` | `PromptInputFooterSuggestions.tsx` | 输入建议列表 |
| `PromptInputHelpMenu` | `PromptInputHelpMenu.tsx` | 帮助菜单 |
| `PromptInputModeIndicator` | `PromptInputModeIndicator.tsx` | 输入模式指示器 |
| `PromptInputQueuedCommands` | `PromptInputQueuedCommands.tsx` | 排队命令显示 |
| `PromptInputStashNotice` | `PromptInputStashNotice.tsx` | Stash 通知 |
| `ShimmeredInput` | `ShimmeredInput.tsx` | 带闪烁效果的输入框 |
| `HistorySearchInput` | `HistorySearchInput.tsx` | 历史搜索输入框 |
| `Notifications` | `Notifications.tsx` | 通知栏 |
| `VoiceIndicator` | `VoiceIndicator.tsx` | 语音输入指示器 |
| `SandboxPromptFooterHint` | `SandboxPromptFooterHint.tsx` | 沙箱模式提示 |
| `IssueFlagBanner` | `IssueFlagBanner.tsx` | Issue 标记横幅 |

---

### PromptInput 辅助模块

| 模块 | 文件 | 用途 |
|---|---|---|
| `inputPaste` | `inputPaste.ts` | 粘贴文本处理逻辑 |
| `inputModes` | `inputModes.ts` | 输入模式定义与切换 |
| `useMaybeTruncateInput` | `useMaybeTruncateInput.ts` | 超长输入截断 |
| `useShowFastIconHint` | `useShowFastIconHint.ts` | 快速模式图标提示 |
| `usePromptInputPlaceholder` | `usePromptInputPlaceholder.ts` | 输入框占位符 |
| `useSwarmBanner` | `useSwarmBanner.ts` | Swarm 横幅逻辑 |
| `utils` | `utils.ts` | 通用工具函数 |

---

## LogoV2/ — 启动画面组件

### LogoV2

**文件**: `LogoV2/LogoV2.tsx`

启动欢迎界面，展示 Logo、项目信息、最近活动、发布公告和快捷操作。

| 子组件 | 文件 | 用途 |
|---|---|---|
| `Clawd` | `Clawd.tsx` | Claude ASCII art Logo |
| `AnimatedClawd` | `AnimatedClawd.tsx` | 动画版 Logo |
| `AnimatedAsterisk` | `AnimatedAsterisk.tsx` | 动画星号 |
| `CondensedLogo` | `CondensedLogo.tsx` | 精简版 Logo |
| `Feed` / `FeedColumn` | `Feed.tsx` / `FeedColumn.tsx` | 信息流布局 |
| `feedConfigs` | `feedConfigs.tsx` | 信息流配置（最近活动、发布公告等） |
| `WelcomeV2` | `WelcomeV2.tsx` | 欢迎信息 |
| `GuestPassesUpsell` | `GuestPassesUpsell.tsx` | 访客通行证推广 |
| `OverageCreditUpsell` | `OverageCreditUpsell.tsx` | 超额额度推广 |
| `EmergencyTip` | `EmergencyTip.tsx` | 紧急提示 |
| `VoiceModeNotice` | `VoiceModeNotice.tsx` | 语音模式通知 |
| `Opus1mMergeNotice` | `Opus1mMergeNotice.tsx` | Opus 1M 合并通知 |
| `ChannelsNotice` | `ChannelsNotice.tsx` | Channels 通知 |

---

## skills/ — 技能菜单

### SkillsMenu

**文件**: `skills/SkillsMenu.tsx`

技能（slash commands）管理界面，按来源分组展示已加载的技能。

| Props | 类型 | 说明 |
|---|---|---|
| `onExit` | `(result?: string, options?) => void` | 退出回调 |
| `commands` | `Command[]` | 命令列表 |

---

## 根级组件

### Message

**文件**: `Message.tsx`（~627 行）

消息渲染分发器——根据消息类型（用户文本、助手文本、工具调用、工具结果、系统消息等）路由到对应的渲染子组件。

| Props | 类型 | 说明 |
|---|---|---|
| `message` | `NormalizedUserMessage \| AssistantMessage \| ...` | 消息对象 |
| `lookups` | `ReturnType<typeof buildMessageLookups>` | 消息查找表 |
| `containerWidth` | `number` | 容器宽度 |
| `addMargin` | `boolean` | 添加间距 |
| `tools` | `Tools` | 工具注册表 |
| `verbose` | `boolean` | 详细模式 |
| `inProgressToolUseIDs` | `Set<string>` | 进行中的工具调用 ID |
| `shouldAnimate` | `boolean` | 是否播放动画 |
| `isTranscriptMode` | `boolean` | 是否为 transcript 模式 |
| `isStatic` | `boolean` | 是否静态渲染 |

---

### Messages

**文件**: `Messages.tsx`（~834 行）

消息列表容器，管理消息规范化、折叠分组、虚拟列表和滚动状态。

核心功能：
- 消息规范化与重排序
- 后台 Bash 通知折叠
- Hook 摘要折叠
- 读取/搜索分组折叠
- 虚拟列表集成
- 搜索高亮与导航

---

### VirtualMessageList

**文件**: `VirtualMessageList.tsx`（~1082 行）

虚拟滚动消息列表，实现高效的大规模消息渲染。

| Props | 类型 | 说明 |
|---|---|---|
| `messages` | `RenderableMessage[]` | 消息列表 |
| `scrollRef` | `RefObject<ScrollBoxHandle>` | 滚动引用 |
| `columns` | `number` | 列数 |
| `itemKey` | `(msg) => string` | 消息唯一键 |
| `renderItem` | `(msg, index) => ReactNode` | 渲染单项 |

**命令式句柄** (`JumpHandle`):
- `jumpToIndex(i)` — 跳转到指定索引
- `setSearchQuery(q)` — 设置搜索查询
- `nextMatch()` / `prevMatch()` — 下一个/上一个匹配
- `setAnchor()` — 设置搜索锚点
- `warmSearchIndex()` — 预热搜索索引
- `disarmSearch()` — 解除搜索高亮

---

### MessageRow

**文件**: `MessageRow.tsx`

单行消息包装器，处理消息间距、OffscreenFreeze 和折叠组状态。

| Props | 类型 | 说明 |
|---|---|---|
| `message` | `RenderableMessage` | 消息 |
| `isUserContinuation` | `boolean` | 是否连续用户消息 |
| `hasContentAfter` | `boolean` | 后续是否有内容 |
| `tools` / `commands` / `verbose` | — | 透传给 Message |
| `inProgressToolUseIDs` / `streamingToolUseIDs` | `Set<string>` | 进行中/流式工具 ID |
| `screen` | `Screen` | 当前屏幕 |
| `canAnimate` | `boolean` | 是否可动画 |

---

### Spinner

**文件**: `Spinner.tsx`（~562 行）

加载状态指示器，显示动画旋转字符、当前活动描述、任务进度和 token 消耗信息。

核心功能：
- 多种动画帧样式
- 任务树展示（多 Agent 进度）
- Token 预算显示
- Shimmer 效果

---

### ScrollKeybindingHandler

**文件**: `ScrollKeybindingHandler.tsx`（~1012 行）

滚动键绑定处理器，管理滚轮加速、键盘滚动、选择和复制。

| Props | 类型 | 说明 |
|---|---|---|
| `scrollRef` | `RefObject<ScrollBoxHandle>` | 滚动引用 |
| `isActive` | `boolean` | 是否激活 |
| `onScroll` | `(sticky, handle) => void` | 滚动回调 |
| `isModal` | `boolean` | 启用分页器模式（g/G/Ctrl+U/D/B/F） |

---

### ThemePicker

**文件**: `ThemePicker.tsx`（~333 行）

主题选择器界面，支持实时预览和语法高亮预览。

| Props | 类型 | 说明 |
|---|---|---|
| `onThemeSelect` | `(setting: ThemeSetting) => void` | 选择回调 |
| `showIntroText` | `boolean` | 显示介绍文本 |
| `helpText` | `string` | 帮助文本 |
| `hideEscToCancel` | `boolean` | 隐藏 Esc 取消提示 |
| `skipExitHandling` | `boolean` | 跳过退出处理 |
| `onCancel` | `() => void` | 取消回调 |

---

### 其他根级组件

| 组件 | 文件 | 用途 |
|---|---|---|
| `Feedback` | `Feedback.tsx` | 用户反馈提交界面（GitHub Issue） |
| `ConsoleOAuthFlow` | `ConsoleOAuthFlow.tsx` | OAuth 登录流程 |
| `BridgeDialog` | `BridgeDialog.tsx` | Bridge 远程连接对话框（含二维码） |
| `HistorySearchDialog` | `HistorySearchDialog.tsx` | 历史记录搜索对话框 |
| `OffscreenFreeze` | `OffscreenFreeze.tsx` | 离屏内容冻结优化 |
| `ToolUseLoader` | `ToolUseLoader.tsx` | 工具调用加载指示器（闪烁圆点） |
| `TokenWarning` | `TokenWarning.tsx` | Token 用量警告 |
| `FastIcon` | `FastIcon.tsx` | 快速模式闪电图标 |
| `EffortCallout` | `EffortCallout.tsx` | Effort 级别选择弹出框 |
| `DiagnosticsDisplay` | `DiagnosticsDisplay.tsx` | 诊断信息展示 |
| `DevBar` | `DevBar.tsx` | 开发者性能调试栏 |
| `AgentProgressLine` | `AgentProgressLine.tsx` | Agent 进度行 |
| `PressEnterToContinue` | `PressEnterToContinue.tsx` | "按 Enter 继续" 提示 |
| `BypassPermissionsModeDialog` | `BypassPermissionsModeDialog.tsx` | 权限绕过确认对话框 |
| `InvalidSettingsDialog` | `InvalidSettingsDialog.tsx` | 无效设置对话框 |
| `ShowInIDEPrompt` | `ShowInIDEPrompt.tsx` | IDE 中打开提示 |
| `RemoteCallout` | `RemoteCallout.tsx` | 远程会话提示 |
| `TeleportError` | `TeleportError.tsx` | Teleport 错误提示 |
| `SkillImprovementSurvey` | `SkillImprovementSurvey.tsx` | 技能改进调查 |
| `SessionBackgroundHint` | `SessionBackgroundHint.tsx` | 后台会话提示 |
| `NativeAutoUpdater` | `NativeAutoUpdater.tsx` | 原生自动更新器 |
| `IdeStatusIndicator` | `IdeStatusIndicator.tsx` | IDE 连接状态指示器 |
| `KeybindingWarnings` | `KeybindingWarnings.tsx` | 键绑定冲突警告 |
| `MessageModel` | `MessageModel.tsx` | 消息模型信息 |
| `MessageTimestamp` | `MessageTimestamp.tsx` | 消息时间戳 |
| `ValidationErrorsList` | `ValidationErrorsList.tsx` | 验证错误列表 |
| `FileEditToolUpdatedMessage` | `FileEditToolUpdatedMessage.tsx` | 文件编辑更新消息 |
| `NotebookEditToolUseRejectedMessage` | `NotebookEditToolUseRejectedMessage.tsx` | Notebook 编辑拒绝消息 |

---

# React Hooks (hooks/)

业务逻辑层 React Hooks，提供状态管理和副作用封装。

---

## UI 与交互

### useTerminalSize

**文件**: `useTerminalSize.ts`

获取终端尺寸（列数、行数）。通过 `TerminalSizeContext` 上下文获取。

```ts
function useTerminalSize(): TerminalSize // { columns: number, rows: number }
```

---

### useBlink

**文件**: `useBlink.ts`

同步闪烁动画 Hook。所有实例共享同一动画时钟，自动在终端失焦时暂停。

```ts
function useBlink(enabled: boolean, intervalMs?: number): [ref: (element: DOMElement | null) => void, isVisible: boolean]
```

- `enabled` — 是否启用闪烁
- `intervalMs` — 闪烁间隔（默认 600ms）
- 返回 `[ref, isVisible]` — ref 附加到元素，`isVisible` 为当前闪烁状态

---

### useDoublePress

**文件**: `useDoublePress.ts`

双击检测 Hook。首次调用触发回调 A，在超时窗口内再次调用触发回调 B。

```ts
function useDoublePress(
  setPending: (pending: boolean) => void,
  onDoublePress: () => void,
  onFirstPress?: () => void,
): () => void
```

超时窗口：800ms（`DOUBLE_PRESS_TIMEOUT_MS`）

---

### useSearchInput

**文件**: `useSearchInput.ts`

搜索输入框 Hook，封装文本编辑、光标移动、Kill/Yank 和退出逻辑。

```ts
type UseSearchInputOptions = {
  isActive: boolean
  onExit: () => void
  onCancel?: () => void
  onExitUp?: () => void
  columns?: number
  initialQuery?: string
  backspaceExitsOnEmpty?: boolean
  passthroughCtrlKeys?: string[]
}

type UseSearchInputReturn = {
  query: string
  setQuery: (q: string) => void
  cursorOffset: number
  handleKeyDown: (e: KeyboardEvent) => void
}
```

---

### useCopyOnSelect

**文件**: `useCopyOnSelect.ts`

自动复制选中文本到剪贴板。模拟 iTerm2 的"选中文本即复制"行为。

```ts
function useCopyOnSelect(selection: Selection, isActive: boolean, onCopied?: (text: string) => void): void
```

---

### usePasteHandler

**文件**: `usePasteHandler.ts`

粘贴处理 Hook，检测大文本粘贴和图片粘贴，区分正常按键输入。

```ts
function usePasteHandler(props: PasteHandlerProps): {
  wrappedOnInput: (input: string, key: Key, event: InputEvent) => void
  pasteState: { chunks: string[]; timeoutId: ReturnType<typeof setTimeout> | null }
  isPasting: boolean
}
```

---

## 文本输入

### useTextInput

**文件**: `useTextInput.ts`（~529 行）

底层文本输入 Hook，实现完整的终端文本编辑器，包括光标移动、选择、Kill/Yank 环和多行支持。

```ts
type UseTextInputProps = {
  value: string
  onChange: (value: string) => void
  onSubmit?: (value: string) => void
  onExit?: () => void
  focus?: boolean
  mask?: string
  multiline?: boolean
  cursorChar: string
  columns: number
  // ... 更多选项
}

// 返回 TextInputState（文本、光标位置、选择状态、事件处理器等）
```

---

### useVimInput

**文件**: `useVimInput.ts`（~316 行）

Vim 模式输入 Hook，在 `useTextInput` 之上实现 NORMAL/INSERT/VISUAL 模式和 Vim 操作符。

```ts
function useVimInput(props: UseVimInputProps): VimInputState
```

支持的操作：`d`/`c`/`y` 操作符、文本对象、`x`/`r`/`J`/`o`/`O` 命令等。

---

### useInputBuffer

**文件**: `useInputBuffer.ts`

输入缓冲区 Hook，实现撤销（undo）功能。防抖快速变更，维护历史栈。

```ts
type UseInputBufferResult = {
  pushToBuffer: (text: string, cursorOffset: number, pastedContents?: Record<number, PastedContent>) => void
  undo: () => BufferEntry | undefined
  canUndo: boolean
  clearBuffer: () => void
}
```

---

## 滚动与虚拟列表

### useVirtualScroll

**文件**: `useVirtualScroll.ts`（~721 行）

虚拟滚动 Hook，为大量消息列表提供高效的视口裁剪。使用 `useSyncExternalStore` 实现响应式滚动位置。

核心参数：
- `OVERSCAN_ROWS = 80` — 视口上下额外渲染的行数
- `SCROLL_QUANTUM` — 滚动位置量化，减少不必要的 React 重渲染
- `MAX_MOUNTED_ITEMS = 300` — 最大挂载项数上限
- `SLIDE_STEP = 25` — 单次提交最大新挂载数

返回：挂载范围 `[startIndex, endIndex]`、滚动操作方法和测量回调。

---

## 历史与搜索

### useHistorySearch

**文件**: `useHistorySearch.ts`

历史记录搜索 Hook，实现 Ctrl+R 风格的增量历史搜索。

```ts
function useHistorySearch(
  onAcceptHistory: (entry: HistoryEntry) => void,
  currentInput: string,
  onInputChange: (input: string) => void,
  // ... 更多参数
): {
  historyQuery: string
  setHistoryQuery: (query: string) => void
  historyMatch: HistoryEntry | undefined
  historyFailedMatch: boolean
  handleKeyDown: (e: KeyboardEvent) => void
}
```

---

### useAssistantHistory

**文件**: `useAssistantHistory.ts`

远程助手历史记录加载 Hook，分页获取旧消息。

```ts
type Result = {
  maybeLoadOlder: (handle: ScrollBoxHandle) => void
}
```

---

## 配置与设置

### useSettings

**文件**: `useSettings.ts`

响应式设置访问 Hook，设置文件变更时自动更新。

```ts
function useSettings(): ReadonlySettings // AppState['settings']
```

---

### useDynamicConfig

**文件**: `useDynamicConfig.ts`

动态配置 Hook，初始返回默认值，远程配置加载后自动更新。

```ts
function useDynamicConfig<T>(configName: string, defaultValue: T): T
```

---

### useMainLoopModel

**文件**: `useMainLoopModel.ts`

获取当前主循环模型名称，支持 GrowthBook 刷新后重新解析模型别名。

```ts
function useMainLoopModel(): ModelName
```

---

## Diff 与 IDE

### useDiffData

**文件**: `useDiffData.ts`

Git diff 数据获取 Hook，返回文件统计和 hunk 信息。

```ts
type DiffData = {
  stats: GitDiffStats | null
  files: DiffFile[]
  hunks: Map<string, StructuredPatchHunk[]>
  loading: boolean
}

function useDiffData(): DiffData
```

---

### useDiffInIDE

**文件**: `useDiffInIDE.ts`

在 IDE 中展示 diff 的 Hook，通过 MCP 连接将差异推送到 IDE 扩展。

---

### useIdeConnectionStatus

**文件**: `useIdeConnectionStatus.ts`

IDE 连接状态 Hook。

```ts
function useIdeConnectionStatus(mcpClients?: MCPServerConnection[]): {
  status: 'connected' | 'disconnected' | 'pending' | null
  ideName: string | null
}
```

---

### useTurnDiffs

**文件**: `useTurnDiffs.ts`

回合级 diff 计算 Hook，从消息历史中提取每回合的文件变更。

```ts
type TurnDiff = {
  turnIndex: number
  userPromptPreview: string
  timestamp: string
  files: Map<string, TurnFileDiff>
  stats: { filesChanged: number; linesAdded: number; linesRemoved: number }
}
```

---

## 时间与计时

### useElapsedTime

**文件**: `useElapsedTime.ts`

格式化耗时计时器 Hook，使用 `useSyncExternalStore` 实现高效更新。

```ts
function useElapsedTime(
  startTime: number,
  isRunning: boolean,
  ms?: number,
  pausedMs?: number,
  endTime?: number,
): string // 如 "1m 23s"
```

---

### useTimeout

**文件**: `useTimeout.ts`

简单超时 Hook，指定延迟后返回 `true`。

```ts
function useTimeout(delay: number, resetTrigger?: number): boolean
```

---

### useMinDisplayTime

**文件**: `useMinDisplayTime.ts`

最小显示时间 Hook，确保每个值至少展示 `minMs` 毫秒，防止快速切换时的闪烁。

```ts
function useMinDisplayTime<T>(value: T, minMs: number): T
```

---

## 会话与远程

### useRemoteSession

**文件**: `useRemoteSession.ts`（~605 行）

远程会话管理 Hook，处理 WebSocket 连接、消息流、权限桥接和超时。

---

### useSSHSession

**文件**: `useSSHSession.ts`（~241 行）

SSH 会话 Hook，通过 SSH 子进程驱动的远程会话，与 `useDirectConnect` 同接口。

---

### useDirectConnect

**文件**: `useDirectConnect.ts`

直连 WebSocket 会话 Hook。

---

### useQueueProcessor

**文件**: `useQueueProcessor.ts`

命令队列处理 Hook，在条件满足时自动处理排队的命令。

```ts
function useQueueProcessor(params: {
  executeQueuedInput: (commands: QueuedCommand[]) => Promise<void>
  hasActiveLocalJsxUI: boolean
  queryGuard: QueryGuard
}): void
```

---

## 退出与取消

### useExitOnCtrlCD

**文件**: `useExitOnCtrlCD.ts`

Ctrl+C / Ctrl+D 双击退出 Hook。首次按下显示提示，超时窗口内再次按下退出应用。

```ts
type ExitState = { pending: boolean; keyName: 'Ctrl-C' | 'Ctrl-D' | null }
```

---

### useCancelRequest

**文件**: `useCancelRequest.ts`（~276 行）

取消请求处理器组件（以 Hook 形式使用），管理 Esc/Ctrl+C 在不同上下文中的行为。

---

## 其他 Hooks

| Hook | 文件 | 用途 |
|---|---|---|
| `useVoice` | `useVoice.ts` | 语音输入（按住说话、STT 转录） |
| `useVoiceEnabled` | `useVoiceEnabled.ts` | 语音功能开关检测 |
| `usePromptSuggestion` | `usePromptSuggestion.ts` | 输入建议生成与追踪 |
| `useMemoryUsage` | `useMemoryUsage.ts` | Node.js 进程内存监控（10s 轮询） |
| `useUpdateNotification` | `useUpdateNotification.ts` | 更新通知 |
| `useSettingsChange` | `useSettingsChange.ts` | 设置文件变更监听 |
| `useSkillsChange` | `useSkillsChange.ts` | 技能文件变更监听 |
| `useManagePlugins` | `useManagePlugins.ts` | 插件管理 |
| `useMergedClients` | `useMergedClients.ts` | 合并 MCP 客户端 |
| `useMergedTools` | `useMergedTools.ts` | 合并工具列表 |
| `useMergedCommands` | `useMergedCommands.ts` | 合并命令列表 |
| `useApiKeyVerification` | `useApiKeyVerification.ts` | API Key 验证 |
| `useClipboardImageHint` | `useClipboardImageHint.ts` | 剪贴板图片提示 |
| `useLogMessages` | `useLogMessages.ts` | 日志消息 |
| `useIdeLogging` | `useIdeLogging.ts` | IDE 日志转发 |
| `useIdeAtMentioned` | `useIdeAtMentioned.ts` | IDE @提及检测 |
| `useIdeSelection` | `useIdeSelection.ts` | IDE 选区检测 |
| `useMailboxBridge` | `useMailboxBridge.ts` | 邮箱桥接 |
| `useInboxPoller` | `useInboxPoller.ts` | 收件箱轮询 |
| `useSessionBackgrounding` | `useSessionBackgrounding.ts` | 会话后台化 |
| `useSwarmPermissionPoller` | `useSwarmPermissionPoller.ts` | Swarm 权限轮询 |
| `useSwarmInitialization` | `useSwarmInitialization.ts` | Swarm 初始化 |
| `useTaskListWatcher` | `useTaskListWatcher.ts` | 任务列表监控 |
| `useTasksV2` | `useTasksV2.ts` | V2 任务系统 |
| `useScheduledTasks` | `useScheduledTasks.ts` | 定时任务 |
| `useBackgroundTaskNavigation` | `useBackgroundTaskNavigation.ts` | 后台任务导航 |
| `useTeammateViewAutoExit` | `useTeammateViewAutoExit.ts` | 队友视图自动退出 |
| `usePrStatus` | `usePrStatus.ts` | PR 状态 |
| `useAwaySummary` | `useAwaySummary.ts` | 离开摘要 |
| `useFileHistorySnapshotInit` | `useFileHistorySnapshotInit.ts` | 文件历史快照初始化 |
| `useDeferredHookMessages` | `useDeferredHookMessages.ts` | 延迟 Hook 消息 |
| `useNotifyAfterTimeout` | `useNotifyAfterTimeout.ts` | 超时通知 |
| `useAfterFirstRender` | `useAfterFirstRender.ts` | 首次渲染后回调 |
| `useSkillImprovementSurvey` | `useSkillImprovementSurvey.ts` | 技能改进调查 |
| `useIssueFlagBanner` | `useIssueFlagBanner.ts` | Issue 标记横幅 |

---

## toolPermission/ — 工具权限处理

| 文件 | 用途 |
|---|---|
| `PermissionContext.ts` | 权限上下文定义 |
| `handlers/interactiveHandler.ts` | 交互模式权限处理 |
| `handlers/coordinatorHandler.ts` | 协调器权限处理 |
| `handlers/swarmWorkerHandler.ts` | Swarm Worker 权限处理 |
| `permissionLogging.ts` | 权限日志 |

---

## notifs/ — 通知 Hooks

| Hook | 文件 | 用途 |
|---|---|---|
| `useStartupNotification` | `useStartupNotification.ts` | 启动通知 |
| `useTeammateShutdownNotification` | `useTeammateShutdownNotification.ts` | 队友关闭通知 |
| `useAutoModeUnavailableNotification` | `useAutoModeUnavailableNotification.ts` | Auto 模式不可用通知 |

---

## 建议系统

| 模块 | 文件 | 用途 |
|---|---|---|
| `unifiedSuggestions` | `unifiedSuggestions.ts` | 统一建议引擎 |
| `fileSuggestions` | `fileSuggestions.ts` | 文件路径建议 |
| `renderPlaceholder` | `renderPlaceholder.ts` | 占位符渲染 |

---

# 终端渲染引擎 (ink/)

基于 React 的终端 UI 渲染引擎，fork 自 [Ink](https://github.com/vadimdemedes/ink) 并进行了大量定制优化。

---

## 核心架构

### Ink（主类）

**文件**: `ink.tsx`（~1723 行）

渲染引擎入口，管理 React 树与终端之间的桥接。

| 功能 | 说明 |
|---|---|
| React 容器管理 | 创建 `ConcurrentRoot` 容器，挂载 `<App>` 根组件 |
| 双缓冲渲染 | 维护 front/back 两个帧缓冲区，渲染完成后交换 |
| 输入处理 | 解析 stdin 的键盘/鼠标事件，分发到事件系统 |
| 滚动支持 | alt-screen 和主屏幕模式下的滚动管理 |
| 搜索高亮 | 消息内搜索匹配位置高亮 |
| 文本选择 | 鼠标拖拽选择、多击选词/行、复制到剪贴板 |
| 输出优化 | 差量 diff 输出，最小化终端写入 |
| 光标管理 | alt-screen 下隐藏光标，主屏幕下声明式光标定位 |

**类型**:
```ts
type Options = {
  stdout: NodeJS.WriteStream
  stdin: NodeJS.ReadStream
  stderr: NodeJS.WriteStream
  exitOnCtrlC: boolean
  patchConsole: boolean
  waitUntilExit?: () => Promise<void>
  onFrame?: (event: FrameEvent) => void
}
```

---

### DOM 模型

**文件**: `dom.ts`（~484 行）

类 DOM 的虚拟节点树，映射 React 组件到终端布局。

| 节点类型 | 说明 |
|---|---|
| `ink-root` | 根节点 |
| `ink-box` | Box 容器节点 |
| `ink-text` | 文本节点 |
| `ink-virtual-text` | 虚拟文本（样式继承） |
| `ink-link` | 超链接节点 |
| `ink-raw-ansi` | 原始 ANSI 序列 |

**DOMElement** 属性：
- `yogaNode` — Yoga 布局节点引用
- `style` — 样式属性
- `scrollTop` / `scrollHeight` / `scrollViewportHeight` — 滚动状态
- `dirty` — 脏标记
- `_eventHandlers` — 事件处理器

核心操作：`createNode`, `appendChildNode`, `removeChildNode`, `insertBeforeNode`, `setAttribute`, `setStyle`, `setTextNodeValue`

---

### React 协调器（Reconciler）

**文件**: `reconciler.ts`（~512 行）

自定义 React 协调器，将 React 组件树映射到 Ink DOM 节点。

- 使用 `react-reconciler` 创建自定义渲染器
- 支持 React DevTools 集成
- 实现 `commitMount`（autoFocus）、`commitUpdate`（样式/属性更新）
- 性能追踪：记录每次 commit 和 Yoga 计算的耗时

---

### 渲染器（Renderer）

**文件**: `renderer.ts`（~178 行）

帧渲染函数，将 DOM 树渲染到 Screen 缓冲区。

```ts
type RenderOptions = {
  frontFrame: Frame    // 前一帧
  backFrame: Frame     // 当前帧
  isTTY: boolean
  terminalWidth: number
  terminalRows: number
  altScreen: boolean
  prevFrameContaminated: boolean  // 前帧是否被选择叠加层污染
}

type Renderer = (options: RenderOptions) => Frame
```

渲染流程：
1. 从 DOM 根节点出发，调用 `renderNodeToOutput` 遍历树
2. Output 对象将节点绘制到 Screen 缓冲区
3. 返回包含新 Screen 的 Frame

---

### Screen（屏幕缓冲区）

**文件**: `screen.ts`（~1486 行）

终端屏幕的二维单元格缓冲区，使用字符串池化（interning）优化内存。

| 类 | 用途 |
|---|---|
| `CharPool` | 字符串池——ASCII 快速路径 + Map 查找 |
| `StylePool` | 样式池——ANSI 样式组合的唯一标识 |
| `HyperlinkPool` | 超链接字符串池 |

每个单元格存储：
- 字符 ID（CharPool 索引）
- 样式 ID（StylePool 索引）
- 超链接 ID（HyperlinkPool 索引）
- 宽度标记（`CellWidth.NARROW` / `CellWidth.WIDE`）

核心操作：`cellAt`, `setCellAt`, `blitRegion`（区域复制）, `diffEach`（差量比较）

---

### Output（输出收集器）

**文件**: `output.ts`（~797 行）

渲染树的输出收集器，将 React 节点的样式和文本转换为 Screen 单元格。

核心概念：
- `ClusteredChar` — 预计算的字素簇（值、宽度、样式ID、超链接）
- 字素分段（`getGraphemeSegmenter`）——正确处理 Unicode
- 双向文本重排（`reorderBidi`）
- 行缓存（`charCache`）——相同行不重复计算

---

### Frame（帧）

**文件**: `frame.ts`

帧数据结构，包含 Screen 缓冲区、光标位置和差量信息。

```ts
type Frame = {
  screen: Screen
  cursor: { x: number; y: number; visible: boolean }
}

type Diff = {
  type: 'stdout'
  content: string  // ANSI 序列字符串
}
```

---

## 终端交互

### Terminal

**文件**: `terminal.ts`（~248 行）

终端能力检测与写入层。

| 功能 | 说明 |
|---|---|
| `writeDiffToTerminal` | 差量写入——只更新变化的行 |
| `isProgressReportingAvailable` | OSC 9;4 进度报告检测（iTerm2 3.6.6+, Ghostty 1.2.0+） |
| `isXtermJs` | xterm.js 检测 |
| 进度报告 | 支持 running/completed/error/indeterminate 状态 |

---

### FocusManager

**文件**: `focus.ts`（~181 行）

DOM 风格的焦点管理器，跟踪 `activeElement` 和焦点栈。

| 方法 | 说明 |
|---|---|
| `focus(node)` | 聚焦节点 |
| `blur()` | 取消焦点 |
| `handleNodeRemoved(node, root)` | 节点移除时恢复焦点 |
| `focusNearest(node)` | 聚焦最近的可 Tab 节点 |
| `tabNext(root)` / `tabPrev(root)` | Tab/Shift+Tab 导航 |

焦点栈最大深度：32（`MAX_FOCUS_STACK`）

---

### Selection（文本选择）

**文件**: `selection.ts`

终端内文本选择状态管理，支持鼠标拖拽和多击。

| 功能 | 说明 |
|---|---|
| `startSelection` | 开始选择（鼠标按下） |
| `extendSelection` | 延伸选择（鼠标拖动） |
| `shiftSelection` / `shiftAnchor` | 键盘滚动时移动选择 |
| `selectWordAt` / `selectLineAt` | 双击/三击选词/行 |
| `getSelectedText` | 获取选中文本 |
| `captureScrolledRows` | 捕获滚出视口的文本 |
| `applySelectionOverlay` | 将选择叠加到 Screen 缓冲区 |

---

### 事件系统

**目录**: `events/`

| 文件 | 类 | 说明 |
|---|---|---|
| `event.ts` | `Event` | 基础事件类 |
| `input-event.ts` | `InputEvent` | 输入事件（键盘、鼠标） |
| `keyboard-event.ts` | `KeyboardEvent` | 键盘事件 |
| `click-event.ts` | `ClickEvent` | 点击事件 |
| `focus-event.ts` | `FocusEvent` | 焦点事件 |
| `terminal-event.ts` | — | 终端事件类型 |
| `terminal-focus-event.ts` | — | 终端焦点事件 |
| `dispatcher.ts` | `Dispatcher` | 事件分发器（捕获/冒泡） |
| `emitter.ts` | — | 事件发射器 |
| `event-handlers.ts` | `EVENT_HANDLER_PROPS` | 事件处理器属性名映射 |

---

### TermIO（终端 I/O 序列）

**目录**: `termio/`

| 文件 | 说明 |
|---|---|
| `csi.ts` | CSI（Control Sequence Introducer）序列——光标移动、键盘模式 |
| `dec.ts` | DEC 私有模式——alt-screen、鼠标跟踪、光标显隐 |
| `osc.ts` | OSC（Operating System Commands）——剪贴板、超链接、进度条、Tab 状态 |
| `sgr.ts` | SGR（Select Graphic Rendition）——样式序列 |
| `parser.ts` | 终端序列解析器 |
| `tokenize.ts` | 输入序列分词 |
| `ansi.ts` | ANSI 常量（ESC、BEL 等） |
| `esc.ts` | ESC 序列 |
| `dec.ts` | DEC 模式常量 |

---

## 布局引擎

### Layout

**目录**: `layout/`

| 文件 | 说明 |
|---|---|
| `engine.ts` | Yoga 布局引擎封装——创建/计算/释放布局节点 |
| `node.ts` | `LayoutNode` / `LayoutDisplay` 类型定义 |
| `geometry.ts` | 几何类型（`Point`, `Rectangle`, `Size`）和操作 |

---

## 内置组件

### Box

**文件**: `components/Box.tsx`

基础布局容器，等同于浏览器中的 `<div style="display: flex">`。

| Props | 类型 | 说明 |
|---|---|---|
| `ref` | `Ref<DOMElement>` | DOM 引用 |
| `tabIndex` | `number` | Tab 导航索引 |
| `autoFocus` | `boolean` | 自动聚焦 |
| `onClick` | `(event: ClickEvent) => void` | 点击事件 |
| `onFocus` / `onBlur` | 焦点事件回调 | 焦点事件 |
| `onKeyDown` | `(event: KeyboardEvent) => void` | 键盘事件 |
| `onMouseEnter` / `onMouseLeave` | `() => void` | 鼠标进出 |
| 所有 `Styles` 属性（不含 `textWrap`） | — | Flexbox 布局样式 |

---

### Text

**文件**: `components/Text.tsx`

文本渲染组件。`bold` 和 `dim` 互斥（终端限制）。

| Props | 类型 | 说明 |
|---|---|---|
| `color` | `Color` | 文本颜色 |
| `backgroundColor` | `Color` | 背景色 |
| `bold` / `dim` | `boolean`（互斥） | 粗体/暗淡 |
| `italic` | `boolean` | 斜体 |
| `underline` | `boolean` | 下划线 |
| `strikethrough` | `boolean` | 删除线 |
| `inverse` | `boolean` | 反色 |
| `wrap` | `'wrap' \| 'wrap-trim' \| 'end' \| 'middle' \| 'truncate-start' \| 'truncate-end' \| 'truncate'` | 换行/截断模式 |

---

### ScrollBox

**文件**: `components/ScrollBox.tsx`

可滚动容器，带视口裁剪和命令式滚动 API。

| Props | 类型 | 说明 |
|---|---|---|
| `ref` | `Ref<ScrollBoxHandle>` | 命令式句柄 |
| `stickyScroll` | `boolean` | 自动跟随底部 |

**ScrollBoxHandle 方法**：
- `scrollTo(y)` / `scrollBy(dy)` — 绝对/相对滚动
- `scrollToElement(el, offset?)` — 滚动到指定元素
- `scrollToBottom()` — 滚动到底部
- `getScrollTop()` / `getScrollHeight()` / `getViewportHeight()` — 状态查询
- `isSticky()` — 是否跟随底部
- `subscribe(listener)` — 订阅滚动变化
- `setClampBounds(min, max)` — 设置滚动边界

---

### 其他内置组件

| 组件 | 文件 | 用途 |
|---|---|---|
| `Button` | `components/Button.tsx` | 按钮——Enter/Space/Click 触发，支持焦点/悬停/按下状态 |
| `Newline` | `components/Newline.tsx` | 插入换行符（`count` 属性控制数量） |
| `Spacer` | `components/Spacer.tsx` | 弹性空白（`flexGrow: 1`） |
| `Link` | `components/Link.tsx` | 终端超链接（OSC 8），不支持时回退到纯文本 |
| `App` | `components/App.tsx` | 根组件——提供所有上下文 |
| `AlternateScreen` | `components/AlternateScreen.tsx` | Alt-screen 模式容器 |
| `RawAnsi` | `components/RawAnsi.tsx` | 原始 ANSI 序列渲染 |
| `NoSelect` | `components/NoSelect.tsx` | 禁止选择区域 |

---

## 内置 Hooks

| Hook | 文件 | 用途 |
|---|---|---|
| `useInput` | `hooks/use-input.ts` | 键盘输入监听（`useLayoutEffect` 同步设置 raw mode） |
| `useApp` | `hooks/use-app.ts` | 获取 App 上下文（退出方法） |
| `useStdin` | `hooks/use-stdin.ts` | 获取 stdin 流 |
| `useSelection` | `hooks/use-selection.ts` | 文本选择操作（复制、清除、移动焦点等） |
| `useAnimationFrame` | `hooks/use-animation-frame.ts` | 同步动画帧（共享时钟，离屏暂停） |
| `useAnimationTimer` | `hooks/use-interval.ts` | 非保活动画定时器（use-interval.ts 导出） |
| `useInterval` | `hooks/use-interval.ts` | 共享时钟间隔（use-interval.ts 导出） |
| `useTerminalFocus` | `hooks/use-terminal-focus.ts` | 终端焦点状态 |
| `useTerminalTitle` | `hooks/use-terminal-title.ts` | 终端标题设置 |
| `useTerminalViewport` | `hooks/use-terminal-viewport.ts` | 元素视口可见性 |
| `useDeclaredCursor` | `hooks/use-declared-cursor.ts` | 声明式光标定位 |
| `useSearchHighlight` | `hooks/use-search-highlight.ts` | 搜索高亮 |
| `useTabStatus` | `hooks/use-tab-status.ts` | Tab 状态栏 |

---

## 文本处理工具

| 文件 | 用途 |
|---|---|
| `stringWidth.ts` | Unicode 字符串宽度计算 |
| `widest-line.ts` | 多行文本最大宽度 |
| `wrap-text.ts` | 文本换行 |
| `wrapAnsi.ts` | ANSI 感知的文本换行 |
| `measure-text.ts` | 文本测量 |
| `measure-element.ts` | 元素测量 |
| `colorize.ts` | ANSI 颜色应用 |
| `styles.ts` | 样式类型定义 |
| `bidi.ts` | 双向文本重排 |
| `parse-keypress.ts` | 按键序列解析 |
| `tabstops.ts` | Tab 停止位展开 |
| `searchHighlight.ts` | 搜索高亮渲染 |
| `squash-text-nodes.ts` | 文本节点合并 |
| `log-update.ts` | 终端输出更新管理 |
| `hit-test.ts` | 鼠标坐标命中测试 |
| `optimizer.ts` | 渲染优化 |
| `node-cache.ts` | 节点缓存 |
| `line-width-cache.ts` | 行宽缓存 |
| `instances.ts` | Ink 实例注册表 |
| `root.ts` | 根节点管理 |
| `clearTerminal.ts` | 终端清屏序列 |
| `supports-hyperlinks.ts` | 超链接支持检测 |
| `warn.ts` | 废弃警告 |
| `get-max-width.ts` | 最大宽度计算 |
| `render-border.ts` | 边框渲染 |
| `render-node-to-output.ts` | 节点到输出渲染 |
| `useTerminalNotification.ts` | 终端通知 |
| `terminal-focus-state.ts` | 终端焦点状态 |
| `terminal-querier.ts` | 终端查询（DA/DSR） |

---

## 上下文（Context）

| Context | 文件 | 提供的值 |
|---|---|---|
| `AppContext` | `components/AppContext.ts` | `exit()` 方法 |
| `StdinContext` | `components/StdinContext.ts` | stdin 流、raw mode、事件发射器 |
| `TerminalSizeContext` | `components/TerminalSizeContext.tsx` | `{ columns, rows }` |
| `TerminalFocusContext` | `components/TerminalFocusContext.tsx` | 终端焦点状态 |
| `ClockContext` | `components/ClockContext.tsx` | 共享动画时钟 |
| `CursorDeclarationContext` | `components/CursorDeclarationContext.ts` | 光标声明上下文 |
