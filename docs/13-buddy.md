# Buddy 模块 (buddy/)

## 架构概览

Buddy 模块是一个桌面宠物（Companion）系统，用户通过 `/buddy` 命令孵化和收养一个基于 ASCII 艺术的小生物。它位于用户输入框旁边，以 Sprite 形式显示在终端中，会在空闲时 fidget，偶尔眨眼，并在用户直接呼叫它时通过气泡回复。

核心设计原则：
- **确定性roll**：Companion 的外观（物种、眼睛、帽子、稀有度）由 `userId` 哈希决定，永不存储在服务端，防止作弊
- **Bones + Soul 分离**：外观属性（Bones）每次从哈希重新生成，名字和性格（ Soul）由模型生成后存储在配置中
- **特性门控**：整个模块受 `BUDDY` 特性标志控制（`feature('BUDDY')`）

### 核心类型

| 类型 | 说明 |
|------|------|
| `Species` | 物种枚举（18 种：duck, goose, blob, cat, dragon, octopus, owl, penguin, turtle, snail, ghost, axolotl, capybara, cactus, robot, rabbit, mushroom, chonk） |
| `Rarity` | 稀有度枚举（common, uncommon, rare, epic, legendary） |
| `Eye` | 眼睛样式（`'·' \| '✦' \| '×' \| '◉' \| '@' \| '°'`） |
| `Hat` | 帽子样式（none, crown, tophat, propeller, halo, wizard, beanie, tinyduck） |
| `StatName` | 属性名称（DEBUGGING, PATIENCE, CHAOS, WISDOM, SNARK） |
| `CompanionBones` | 确定性外观（rarity, species, eye, hat, shiny, stats） |
| `CompanionSoul` | 存储的灵魂（name, personality） |
| `Companion` | Bones + Soul 组合体 |
| `StoredCompanion` | 配置中持久化的部分（仅 Soul + hatchedAt） |

### 稀有度系统

| 稀有度 | 权重 | 星级 | 颜色主题 |
|--------|------|------|----------|
| `common` | 60 | ★ | `inactive` |
| `uncommon` | 25 | ★★ | `success` |
| `rare` | 10 | ★★★ | `permission` |
| `epic` | 4 | ★★★★ | `autoAccept` |
| `legendary` | 1 | ★★★★★ | `warning` |

---

## 核心接口

### companion.ts

**文件**: `buddy/companion.ts`

**核心函数**:

- **`roll(userId: string): Roll`** — 根据 userId 哈希生成 CompanionBones，结果会被缓存（`rollCache`），避免热路径（500ms sprite tick、逐按键 PromptInput、每轮 observer）重复计算
- **`rollWithSeed(seed: string): Roll`** — 使用指定种子生成 Roll，用于确定性测试
- **`companionUserId(): string`** — 获取当前用户的唯一标识（优先使用 oauthAccount.accountUuid，否则用 userID）
- **`getCompanion(): Companion | undefined`** — 获取当前 Companion：先用 `roll(userId)` 生成 Bones，再与 `config.companion`（Soul）合并

**roll 流程**:
1. Mulberry32 PRNG（基于 `hashString(userId + SALT)`）生成随机数
2. `rollRarity()` 按权重抽取稀有度
3. 随机选择 species、eye、hat（common 无帽子）
4. 1% 概率 shiny
5. `rollStats()` 分配属性：峰值属性 +50~79，垃圾属性 floor-10~+4，中间属性 floor~floor+39

---

### sprites.ts

**文件**: `buddy/sprites.ts`

**核心函数**:

- **`renderSprite(bones: CompanionBones, frame?: number): string[]`** — 渲染 ASCII Sprite 的 5 行身体，支持 3 种 fidget 帧动画，自动去掉空白的 hat slot
- **`spriteFrameCount(species: Species): number`** — 返回某物种的总帧数（均为 3）
- **`renderFace(bones: CompanionBones): string`** — 渲染紧凑型单行 face（用于窄终端）

