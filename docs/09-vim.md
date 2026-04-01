# Vim 模式编辑器 (vim/)

本模块实现了一个纯函数式设计的 Vim 状态机，涵盖 Normal 模式下的操作符（operator）、移动（motion）和文本对象（text object）处理。`motions.ts` 和 `operators.ts` 中的核心计算函数均为纯函数，状态通过 `OperatorContext` 回调从外部注入，确保业务逻辑与状态管理解耦。

状态机通过 `transitions.ts` 中的状态转换表驱动，`types.ts` 定义了所有状态类型与常量。

---

## types.ts — 状态机核心类型、常量和工厂函数

`types.ts` 是整个 Vim 模块的类型定义文件，定义了状态机的所有状态类型、持久化状态、操作符常量等。状态图即文档本身。

### 导出类型

#### `Operator`

```typescript
type Operator = 'delete' | 'change' | 'yank'
```

NORMAL 模式下可用的操作符类型。

#### `FindType`

```typescript
type FindType = 'f' | 'F' | 't' | 'T'
```

字符查找命令的类型：`f`/`F` 为找到，`t`/`T` 为跳转到字符前。

| 值 | 含义 |
|----|------|
| `f` | 正向查找字符 |
| `F` | 反向查找字符 |
| `t` | 正向跳转到字符前 |
| `T` | 反向跳转到字符前 |

#### `TextObjScope`

```typescript
type TextObjScope = 'inner' | 'around'
```

文本对象的作用范围：`inner` 仅选中内容，`around` 包含包围的分隔符。

#### `VimState`

```typescript
type VimState =
  | { mode: 'INSERT'; insertedText: string }
  | { mode: 'NORMAL'; command: CommandState }
```

完整的 Vim 状态。INSERT 模式追踪输入文本（用于 dot-repeat），NORMAL 模式运行命令解析状态机。

#### `CommandState`

```typescript
type CommandState =
  | { type: 'idle' }
  | { type: 'count'; digits: string }
  | { type: 'operator'; op: Operator; count: number }
  | { type: 'operatorCount'; op: Operator; count: number; digits: string }
  | { type: 'operatorFind'; op: Operator; count: number; find: FindType }
  | { type: 'operatorTextObj'; op: Operator; count: number; scope: TextObjScope }
  | { type: 'find'; find: FindType; count: number }
  | { type: 'g'; count: number }
  | { type: 'operatorG'; op: Operator; count: number }
  | { type: 'replace'; count: number }
  | { type: 'indent'; dir: '>' | '<'; count: number }
```

NORMAL 模式的命令状态机。每个状态精确描述了等待什么输入。TypeScript exhaustive switch 确保所有状态都被处理。

| 状态 | 等待输入 | 说明 |
|------|----------|------|
| `idle` | 操作符/数字/动作/其他 | 初始状态 |
| `count` | 更多数字或动作 | 前缀计数中 |
| `operator` | 动作/文本对象/查找/数字 | 操作符后等待motion |
| `operatorCount` | 操作符的计数 | 操作符后又有数字前缀 |
| `operatorFind` | 目标字符 | `df`/`dt` 等 |
| `operatorTextObj` | 文本对象类型 | `di(`/`da"` 等 |
| `find` | 目标字符 | `f`/`t` 等字符查找 |
| `g` | `j`/`k`/`g` | `gj`/`gk`/`gg` |
| `operatorG` | `j`/`k`/`g` | 操作符 + `G` |
| `replace` | 替换字符 | `r` 命令 |
| `indent` | `>` 或 `<` | `>>`/`<<` 等 |

#### `PersistentState`

```typescript
type PersistentState = {
  lastChange: RecordedChange | null
  lastFind: { type: FindType; char: string } | null
  register: string
  registerIsLinewise: boolean
}
```

跨命令持久化的 Vim 状态——即 Vim 的"记忆"。用于重复（`.`）、粘贴（`p`/`P`）和查找重复（`;`/`,`）。

