# Claude Code CLI 源码分析

> Anthropic 官方 Claude Code CLI 工具的源代码学习与分析项目

## 文档目录

### 核心架构

| 章节 | 说明 |
|------|------|
| [01 - 根目录核心文件](01-root-core.md) | 项目基础架构层：工具抽象、命令注册、查询引擎、任务管理 |
| [02 - 工具系统](02-tools.md) | tools/ 目录下所有工具的实现 |
| [03 - 命令系统](03-commands.md) | commands/ 目录下的斜杠命令实现 |
| [04 - 服务层](04-services.md) | services/ 核心业务逻辑模块 |
| [05 - 状态管理与工具函数](05-state-and-utils.md) | state/ 状态存储与通用工具 |

### UI 与基础设施

| 章节 | 说明 |
|------|------|
| [06 - UI 组件、Hooks 与终端渲染引擎](06-components-hooks-ink.md) | components/、hooks/、ink/ 目录 |
| [07 - 启动引导、类型定义、常量与查询层](07-bootstrap-types-constants.md) | bootstrap/、types/、constants/、schemas/、query/ |
| [08 - 上游代理](08-upstreamproxy.md) | upstreamproxy/ 代理模块 |
| [09 - Vim 模式编辑器](09-vim.md) | vim/ 目录 |
| [10 - React Context 状态管理](10-context.md) | context/ 目录 |

### 功能模块

| 章节 | 说明 |
|------|------|
| [11 - 根目录零散模块](11-root-modules.md) | 根目录下未归类的独立模块 |
| [12 - Bridge 模块](12-bridge.md) | bridge/ 进程间通信 |
| [13 - Buddy 模块](13-buddy.md) | buddy/ 辅助功能 |
| [14 - CLI 模块](14-cli.md) | cli/ 命令行界面 |
| [15 - Coordinator 模块](15-coordinator.md) | coordinator/ 协调者模式 |

### 入口与扩展

| 章节 | 说明 |
|------|------|
| [16 - Entrypoints 模块](16-entrypoints.md) | entrypoints/ 入口点与 SDK |
| [17 - 键盘绑定系统](17-keybindings.md) | keybindings/ 快捷键配置 |
| [18 - Memdir 模块](18-memdir.md) | memdir/ 内存目录 |
| [19 - Migrations 模块](19-migrations.md) | migrations/ 数据迁移 |
| [20 - Moreright 模块](20-moreright.md) | moreright/ 扩展模块 |
| [21 - Native-TS 模块](21-native-ts.md) | native-ts/ 原生绑定 |

## 技术栈

- **语言**: TypeScript / TSX
- **运行时**: Bun
- **UI 框架**: Ink (React for CLI)
- **CLI 框架**: Commander.js
