# Native-TS 模块 (native-ts/)

## 架构概览

Native-TS 模块是 Claude Code CLI 的纯 TypeScript 重实现层，用于替代原有的 Rust NAPI 原生模块。这些纯 TS 端口保留了相同 API 表面，使上层代码无需修改即可切换到底层实现。

```
Rust NAPI (vendor/) → Native-TS (native-ts/)
  - color-diff-src      → color-diff/
  - file-index-src       → file-index/
  - yoga-layout          → yoga-layout/
```

### 设计原则

- **API 兼容**: 与 vendor 源码的接口完全一致，上层无需感知底层实现切换
- **延迟加载**: highlight.js 等重型依赖采用延迟加载，避免模块初始化时的性能开销
- **事件循环让渡**: 大量计算操作（如文件索引构建）支持异步分块，避免阻塞主线程
- **性能优化**: 使用 TypedArray、Bitmap 拒绝、缓存失效策略等手段接近原生性能

---

## 文件索引 (file-index/)

**用途**: 高性能模糊文件搜索，替代 nucleo (Rust) 原生模块。

- **文件**: `native-ts/file-index/index.ts`
- **上游**: `vendor/file-index-src` (Rust NAPI，封装 nucleo)

### 核心类型

| 类型 | 说明 |
|------|------|
| `SearchResult` | 搜索结果 `{ path: string; score: number }` |
| `FileIndex` | 文件索引主类 |

### 核心方法

| 方法 | 说明 |
|------|------|
| `loadFromFileList(fileList: string[]): void` | 从路径数组加载并索引，自动去重 |
| `loadFromFileListAsync(fileList: string[]): { queryable, done }` | 异步分块构建索引，支持渐进查询 |
| `search(query: string, limit: number): SearchResult[]` | 模糊搜索，返回得分排序结果 |

### 评分语义

- **score 越低越好**: 分数 = 结果位置 / 结果总数，最佳匹配为 0.0
- **test 惩罚**: 路径包含 "test" 的文件乘以 1.05 惩罚系数（上限 1.0）
- **智能大小写**: 查询全小写时大小写不敏感；包含大写时大小写敏感

### 性能优化

- **Bitmap 拒绝**: O(1) 检查路径是否包含查询的所有字母，89% 的宽泛查询可快速拒绝
- **Top-K 算法**: 维护有序 top-k 结果，避免 O(n log n) 全量排序
- **间隙边界拒绝**: 在边界评分计算前提前跳过不可能胜出的路径
- **异步分块**: 时间阈值让渡（每 4ms），慢机器自动获得更小分块以保持响应；M 系列上约 5k-12k 路径触发一次让渡，270k+ 文件的索引构建不超过 10ms 阻塞

### 内部缓存

- **topLevelCache**: 顶层路径缓存，按 (长度升序, 字母升序) 排列，用于空查询快速返回
- **readyCount**: 异步构建过程中已就绪的路径数，支持搜索与构建并行

---

## 颜色差分 (color-diff/)

**用途**: 语法高亮和 Git diff 着色，替代 Rust 原生模块。

- **文件**: `native-ts/color-diff/index.ts`
- **上游**: `vendor/color-diff-src` (Rust NAPI，使用 syntect + bat)
- **依赖**: highlight.js（延迟加载）、diff npm 包

### 核心类型

| 类型 | 说明 |
|------|------|
| `Hunk` | Git diff 块 `{ oldStart, oldLines, newStart, newLines, lines }` |
| `SyntaxTheme` | 语法高亮主题 `{ theme: string; source: string \| null }` |
| `NativeModule` | 模块导出 `{ ColorDiff, ColorFile, getSyntaxTheme }` |
| `Color` | RGBA 颜色 `{ r, g, b, a }`（a=1=终端默认，a=0=调色板索引） |
| `Block` | 样式块 `[[Style, text]]` — foreground/background Color + 文本片段 |

### 核心类

| 类 | 说明 |
|----|------|
| `ColorDiff` | 渲染 diff hunk，支持行号、标记、背景色、单词级 diff |
| `ColorFile` | 渲染完整文件，支持语法高亮和行号 |
| `getSyntaxTheme()` | 获取语法高亮主题（stub: BAT_THEME 环境变量不支持） |
| `getNativeModule()` | 懒加载获取完整模块 |

### ColorDiff.render() 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `themeName` | `string` | 主题名（dark/light/ansi/daltonized） |
| `width` | `number` | 终端宽度（用于文本换行） |
| `dim` | `boolean` | 是否淡化删除行内容（true 时跳过单词 diff） |

### 语法高亮

- **语言检测**: 文件名扩展名、shebang（#!/bin/bash）、文件特征（MimeType）
- **Scope 颜色**: Monokai Extended（暗色）、GitHub（亮色）、ANSI（256 色）
- **关键字分离**: `const`/`function`/`class` 等使用 storage.type 颜色而非 keyword 颜色
- **差异**: hljs 语法树与 syntect 存在差异，部分 token（如纯标识符、运算符）无作用域颜色