| 字段 | 含义 |
|------|------|
| `lastChange` | 最近一次变更（用于 dot-repeat） |
| `lastFind` | 最近一次字符查找（用于 `;`/`,`） |
| `register` | 当前寄存器内容 |
| `registerIsLinewise` | 寄存器内容是否为行级粘贴 |

#### `RecordedChange`

```typescript
type RecordedChange =
  | { type: 'insert'; text: string }
  | { type: 'operator'; op: Operator; motion: string; count: number }
  | { type: 'operatorTextObj'; op: Operator; objType: string; scope: TextObjScope; count: number }
  | { type: 'operatorFind'; op: Operator; find: FindType; char: string; count: number }
  | { type: 'replace'; char: string; count: number }
  | { type: 'x'; count: number }
  | { type: 'toggleCase'; count: number }
  | { type: 'indent'; dir: '>' | '<'; count: number }
  | { type: 'openLine'; direction: 'above' | 'below' }
  | { type: 'join'; count: number }
```

记录的可重复变更。捕获重放命令所需的全部信息。

### 导出常量

#### `OPERATORS`

```typescript
const OPERATORS = {
  d: 'delete',
  c: 'change',
  y: 'yank',
} as const satisfies Record<string, Operator>
```

操作符按键映射。

#### `SIMPLE_MOTIONS`

```typescript
const SIMPLE_MOTIONS = new Set([
  'h', 'l', 'j', 'k',           // Basic movement
  'w', 'b', 'e', 'W', 'B', 'E', // Word motions
  '0', '^', '$',                // Line positions
])
```

简单动作键集合——可在 idle 状态直接执行，或在 operator 状态作为 motion。

#### `FIND_KEYS`

```typescript
const FIND_KEYS = new Set(['f', 'F', 't', 'T'])
```

字符查找命令键集合。

#### `TEXT_OBJ_SCOPES`

```typescript
const TEXT_OBJ_SCOPES = {
  i: 'inner',
  a: 'around',
} as const satisfies Record<string, TextObjScope>
```

文本对象范围前缀映射。

#### `TEXT_OBJ_TYPES`

