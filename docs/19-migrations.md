# Migrations 模块 (migrations/)

## 架构概览

Migrations 模块负责在版本升级过程中执行一次性数据迁移，确保用户配置从旧格式平滑过渡到新格式。每个迁移函数专注于一类配置的移动、转换或清理，通常在应用启动时按序执行一次。

### 核心设计原则

- **幂等性**: 大多数迁移通过比较源值与目标值来判断是否需要执行，避免重复写入
- **失败安全**: 迁移失败时记录错误但不会阻断启动
- **隔离性**: 仅操作 `userSettings`/`localSettings`/`globalConfig` 中明确指定的字段
- **可观测性**: 每个迁移通过 `logEvent()` 记录分析事件

### 执行时机

迁移在 `main.tsx` 的 `runMigrations()` 函数中统一调度：

```typescript
启动 → runMigrations() → 检查 migrationVersion
  → 版本不匹配: 执行所有待运行迁移
  → saveGlobalConfig({ migrationVersion: CURRENT_MIGRATION_VERSION })
  → 异步: migrateChangelogFromConfig() (fire-and-forget)
```

- **`CURRENT_MIGRATION_VERSION`**：当前迁移版本号（`main.tsx:325`），每次新增迁移递增
- **`runMigrations()`**：检查 `globalConfig.migrationVersion !== CURRENT_MIGRATION_VERSION` 后执行
- 同步迁移全部执行完毕后立即更新 `migrationVersion`（非每个迁移单独更新）
- `migrateChangelogFromConfig` 为异步迁移，fire-and-forget 模式执行

### 迁移顺序

```typescript
// main.tsx:33-52, "external" === 'ant' check at main.tsx:340
migrateAutoUpdatesToSettings();
migrateBypassPermissionsAcceptedToSettings();
migrateEnableAllProjectMcpServersToSettings();
resetProToOpusDefault();
migrateSonnet1mToSonnet45();
migrateLegacyOpusToCurrent();
migrateSonnet45ToSonnet46();
migrateOpusToOpus1m();
migrateReplBridgeEnabledToRemoteControlAtStartup();
if (feature('TRANSCRIPT_CLASSIFIER')) {
  resetAutoModeOptInForDefaultOffer();
}
if ("external" === 'ant') {
  migrateFennecToOpus();
}
// NOTE: The condition `"external" === 'ant'` is always false because it compares two
// string literals. This means migrateFennecToOpus() is NEVER called through the normal
// migration path. The migration function itself has its own internal USER_TYPE check
// as a safety net, but the main.tsx caller never triggers it.
saveGlobalConfig({ migrationVersion: CURRENT_MIGRATION_VERSION });
// 异步:
migrateChangelogFromConfig().catch(() => {}); // fire-and-forget
```

---

## 全局配置迁移

### migrateAutoUpdatesToSettings

**用途**: 将用户显式设置的 `autoUpdates: false` 偏好迁移到 `settings.json` 的 `env.DISABLE_AUTOUPDATER`。

**触发条件**:
- `globalConfig.autoUpdates === false`
- `globalConfig.autoUpdatesProtectedForNative !== true`（非系统自动保护）

**迁移逻辑**:
1. 读取 `userSettings`，设置 `env.DISABLE_AUTOUPDATER: '1'`
2. 立即生效：`process.env.DISABLE_AUTOUPDATER = '1'`
3. 从 `globalConfig` 中移除 `autoUpdates` 和 `autoUpdatesProtectedForNative`

**文件**: `migrations/migrateAutoUpdatesToSettings.ts`

---

### migrateBypassPermissionsAcceptedToSettings

**用途**: 将 `bypassPermissionsModeAccepted` 从 `globalConfig` 迁移到 `settings.json` 的 `skipDangerousModePermissionPrompt` 字段。

**触发条件**: `globalConfig.bypassPermissionsModeAccepted` 存在

**迁移逻辑**:
1. 在 `settings.json` 中写入 `skipDangerousModePermissionPrompt: true`
2. 从 `globalConfig` 中移除 `bypassPermissionsModeAccepted`

**文件**: `migrations/migrateBypassPermissionsAcceptedToSettings.ts`

---

### migrateReplBridgeEnabledToRemoteControlAtStartup

**用途**: 将已废弃的 `replBridgeEnabled` 配置键迁移到 `remoteControlAtStartup`。

**触发条件**: `replBridgeEnabled` 存在且 `remoteControlAtStartup` 未设置

**迁移逻辑**:
1. 读取 `replBridgeEnabled` 值，类型转换为布尔值
2. 写入 `remoteControlAtStartup`
3. 删除 `replBridgeEnabled`