### 主题构建

- **暗色**: Monokai Extended 配色，添加行背景色（绿/红）
- **亮色**: GitHub 配色，添加行背景色（浅绿/浅红）
- **Daltonized**: 色盲友好版本（蓝/橙色调）
- **ANSI**: 256 色模式，适合真彩色不支持的终端

### 单词级 Diff

- **分词器**: Unicode 感知，区分字母/数字/空白/标点符号
- **阈值**: 变更长度超过总长度 40% 时返回空 ranges（避免无意义的高亮）
- **配对算法**: 找到相邻的删除/添加对，计算字符级别的变更范围

### 渲染管线

1. **标记解析**: 解析 hunk 行的 `+`/`-`/` ` 前缀，分配行号
2. **单词 diff**: 对相邻的删除/添加行执行 `findAdjacentPairs` + `wordDiffStrings`
3. **语法高亮**: `highlightLine()` 调用 hljs，对每行输出 tokenized `Block[]`
4. **removeNewlines**: 将 Block 中的 `\n` 拆分为多行
5. **applyBackground**: 将 word-diff ranges 应用于背景色
6. **wrapText**: 按 width 折叠长行，末尾添加空格填充背景色
7. **addMarker/addLineNumber**: 添加 gutter 标记和行号
8. **intoLines**: 将 `Block[][]` 转换为 ANSI 转义序列字符串

---

## Yoga 布局引擎 (yoga-layout/)

**用途**: 纯 TypeScript 实现的 Flexbox 布局引擎，替代 Meta 的 Yoga (C++) 原生模块。

- **文件**: `native-ts/yoga-layout/index.ts`、`native-ts/yoga-layout/enums.ts`
- **上游**: `vendor/yoga-layout` (C++ NAPI)
- **上游仓库**: https://github.com/facebook/yoga

### 支持的 CSS Flexbox 特性

| 类别 | 支持的属性 |
|------|-----------|
| 方向 | `flex-direction` (row/column ±reverse) |
| 伸缩 | `flex-grow`、`flex-shrink`、`flex-basis` |
| 对齐 | `align-items`、`align-self` (stretch/flex-start/center/flex-end/baseline) |
| 分布 | `justify-content` (全部 6 种值) |
| 间距 | `margin`、`padding`、`border`、`gap` |
| 尺寸 | `width`、`height`、`min-width`、`min-height`、`max-width`、`max-height` (point/percent/auto) |
| 定位 | `position: relative / absolute` |
| 显示 | `display: flex / none` |
| 换行 | `flex-wrap: wrap / wrap-reverse` |
| 文本节点 | measure functions（通过 `setMeasureFunc`） |
| 基线对齐 | `align-items/align-self: baseline` |
| Contents | `display: contents`（子节点提升到祖父节点） |
| Margin Auto | 主轴/交叉轴 margin:auto 覆盖 justify/align |

### 未实现特性

- `aspect-ratio`
- `box-sizing: content-box`
- `direction: RTL`（Ink 始终传递 LTR）

### 核心类型

| 类型 | 说明 |
|------|------|
| `Value` | 布局值 `{ unit: Unit; value: number }` |
| `Layout` | 计算后的布局结果 `{ left, top, width, height, border, padding, margin }` |
| `Style` | 节点样式输入 |
| `Config` | Yoga 配置 `{ pointScaleFactor, errata, useWebDefaults }` |
| `MeasureFunction` | 文本测量函数类型 |
| `Size` | 尺寸 `{ width: number; height: number }` |
| `Yoga` | 模块导出接口 |

### 核心 API

| 函数/方法 | 说明 |
|----------|------|
| `loadYoga(): Promise<Yoga>` | 异步加载 Yoga 实例（返回 `{ Config, Node }`） |
| `DEFAULT_CONFIG` | 默认配置单例（`pointScaleFactor=1`, `errata=Errata.None`） |
| `Node.calculateLayout(w, h)` | 计算布局 |
| `Node.setMeasureFunc(fn)` | 设置文本测量函数 |
| `Node.setWidth/setHeight` | 设置尺寸（point/percent/auto） |
| `Node.setFlexGrow/setFlexShrink` | 设置伸缩因子 |
| `Node.setMargin/setPadding/setBorder` | 设置边距/间距 |
| `Node.setJustifyContent/setAlignItems` | 设置主轴/交叉轴对齐 |
| `Node.getComputedLayout()` | 获取计算后的布局 |

### 性能计数器

```typescript
getYogaCounters(): { visited, measured, cacheHits, live }
```

- `visited`: 布局访问的节点数
- `measured`: measure 函数调用次数
- `cacheHits`: 缓存命中次数
- `live`: 当前活跃节点数