```typescript
const TEXT_OBJ_TYPES = new Set([
  'w', 'W',                        // Word/WORD
  '"', "'", '`',                   // Quotes
  '(', ')', 'b',                  // Parens
  '[', ']',                        // Brackets
  '{', '}', 'B',                  // Braces
  '<', '>',                        // Angle brackets
])
```

支持的文本对象类型集合。

#### `MAX_VIM_COUNT`

```typescript
const MAX_VIM_COUNT = 10000
```

操作符计数的上限，防止过度重复。

### 导出函数

#### `isOperatorKey()`

```typescript
function isOperatorKey(key: string): key is keyof typeof OPERATORS
```

类型守卫函数，判断键是否为操作符键。

#### `isTextObjScopeKey()`

```typescript
function isTextObjScopeKey(key: string): key is keyof typeof TEXT_OBJ_SCOPES
```

类型守卫函数，判断键是否为文本对象范围前缀（`i` 或 `a`）。

#### `createInitialVimState()`

```typescript
function createInitialVimState(): VimState
```

工厂函数——返回初始 Vim 状态 `{ mode: 'INSERT', insertedText: '' }`。

#### `createInitialPersistentState()`

```typescript
function createInitialPersistentState(): PersistentState
```

工厂函数——返回初始持久化状态，所有寄存器置空。

---

## motions.ts — 纯函数式移动计算

`motions.ts` 实现了所有 Vim 动作的纯计算逻辑。给定当前光标位置、动作键和计数，返回计算后的目标光标位置。不修改任何状态。

### 导出函数

#### `resolveMotion()`

```typescript
function resolveMotion(
  key: string,
  cursor: Cursor,
  count: number,
): Cursor
```

解析动作键并计算目标光标位置。

**核心逻辑：**

1. 初始化结果为当前光标
2. 循环 `count` 次应用单步动作
3. 若单步动作未产生位移，提前终止循环
4. 返回最终光标位置

#### `isInclusiveMotion()`

```typescript
function isInclusiveMotion(key: string): boolean
```

判断动作是否为 inclusive（含目标字符）。

**inclusive 动作**：`e`、`E`、`$`——动作终点包含该字符。

```typescript
// 示例：de 删除从当前字符到 word 结尾的所有字符
// inclusive 意味着 'word' 的 'd' 也被删除
```

#### `isLinewiseMotion()`

```typescript
function isLinewiseMotion(key: string): boolean
```

判断动作是否为 linewise（行级操作）。

**linewise 动作**：`G`、`gg`——跳转到指定行首，操作覆盖完整行。

> 注意：`gj`/`gk` 按 `:help gj` 规范为 characterwise exclusive，非 linewise。

**支持的动作一览：**

| 键 | 动作 | 类型 |
|----|------|------|
| `h` | 左移一字符 | characterwise |
| `l` | 右移一字符 | characterwise |
| `j` | 下移一行（逻辑行） | characterwise |
| `k` | 上移一行（逻辑行） | characterwise |
| `gj` | 下移一行（显示行） | characterwise |
| `gk` | 上移一行（显示行） | characterwise |
| `w` | 下一 word 开头 | characterwise |
| `b` | 上一 word 开头 | characterwise |
| `e` | 当前 word 结尾 | inclusive |
| `W` | 下一 WORD 开头 | characterwise |
| `B` | 上一 WORD 开头 | characterwise |
| `E` | 当前 WORD 结尾 | inclusive |
| `0` | 行首 | characterwise |
| `^` | 行首非空白 | characterwise |
| `$` | 行尾 | inclusive |
| `G` | 最后一行开头（通过 `handleNormalInput` 单独处理） | linewise |

---

## textObjects.ts — 文本对象边界计算

`textObjects.ts` 实现了文本对象（text object）的边界查找。给定文本、光标偏移和对象类型，计算选中范围的起始和结束偏移。

### 导出类型

#### `TextObjectRange`

```typescript
type TextObjectRange = { start: number; end: number } | null
```

文本对象范围。若当前位置不存在有效对象（如不在任何引号内），返回 `null`。

### 导出函数

#### `findTextObject()`

```typescript
function findTextObject(
  text: string,
  offset: number,
  objectType: string,
  isInner: boolean,
): TextObjectRange
```

查找给定偏移处的文本对象范围。

| 参数 | 含义 |
|------|------|
| `text` | 完整文本 |
| `offset` | 当前光标偏移 |
| `objectType` | 对象类型（如 `w`、`"`、`(`、`{`） |
| `isInner` | `true` = inner（不含分隔符），`false` = around（含分隔符） |

**支持的对象类型：**

| 类型 | 对象 | 说明 |
|------|------|------|
| `iw` | inner word | 单词内容 |
| `aw` | around word | 单词及周围空白 |
| `iW` | inner WORD | WORD 内容 |
| `aW` | around WORD | WORD 及周围空白 |
| `i"` | inner double quote | 引号内内容 |
| `a"` | around double quote | 含引号 |
| `i'` | inner single quote | 引号内内容 |
| `a'` | around single quote | 含引号 |
| `` i` `` | inner backtick | 引号内内容 |
| `` a` `` | around backtick | 含引号 |
| `i(` / `ib` | inner parens | 括号内 |
| `a(` / `ab` | around parens | 含括号 |
| `i)` | inner parens | 同 `i(` |
| `a)` | around parens | 同 `a(` |
| `i[` | inner bracket | 方括号内 |
| `a[` | around bracket | 含方括号 |
| `i{` / `iB` | inner brace | 花括号内 |
| `a{` / `aB` | around brace | 含花括号 |
| `i<` | inner angle bracket | 尖括号内 |
| `a<` | around angle bracket | 含尖括号 |