**文件**: `migrations/migrateReplBridgeEnabledToRemoteControlAtStartup.ts`

---

## MCP 服务器迁移

### migrateEnableAllProjectMcpServersToSettings

**用途**: 将 MCP 服务器审批字段从项目配置迁移到本地设置。

**迁移字段**:

| 源字段 (projectConfig) | 目标字段 (localSettings) | 说明 |
|------------------------|--------------------------|------|
| `enableAllProjectMcpServers` | `enableAllProjectMcpServers` | 是否启用所有项目 MCP 服务器 |
| `enabledMcpjsonServers` | `enabledMcpjsonServers` | 已启用的 MCP 服务器列表（合并去重） |
| `disabledMcpjsonServers` | `disabledMcpjsonServers` | 已禁用的 MCP 服务器列表（合并去重） |

**触发条件**: 上述任意字段在 `projectConfig` 中存在

**迁移逻辑**:
1. 读取 `projectConfig` 和 `localSettings`
2. 合并 `enabledMcpjsonServers` 和 `disabledMcpjsonServers`（避免重复）
3. 写入 `localSettings`
4. 从 `projectConfig` 中移除已迁移的字段

**文件**: `migrations/migrateEnableAllProjectMcpServersToSettings.ts`

---

## 模型别名迁移

### migrateFennecToOpus

**用途**: 将已废弃的 Fennec 模型别名迁移到新的 Opus 4.6 别名。

**触发条件**: `process.env.USER_TYPE === 'ant'`（第一方用户）

**迁移映射**:

| 旧模型字符串 | 新模型字符串 | 说明 |
|-------------|-------------|------|
| `fennec-latest` | `opus` | Fennec latest → Opus latest |
| `fennec-latest[1m]` | `opus[1m]` | Fennec 1M → Opus 1M |
| `fennec-fast-latest` | `opus[1m]` + `fastMode: true` | Fennec fast → Opus 1M fast |
| `opus-4-5-fast` | `opus[1m]` + `fastMode: true` | Opus 4.5 fast → Opus 1M fast |

**注意**: 仅操作 `userSettings`，不触及项目级/本地级/策略级设置，避免静默提升为全局默认。

**文件**: `migrations/migrateFennecToOpus.ts`

---

### migrateLegacyOpusToCurrent

**用途**: 将第一方用户从显式的 Opus 4.0/4.1 模型字符串迁移到 `opus` 别名。

**触发条件**:
- `getAPIProvider() === 'firstParty'`
- `isLegacyModelRemapEnabled()` 返回 true
- `userSettings.model` 为以下之一:
  - `claude-opus-4-20250514`
  - `claude-opus-4-1-20250805`
  - `claude-opus-4-0`
  - `claude-opus-4-1`

**迁移逻辑**:
1. 将 `userSettings.model` 设为 `'opus'`
2. 在 `globalConfig` 中设置 `legacyOpusMigrationTimestamp: Date.now()`（用于 REPL 一次性通知）

**文件**: `migrations/migrateLegacyOpusToCurrent.ts`

---

### migrateOpusToOpus1m

**用途**: 将符合条件的用户在 settings 中固定的 `opus` 迁移到 `opus[1m]`。

**触发条件**:
- `isOpus1mMergeEnabled()` 返回 true（Max/Team Premium 用户）
- `userSettings.model === 'opus'`

**迁移逻辑**:
1. 比较 `opus[1m]` 解析结果与默认主循环模型
2. 如果相同则清除 `model` 字段（使用全局默认），否则写入 `opus[1m]`

**注意**: CLI 运行时 flag `--model opus` 不受影响（它是运行时覆盖，不写入 userSettings）。

**文件**: `migrations/migrateOpusToOpus1m.ts`

---

### migrateSonnet1mToSonnet45

**用途**: 将使用 `sonnet[1m]` 的用户迁移到显式的 `sonnet-4-5-20250929[1m]`。

**触发条件**:
- `globalConfig.sonnet1m45MigrationComplete` 未设置
- `userSettings.model === 'sonnet[1m]'`

**迁移逻辑**:
1. 将 `userSettings.model` 设为 `'sonnet-4-5-20250929[1m]'`
2. 如果内存中的 `mainLoopModelOverride === 'sonnet[1m]'`，同步更新
3. 设置 `sonnet1m45MigrationComplete: true` 完成标记

**背景**: Sonnet 4.6 1M 与 Sonnet 4.5 1M 的目标用户群不同，需要将已有 `sonnet[1m]` 用户固定到 Sonnet 4.5 1M 以保留其原有体验。

**文件**: `migrations/migrateSonnet1mToSonnet45.ts`