**Sprite 规格**:
- 每帧 5 行高，12 字符宽
- `{E}` 占位符替换为实际眼睛字符
- 帧 0-1 的第 0 行为 hat slot（某些帧用于烟雾/天线等效果）
- Idle 序列：`[0, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, 2, 0, 0, 0]`（-1 = 眨眼）

**支持的 18 种物种**: duck, goose, blob, cat, dragon, octopus, owl, penguin, turtle, snail, ghost, axolotl, capybara, cactus, robot, rabbit, mushroom, chonk

---

### prompt.ts

**文件**: `buddy/prompt.ts`

**核心函数**:

- **`companionIntroText(name: string, species: string): string`** — 生成 Companion 的系统提示词，说明 Companion 是一个坐在用户输入框旁的小生物，当用户直接呼叫它时会回答
- **`getCompanionIntroAttachment(messages?: Message[]): Attachment[]`** — 生成 `companion_intro` 类型的附件，仅在首次（messages 中无同 name 的 companion_intro 时）返回

---

### CompanionSprite.tsx

**文件**: `buddy/CompanionSprite.tsx`

**核心组件**:

- **`CompanionSprite()`** — 主渲染组件，500ms tick 驱动动画
  - 窄终端（< 100 cols）：折叠为单行 face + label
  - 正常终端：渲染完整 ASCII sprite + 名字行
  - 有 reaction 时：显示 SpeechBubble（右侧尾巴），10s 后淡出
  - 有 petAt 时：显示漂浮爱心动画（5 帧，约 2.5s）

- **`CompanionFloatingBubble()`** — 全屏模式下的浮动气泡，渲染在 `FullscreenLayout.bottomFloat` 槽位（溢出隐藏区域外）

**关键常量**:
| 常量 | 值 | 说明 |
|------|---|------|
| `TICK_MS` | 500 | 动画 tick 间隔 |
| `BUBBLE_SHOW` | 20 ticks (~10s) | 气泡显示时长 |
| `FADE_WINDOW` | 6 ticks (~3s) | 淡出窗口 |
| `PET_BURST_MS` | 2500 | /buddy pet 爱心动画持续时间 |
| `MIN_COLS_FOR_FULL_SPRITE` | 100 | 显示完整 sprite 所需最小列宽 |

**导出的布局函数**:
- **`companionReservedColumns(terminalColumns, speaking): number`** — 计算 Companion 区域占用的列数，用于 PromptInput 文本折行

---

### useBuddyNotification.tsx

**文件**: `buddy/useBuddyNotification.tsx`

**核心函数**:

- **`useBuddyNotification()`** — React Hook，在首次启动时（无已孵化的 companion + 在 teaser 窗口内）显示彩虹 `/buddy` 提示通知
- **`isBuddyTeaserWindow(): boolean`** — 判断是否在 teaser 窗口（2026年4月1-7日）
- **`isBuddyLive(): boolean`** — 判断 Buddy 功能是否已上线（2026年4月之后）
- **`findBuddyTriggerPositions(text: string): Array<{start, end}>`** — 在文本中查找 `/buddy` 触发位置（用于特殊高亮或交互）

---

## 文件索引

| 文件 | 作用 |
|------|------|
| `buddy/types.ts` | 所有类型定义、常量（物种、稀有度、眼睛、帽子、属性）及 RARITY_* 映射表 |
| `buddy/companion.ts` | Companion 随机生成逻辑（roll 系统）、缓存、userId 获取、getCompanion |
| `buddy/sprites.ts` | ASCII sprite 渲染（20 物种 x 3 帧）、face 渲染、HAT_LINES |
| `buddy/prompt.ts` | Companion 系统提示词生成、intro 附件构造 |
| `buddy/CompanionSprite.tsx` | React 组件：主 sprite 渲染、SpeechBubble、浮动气泡、动画状态机 |
| `buddy/useBuddyNotification.tsx` | React Hook：teaser 通知、高亮触发器查找、上下线判断 |