**核心逻辑（单词对象）：**

1. 使用 `getGraphemeSegmenter()` 对文本进行 grapheme 级分段，确保多字节字符正确处理
2. 定位当前偏移所在的 grapheme 索引
3. 根据字符类型（word/whitespace/punctuation）向两端扩展
4. `around` 模式下额外包含周围空白

**核心逻辑（引号对象）：**

1. 定位当前偏移所在行
2. 收集行内所有引号位置（配对：0-1, 2-3, 4-5...）
3. 查找包含当前位置的引号对
4. `inner` 返回引号内内容（不含引号），`around` 含引号本身

**核心逻辑（括号对象）：**

1. 从当前位置反向扫描，统计 `close` 括号深度，找到配对的 `open`
2. 从 `open` 位置正向扫描，统计 `open` 深度，找到配对的 `close`
3. `inner` 返回括号内（不含括号），`around` 含括号

---

## operators.ts — 操作符执行模块

`operators.ts` 实现了所有 Vim 操作符的执行逻辑。操作符接收 `OperatorContext`（包含 cursor/text/setText 等回调），通过调用纯函数 `resolveMotion` 和 `findTextObject` 计算目标范围，然后通过回调修改状态。

### 导出类型

#### `OperatorContext`

```typescript
type OperatorContext = {
  cursor: Cursor
  text: string
  setText: (text: string) => void
  setOffset: (offset: number) => void
  enterInsert: (offset: number) => void
  getRegister: () => string
  setRegister: (content: string, linewise: boolean) => void
  getLastFind: () => { type: FindType; char: string } | null
  setLastFind: (type: FindType, char: string) => void
  recordChange: (change: RecordedChange) => void
}
```

操作符执行的上下文——封装了所有状态读写操作。纯函数通过此接口与外部状态解耦。

| 字段 | 含义 |
|------|------|
| `cursor` | 当前光标（带文本测量信息） |
| `text` | 当前文本内容 |
| `setText` | 设置新文本内容 |
| `setOffset` | 设置光标偏移 |
| `enterInsert` | 进入 INSERT 模式 |
| `getRegister` | 获取寄存器内容 |
| `setRegister` | 设置寄存器内容 |
| `getLastFind` | 获取最近一次字符查找 |
| `setLastFind` | 设置最近一次字符查找 |
| `recordChange` | 记录变更（用于 dot-repeat） |

### 导出函数

#### `executeOperatorMotion()`

```typescript
function executeOperatorMotion(
  op: Operator,
  motion: string,
  count: number,
  ctx: OperatorContext,
): void
```

执行操作符 + 简单动作（如 `dw`、`ce`、`yw`）。

**核心逻辑：**

1. `resolveMotion()` 计算目标光标
2. 若目标未变化，直接返回
3. `getOperatorRange()` 计算操作范围（含 special case 如 `cw`）
4. `applyOperator()` 执行实际操作
5. `recordChange()` 记录变更

#### `executeOperatorFind()`

```typescript
function executeOperatorFind(
  op: Operator,
  findType: FindType,
  char: string,
  count: number,
  ctx: OperatorContext,
): void
```

执行操作符 + 查找动作（如 `dfx`、`ctx`）。

**核心逻辑：**

1. `cursor.findCharacter()` 查找目标字符
2. 若未找到，直接返回
3. 计算操作范围（find 类型已由 `Cursor.findCharacter` 调整偏移）
4. `applyOperator()` 执行操作
5. 更新 lastFind 并记录变更

#### `executeOperatorTextObj()`

```typescript
function executeOperatorTextObj(
  op: Operator,
  scope: TextObjScope,
  objType: string,
  count: number,
  ctx: OperatorContext,
): void
```

执行操作符 + 文本对象（如 `diw`、`da"`、`ci(`）。

**核心逻辑：**