---

### migrateSonnet45ToSonnet46

**用途**: 将 Pro/Max/Team Premium 第一方用户从显式 Sonnet 4.5 字符串迁移到 `sonnet` 别名。

**触发条件**:
- 第一方用户
- Pro / Max / Team Premium 订阅
- `userSettings.model` 为以下之一:
  - `claude-sonnet-4-5-20250929` / `claude-sonnet-4-5-20250929[1m]`
  - `sonnet-4-5-20250929` / `sonnet-4-5-20250929[1m]`

**迁移映射**:

| 旧模型字符串 | 新模型字符串 |
|-------------|-------------|
| `claude-sonnet-4-5-20250929` | `sonnet` |
| `claude-sonnet-4-5-20250929[1m]` | `sonnet[1m]` |
| `sonnet-4-5-20250929` | `sonnet` |
| `sonnet-4-5-20250929[1m]` | `sonnet[1m]` |

**注意**: 仅操作 `userSettings`（非合并设置），避免将项目级 pin 静默提升为全局默认。新用户（`numStartups === 1`）不显示迁移通知。

**文件**: `migrations/migrateSonnet45ToSonnet46.ts`

---

### resetProToOpusDefault

**用途**: 在 Pro 用户中执行 Opus 4.5 默认模型迁移。

**触发条件**: `globalConfig.opusProMigrationComplete` 未设置

**迁移逻辑**:
1. 非第一方用户或非 Pro 订阅：标记完成并跳过
2. Pro 用户 + 无自定义模型（`settings.model === undefined`）：设置 `opusProMigrationTimestamp` 以触发 REPL 通知
3. Pro 用户 + 有自定义模型：仅标记完成，不通知

**文件**: `migrations/resetProToOpusDefault.ts`

---

## Auto Mode 迁移

### resetAutoModeOptInForDefaultOffer

**用途**: 清除符合条件的用户的 `skipAutoPermissionPrompt`，重新展示带有"设为默认模式"选项的对话框。

**触发条件**:
- `TRANSCRIPT_CLASSIFIER` 特性已启用
- `globalConfig.hasResetAutoModeOptInForDefaultOffer` 未设置
- `getAutoModeEnabledState() === 'enabled'`
- `userSettings.skipAutoPermissionPrompt === true`
- `userSettings.permissions.defaultMode !== 'auto'`

**迁移逻辑**:
1. 将 `userSettings.skipAutoPermissionPrompt` 设为 `undefined`
2. 设置 `hasResetAutoModeOptInForDefaultOffer: true` 完成标记

**背景**: 针对约 40 个第一方用户（通过 Shift+Tab 到达旧对话框），清除跳过标记以重新展示新的默认模式选项。

**文件**: `migrations/resetAutoModeOptInForDefaultOffer.ts`

---

## 迁移模块索引

| 文件 | 迁移方向 | 触发条件 |
|------|----------|----------|
| `migrateAutoUpdatesToSettings.ts` | `globalConfig` → `userSettings.env` | `autoUpdates === false`（非保护） |
| `migrateBypassPermissionsAcceptedToSettings.ts` | `globalConfig` → `userSettings` | `bypassPermissionsModeAccepted` 存在 |
| `migrateEnableAllProjectMcpServersToSettings.ts` | `projectConfig` → `localSettings` | MCP 服务器审批字段存在 |
| `migrateFennecToOpus.ts` | 模型别名 | `USER_TYPE === 'ant'` 用户（别名转换在函数内部处理） |
| `migrateLegacyOpusToCurrent.ts` | 模型别名 | 第一方 + Opus 4.0/4.1 显式字符串 |
| `migrateOpusToOpus1m.ts` | 模型别名 | Opus 1M 合并启用 + `model === 'opus'` |
| `migrateReplBridgeEnabledToRemoteControlAtStartup.ts` | `globalConfig` 键重命名 | `replBridgeEnabled` 存在 |
| `utils/releaseNotes.ts:migrateChangelogFromConfig` | 状态迁移 | changelog 迁移（异步，fire-and-forget） |
| `migrateSonnet1mToSonnet45.ts` | 模型别名 | `sonnet[1m]` 用户（需 sonnet1m45MigrationComplete 未设置） |
| `migrateSonnet45ToSonnet46.ts` | 模型别名 | Pro/Max/Team + Sonnet 4.5 显式字符串 |
| `resetAutoModeOptInForDefaultOffer.ts` | 状态重置 | `TRANSCRIPT_CLASSIFIER` + 符合条件的用户 |
| `resetProToOpusDefault.ts` | 默认模型 | Pro 用户 + 迁移未完成 |