### 布局算法步骤

Yoga 布局引擎的核心 `layoutNode()` 按以下步骤执行：

1. **缓存查找**: dirty flag + generation stamp 双检，跳过无变更子树
2. **边缘解析**: `resolveEdges4Into` 批量解析 padding/border/margin
3. **尺寸约束**: 应用 min/max 约束到 style 维度
4. **叶节点**: 有 measure 函数则调用，否则取 0 或 content 尺寸
5. **容器节点**: flexbox 算法 — 计算 flex-basis → 分行 → flex 长度解析 → 子节点布局 → 确定容器尺寸
6. **绝对定位**: 绝对定位子节点独立布局（相对父节点 padding-box）
7. **Round**: 像素网格对齐（文本节点 floor 位置/ceil 宽度）

### 布局缓存

- **单槽缓存**: 记录上一次布局的输入/输出，快速跳过无变更的子树
- **多槽缓存**: 4 槽 Float64Array 缓存，应对滚动场景下同一节点被不同输入多次访问
- **基准缓存**: 存储 computeFlexBasis 结果，避免重复计算子节点基准尺寸
- **失效策略**: 基于 generation 的缓存失效，支持虚拟滚动中的新鲜节点复用缓存

### 性能优化

- **TypedArray**: 使用 `Int32Array`（bitmap）、`Uint16Array`（路径长度）、`Float64Array`（缓存）
- **批量边缘解析**: `resolveEdges4Into` 一次计算四个物理边缘，避免重复查询
- **快速拒绝**: 无 auto margin/position 时跳过 6+ 次 `isMarginAuto` 调用
- **像素网格舍入**: 文本节点向下取整位置、向上取整宽度，与上游 WASM 行为一致

---

## 枚举常量 (yoga-layout/enums.ts)

所有枚举使用 `const` 对象而非 TS `enum`，符合仓库约定。

| 枚举 | 值 |
|------|---|
| `Align` | Auto, FlexStart, Center, FlexEnd, Stretch, Baseline, SpaceBetween, SpaceAround, SpaceEvenly |
| `BoxSizing` | BorderBox, ContentBox |
| `Dimension` | Width, Height |
| `Direction` | Inherit, LTR, RTL |
| `Display` | Flex, None, Contents |
| `Edge` | Left, Top, Right, Bottom, Start, End, Horizontal, Vertical, All |
| `Errata` | None, StretchFlexBasis, AbsolutePositionWithoutInsetsExcludesPadding, ... |
| `ExperimentalFeature` | WebFlexBasis |
| `FlexDirection` | Column, ColumnReverse, Row, RowReverse |
| `Gutter` | Column, Row, All |
| `Justify` | FlexStart, Center, FlexEnd, SpaceBetween, SpaceAround, SpaceEvenly |
| `MeasureMode` | Undefined, Exactly, AtMost |
| `Overflow` | Visible, Hidden, Scroll |
| `PositionType` | Static, Relative, Absolute |
| `Unit` | Undefined, Point, Percent, Auto |
| `Wrap` | NoWrap, Wrap, WrapReverse |

---

## file-index 导出常量

| 导出 | 说明 |
|------|------|
| `yieldToEventLoop()` | 让出事件循环的 Promise（用于异步分块） |
| `CHUNK_MS` | 异步分块时间阈值（4ms） |
| `FileIndexType` | `FileIndex` 别名（用于类型引用） |

---

## color-diff 内部函数（测试用）

`__test` 命名空间导出以下函数供测试验证：

| 函数 | 说明 |
|------|------|
| `tokenize(text)` | Unicode 感知的分词器 |
| `findAdjacentPairs(markers)` | 查找相邻的 `-...-+` 对 |
| `wordDiffStrings(old, new)` | 计算词级别 diff 范围 |
| `ansi256FromRgb(r, g, b)` | RGB → xterm-256 调色板近似 |
| `colorToEscape(color, fg, mode)` | Color → ANSI 转义序列 |
| `detectColorMode(theme)` | 检测颜色模式 |
| `detectLanguage(filePath, firstLine)` | 检测编程语言 |

**颜色转换**: `ansi256FromRgb` 使用 6×6×6 色立方 + 24 级灰阶梯，选取感知最近的颜色索引。

---

## 文件索引

| 模块 | 文件 | 上游 | 用途 |
|------|------|------|------|
| file-index | `file-index/index.ts` | nucleo (Rust) | 高性能模糊文件搜索 |
| color-diff | `color-diff/index.ts` | syntect+bat (Rust) | 语法高亮和 diff 着色 |
| yoga-layout | `yoga-layout/index.ts` | Yoga (C++) | Flexbox 布局引擎 |
| yoga enums | `yoga-layout/enums.ts` | Yoga (C++) | 布局枚举常量 |