1. `findTextObject()` 查找文本对象范围
2. 若不存在，直接返回
3. `applyOperator()` 执行操作
4. 记录变更

#### `executeLineOp()`

```typescript
function executeLineOp(
  op: Operator,
  count: number,
  ctx: OperatorContext,
): void
```

执行行级操作（`dd`、`cc`、`yy`）。

**核心逻辑：**

1. 计算当前逻辑行（通过 `\n` 数量而非 `cursor.getPosition()`）
2. 计算受影响的行范围
3. **yank**：提取内容存入寄存器，保持原位置
4. **delete**：
   - 提取内容存入寄存器
   - 删除行（特殊处理文件末尾的尾随换行）
   - 移动光标到删除起点
5. **change**：删除行后插入空行，进入 INSERT 模式

#### `executeX()`

```typescript
function executeX(count: number, ctx: OperatorContext): void
```

删除光标下的字符（`x` 命令）。按 grapheme 级别删除而非 code unit。

**核心逻辑：**

1. 循环 `count` 次右移光标（grapheme 级）
2. 提取待删除内容
3. 更新寄存器（characterwise）、文本和光标位置
4. 记录变更

#### `executeReplace()`

```typescript
function executeReplace(
  char: string,
  count: number,
  ctx: OperatorContext,
): void
```

替换光标下的字符（`r` 命令）。

**核心逻辑：**

1. 循环 `count` 次
2. 按 grapheme 长度替换单个字符
3. 光标移动到最后一个替换字符后
4. 记录变更

#### `executeToggleCase()`

```typescript
function executeToggleCase(count: number, ctx: OperatorContext): void
```

大小写切换（`~` 命令）。

**核心逻辑：**

1. 循环 `count` 次处理 grapheme
2. 大写转小写，小写转大写
3. 光标移动到最后一个转换字符后
4. 记录变更

#### `executeJoin()`

```typescript
function executeJoin(count: number, ctx: OperatorContext): void
```

连接行（`J` 命令）。

**核心逻辑：**

1. 计算需要连接的行数
2. 逐行连接，用单个空格分隔（除非前一行已以空格结尾）
3. 合并后的行保留原始行的尾部空白修剪
4. 记录变更

#### `executePaste()`

```typescript
function executePaste(
  after: boolean,
  count: number,
  ctx: OperatorContext,
): void
```

粘贴寄存器内容（`p`/`P` 命令）。

**核心逻辑：**

1. 判断寄存器内容是否为行级（以 `\n` 结尾）
2. **行级粘贴**：
   - 在当前行后（前）插入完整行
   - 光标移动到插入位置
3. **字符级粘贴**：
   - 在当前光标后（前）插入内容
   - 处理 grapheme 边界对齐
4. 支持重复粘贴 `count` 次
5. 不记录到变更历史（粘贴是独立操作）

#### `executeIndent()`

```typescript
function executeIndent(
  dir: '>' | '<',
  count: number,
  ctx: OperatorContext,
): void
```

缩进/取消缩进行（`>>`/`<<` 命令）。

**核心逻辑：**

1. 影响从当前行开始的 `count` 行
2. 右缩进：添加两个空格
3. 左缩进：移除两个空格；若以 tab 开头则移除一个 tab；否则移除最多两个空白字符
4. 光标跟随行首移动
5. 记录变更

#### `executeOpenLine()`

```typescript
function executeOpenLine(
  direction: 'above' | 'below',
  ctx: OperatorContext,
): void
```

打开新行（`o`/`O` 命令）。

**核心逻辑：**

1. 在当前行上方或下方插入空行
2. 进入 INSERT 模式，光标在新行行首
3. 记录变更

#### `executeOperatorG()`

```typescript
function executeOperatorG(
  op: Operator,
  count: number,
  ctx: OperatorContext,
): void
```

操作符 + `G`（如 `dG`、`yG`）。

- `count === 1`：无计数，从当前位置到文件末尾
- `count > 1`：跳转到第 `count` 行后执行

