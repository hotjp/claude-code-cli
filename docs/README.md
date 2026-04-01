# Claude Code CLI 源码分析

> Anthropic 官方 Claude Code CLI 工具的源代码学习与分析项目

## 文档目录

| 章节 | 说明 |
|------|------|
| [01 - 根目录核心文件](01-root-core.md) | 项目基础架构层：工具抽象、命令注册、查询引擎、任务管理 |
| [02 - 工具系统](02-tools.md) | tools/ 目录下所有工具的实现 |
| [03 - 命令系统](03-commands.md) | commands/ 目录下的斜杠命令实现 |
| [04 - 服务层](04-services.md) | services/ 核心业务逻辑模块 |
| [05 - 状态管理与工具函数](05-state-and-utils.md) | state/ 状态存储与通用工具 |

## 技术栈

- **语言**: TypeScript / TSX
- **运行时**: Bun
- **UI 框架**: Ink (React for CLI)
- **CLI 框架**: Commander.js