#### `executeOperatorGg()`

```typescript
function executeOperatorGg(
  op: Operator,
  count: number,
  ctx: OperatorContext,
): void
```

操作符 + `gg`（如 `dgg`、`cgg`）。

- `count === 1`：无计数，到第一行
- `count > 1`：跳转到第 `count` 行后执行

### 内部辅助函数

#### `getOperatorRange()`

```typescript
function getOperatorRange(
  cursor: Cursor,
  target: Cursor,
  motion: string,
  op: Operator,
  count: number,
): { from: number; to: number; linewise: boolean }
```

计算操作符的作用范围。

**Special case：`cw`/`cW`**

`change` + `word` 时，范围为当前 word 结尾到下一 word 开头，而非到 word 开始。

**Linewise 范围：**

- linewise 动作时，`to` 扩展到行尾换行符
- 删除到文件末尾时，包含前一行尾的换行符

**Inclusive 范围：**

- `e`/`$` 等 inclusive 动作，`to` 包含目标字符（`nextOffset`）

**图像引用边界：**

- `snapOutOfImageRef()` 确保 word 动作不会留下部分图像引用（如 `[Image #1]`）

#### `applyOperator()`

```typescript
function applyOperator(
  op: Operator,
  from: number,
  to: number,
  ctx: OperatorContext,
  linewise?: boolean,
): void
```

执行实际操作（yank/delete/change）。根据操作符类型调用对应回调。

---

## transitions.ts — 状态转换表

`transitions.ts` 是 Vim 状态机的转换引擎，实现了从当前状态和输入到下一状态和执行动作的映射。这是整个状态机的可扫描真相来源。

### 导出类型

#### `TransitionContext`

```typescript
type TransitionContext = OperatorContext & {
  onUndo?: () => void
  onDotRepeat?: () => void
}
```

传递给转换函数的完整上下文，包含操作符上下文和可选的 undo/dot-repeat 回调。

#### `TransitionResult`

```typescript
type TransitionResult = {
  next?: CommandState
  execute?: () => void
}
```

转换结果：`next` 为下一状态，`execute` 为待执行的副作用函数。

### 导出函数

#### `transition()`

```typescript
function transition(
  state: CommandState,
  input: string,
  ctx: TransitionContext,
): TransitionResult
```

主转换函数——根据当前状态类型分发到对应的转换处理函数。

**状态分发一览：**

| 当前状态 | 处理函数 |
|----------|----------|
| `idle` | `fromIdle` |
| `count` | `fromCount` |
| `operator` | `fromOperator` |
| `operatorCount` | `fromOperatorCount` |
| `operatorFind` | `fromOperatorFind` |
| `operatorTextObj` | `fromOperatorTextObj` |
| `find` | `fromFind` |
| `g` | `fromG` |
| `operatorG` | `fromOperatorG` |
| `replace` | `fromReplace` |
| `indent` | `fromIndent` |

### 转换处理函数

#### `fromIdle()`

处理 idle 状态输入。

**核心逻辑：**

1. `0` 是行首动作，不是计数前缀
2. 数字 `1-9` 进入 `count` 状态
3. 其他输入委托 `handleNormalInput()`

#### `fromCount()`

处理计数输入状态。

**核心逻辑：**

1. 继续输入数字累积计数（上限 `MAX_VIM_COUNT`）
2. 非数字输入使用累积计数委托 `handleNormalInput()`
3. 输入无效则返回 `idle`

#### `fromOperator()`

处理 operator 状态。

**核心逻辑：**

1. 双击操作符键（如 `dd`）执行行操作
2. 数字输入进入 `operatorCount` 状态
3. 其他输入委托 `handleOperatorInput()`

#### `handleNormalInput()`

idle 和 count 状态共用的输入处理。

**识别的输入类型：**

| 输入 | 行为 |
|------|------|
| 操作符键 `d/c/y` | 进入 `operator` 状态 |
| 简单动作 | 直接执行 motion |
| 查找键 `f/F/t/T` | 进入 `find` 状态 |
| `g` | 进入 `g` 状态 |
| `r` | 进入 `replace` 状态 |
| `>`/`<` | 进入 `indent` 状态 |
| `~` | 执行 toggle case |
| `x` | 执行删除字符 |
| `J` | 执行连接行 |
| `p`/`P` | 执行粘贴 |
| `D`/`C`/`Y` | 执行 `d$`/`c$`/`yy` |
| `G` | 跳转到指定行 |
| `.` | 执行 dot-repeat |
| `;`/`,` | 重复/反向重复查找 |
| `u` | 执行 undo |
| `i`/`I`/`a`/`A` | 进入 INSERT 模式 |
| `o`/`O` | 打开新行 |

#### `handleOperatorInput()`

operator 状态共用的输入处理。

**识别的输入类型：**

| 输入 | 行为 |
|------|------|
| 文本对象范围前缀 `i`/`a` | 进入 `operatorTextObj` 状态 |
| 查找键 `f/F/t/T` | 进入 `operatorFind` 状态 |
| 简单动作 | 执行 operator + motion |
| `G` | 执行 operator + G |
| `g` | 进入 `operatorG` 状态 |

#### `fromFind()`

处理 `f`/`F`/`t`/`T` 状态——等待目标字符输入。

**参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `state` | `CommandState` | 当前 `find` 状态，包含查找类型和计数 |
| `input` | `string` | 用户输入的目标字符 |
| `ctx` | `TransitionContext` | 转换上下文 |

**核心逻辑：**

1. 查找类型已在 `state.find` 中确定（`f`/`F`/`t`/`T`）
2. `input` 为用户按下的目标字符
3. 使用 `Cursor.findCharacter()` 在文本中查找目标字符
4. 若找到，更新光标位置并返回 `idle`；未找到则保持在 `find` 状态
5. 将本次查找记录到 `lastFind`（用于 `;`/`,` 重复）

#### `fromG()`

处理 `g` 状态——等待后续输入 `j`/`k`/`g` 以确定完整命令。

**参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `state` | `CommandState` | 当前 `g` 状态，包含计数 |
| `input` | `string` | 用户输入（`j`、`k` 或 `g`） |
| `ctx` | `TransitionContext` | 转换上下文 |

**核心逻辑：**

1. `gj`：下移一行（显示行，非逻辑行）
2. `gk`：上移一行（显示行，非逻辑行）
3. `gg`：跳转到第一行（`count` 为行号，默认为 1）
4. 其他输入无效，返回 `idle`

#### `fromOperatorG()`

处理 operator 后接 `G` 的情况——从当前行执行到指定行。

**参数：**

| 参数 | 类型 | 含义 |
|------|------|------|
| `state` | `CommandState` | 当前 `operatorG` 状态，包含操作符和计数 |
| `input` | `string` | 用户输入（`g` 或其他） |
| `ctx` | `TransitionContext` | 转换上下文 |

**核心逻辑：**

1. 等待 `g` 输入确认 `G` 命令
2. `count === 1` 或无计数：从当前行到文件末尾
3. `count > 1`：跳转到第 `count` 行
4. 执行对应操作符（delete/change/yank）到目标位置
5. 返回 `idle`

#### `fromReplace()`

处理 `r` 状态——等待替换字符。

> 特殊：`r<BS>`（空输入）取消替换，返回 idle。

#### `fromIndent()`

处理 `>`/`>` 状态——等待第二个 `>` 或 `<`。

#### `executeRepeatFind()`

执行 `;`/`,` 重复查找。

**核心逻辑：**

1. 获取最近一次查找（类型和字符）
2. `,` 时翻转方向（`f` → `F`）
3. 使用 `Cursor.findCharacter()` 定位目标
4. 更新光标位置
