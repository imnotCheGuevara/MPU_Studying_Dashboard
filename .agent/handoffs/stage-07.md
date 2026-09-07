# Stage 07 handoff

Status: PASS

## 实现范围

- 实现 `UserNotifications` 生产适配器。权限只由设置页的明确用户操作或显式本地 smoke 命令申请；普通启动、同步和 outbox 消费不会弹出权限请求。
- 实现通知权限 `not_determined`、`authorized`、`denied` 与撤销后的状态刷新。拒绝/撤销会停止并取消应用已追踪的待发送提醒，但不修改来源数据、日历绑定或本地界面状态。
- 新增持久化通知策略：总开关、课程级开关、可编辑的截止提前分钟列表（默认 1440/180/60）、可选上课提前分钟（默认 15）、夜间静默开始/结束和策略版本。
- 为新作业、新测验、新公告、截止提醒、上课提醒、来源连续失败和恢复生成确定性通知 key。key 由对象类型、稳定领域对象 ID、通知类型、目标时间/规则槽和策略版本组成；没有使用随机 UUID 作为通知去重身份。
- Stage 05 durable notification outbox 由 `CampusNotificationService` 幂等消费。系统通知 identifier 与持久 `notification_key` 相同；系统写成功但数据库提交前崩溃时，重放同一 identifier 会替换同一待发送请求，不产生副本。
- 新项目通知只读取已提交 outbox 和统一领域表。作业/测验分类从统一任务类型读取；公告从统一公告表读取；没有读取 Canvas/SIweb DTO。
- 提醒重算只读取统一领域表。截止提醒优先使用 `official_due_at`；仅当 `suggestion_confirmed_at` 存在时才允许使用 `suggested_complete_at`。未确认 AI 推断日期不能安排通知，三个日期/确认字段未合并。
- 同步后和应用启动时重算未来提醒。截止或课程时间变化会取消旧 key 并安排新 key；来源取消、课程开关关闭、总开关关闭、过期或不再满足条件的提醒会被取消。
- 静默期内的普通通知延后到当前日或次日的静默结束。截止/上课提醒若延后后达到或超过目标时间则丢弃；过期 nominal fire date 不补发。计算使用注入的 `Calendar`，覆盖时区与 DST。
- 新增按来源持久化的失败周期。一个连续失败周期只安排一次失败通知；一次恢复只安排一次恢复通知；新的失败周期会使用递增、持久的确定性 cycle 槽重新允许一次通知。系统安排失败不会提前把该周期误记为已通知。
- 新增用户可见、可关闭的 `SMAppService.mainApp` 登录项，设置页显示 `enabled`、`requires_approval`、`disabled` 或 `unavailable`，并提供 macOS Login Items 设置入口。
- 新增持久化后台调度状态，生产默认目标间隔 3600 秒；开发 smoke 可注入短间隔但不会改变生产默认。应用进程可运行时以 30 秒检查粒度追踪目标间隔。
- 新增应用启动、`NSWorkspace.didWakeNotification` 和 `NWPathMonitor` 离线恢复补偿入口。失败/离线运行不推进成功完成时间，因此网络恢复仍保持 overdue 并立即补偿；重复恢复信号在目标间隔内不会重复运行。
- 后台运行调用既有 Canvas/SIweb 只读连接器、Stage 05 确定性同步引擎、Stage 05 durable outbox、Stage 06 日历服务和本 Stage 通知服务。来源仍独立；没有新增来源写操作。
- 设置页显示通知权限、主/课程开关、提前量、静默时间、测试通知、后台开关、后台项目状态、目标间隔限制和错误/修复说明。

## 修改文件

- `Package.swift`
- `Resources/Info.plist`
- `Sources/CampusDashboard/App/AppEnvironment.swift`
- `Sources/CampusDashboard/App/CampusDashboardApp.swift`
- `Sources/CampusDashboard/App/DashboardModel.swift`
- `Sources/CampusDashboard/Features/Settings/SettingsView.swift`
- `Sources/CampusDashboard/Persistence/DatabaseMigrator.swift`
- `Sources/CampusDashboard/Persistence/SQLiteDatabase.swift`
- `Sources/CampusDashboard/Background/BackgroundModels.swift`
- `Sources/CampusDashboard/Background/BackgroundPersistence.swift`
- `Sources/CampusDashboard/Background/BackgroundItemController.swift`
- `Sources/CampusDashboard/Background/BackgroundSyncScheduler.swift`
- `Sources/CampusDashboard/Background/ProductionSyncRunner.swift`
- `Sources/CampusDashboard/Background/RuntimeRecoveryMonitor.swift`
- `Sources/CampusDashboard/Notifications/NotificationModels.swift`
- `Sources/CampusDashboard/Notifications/NotificationPersistence.swift`
- `Sources/CampusDashboard/Notifications/UserNotificationCenterAdapter.swift`
- `Sources/CampusDashboard/Notifications/CampusNotificationService.swift`
- `Sources/CampusDashboard/Notifications/Stage07LocalTool.swift`
- `Tests/CampusDashboardTests/NotificationBackgroundTests.swift`
- `Tests/CampusDashboardTests/PersistenceTests.swift`
- `.agent/handoffs/stage-07.md`

未修改 `AGENTS.md`、`.agent/PROJECT_CONSTRAINTS.md`、`.agent/ROADMAP.md`、`.agent/STATUS.md`、`.agent/STAGE_PROMPTS.md`、`docs/project-spec.md` 或其他 Stage handoff。仓库进入本任务时所有项目文件已经显示为 untracked；本任务未执行 reset、checkout 或清理用户文件。

## 设计与安全边界

- 通知内容和调度时间只来自统一领域表或已提交 durable outbox；连接器响应对象不会进入通知层。
- `official_due_at`、`suggested_complete_at`、`suggestion_confirmed_at` 保持独立。没有实现 AI 解析；确认门禁仅消费既有字段。
- 通知和后台状态只写本地 SQLite/UserNotifications/Service Management，不写回 Canvas 或 SIweb。
- 通知 master/course/policy 变更会提高策略版本并进行 desired-state reconciliation；旧提醒被明确取消，新提醒使用不同稳定 key。
- 所有后台行为在设置页可见、可关闭。`SMAppService.mainApp` 仅使应用成为用户可管理的登录项；实际周期任务由可运行的应用进程执行。
- “60 分钟”仅为用户已登录且 Mac/应用可运行时的目标间隔。没有实现或声称 Mac 睡眠、关机或无用户登录时执行。
- 权限拒绝、权限撤销、后台项目禁用和来源未配置均不会阻止本地 UI、持久化或日历功能。
- 本地 smoke 只使用合成标题/正文与独立 smoke 数据库；handoff 未记录通知正文、真实课程、来源 ID、系统通知 ID 或个人标识。

## 自动测试命令及真实结果

```sh
swift package clean && swift build --jobs 1
# PASS: 干净 debug 构建完成，34.34s。

./scripts/test.sh --filter PersistenceTests
# PASS: 11 tests / 1 suite；包含 fresh v6、v1/v2/v3/v4 -> v6 和保守默认值迁移。

./scripts/test.sh --filter NotificationBackgroundTests
# PASS: 17 tests / 1 suite。

./scripts/test.sh
# PASS: 111 tests / 9 suites；Stage 01–06 全部既有套件无回归。
```

Stage 07 自动测试覆盖：

1. 权限未决定、允许、拒绝、撤销和撤销后取消待发送提醒。
2. 拒绝权限时本地任务状态与同步 fake 仍可用。
3. 稳定 key 及对象/类型/槽/策略版本唯一性。
4. 同一 outbox 重放和重复命令只保留一个系统 identifier/投递记录。
5. Stage 05 既有测试继续证明重复同步不重复产生通知 outbox。
6. 截止时间变化取消旧提醒并安排新提醒。
7. 来源取消取消相应提醒。
8. 课程时间变化重新安排上课提醒。
9. 总开关和课程级开关。
10. 静默时间内安全延后。
11. 延后后失效的截止提醒丢弃。
12. 过期提醒过滤。
13. Stage 05 既有首次同步基线测试继续证明历史项目不产生“新增”通知。
14. Stage 05 既有基线后新增测试和 Stage 07 消费测试共同证明只通知一次。
15. 连续失败周期只通知一次。
16. 恢复只通知一次并允许下一失败周期重新通知。
17. 未确认推断日期门禁；确认后才允许提醒。
18. Asia/Macau 时区边界。
19. America/New_York 2026 DST 前进/回退边界。
20. 后台启用/关闭及关闭后不主动执行。
21. 启动、唤醒和网络恢复补偿；离线失败不推进成功完成时间。
22. 数据库/服务重建后通知去重、失败周期和调度状态仍有效。
23. 2 秒开发间隔注入与 3600 秒生产默认分离。

## 构建、签名、配置和扫描

```sh
./scripts/build-app.sh
./scripts/verify-app.sh
codesign --verify --deep --strict "dist/Campus Dashboard.app"
# PASS: release build 37.04s；ad-hoc 签名 app 启动并完成 packaged Keychain smoke。

plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
codesign -d --entitlements - "dist/Campus Dashboard.app"
# PASS: plist/entitlements 有效；签名应用保留 app sandbox、network client、Calendar 权限。
# UserNotifications 本地通知和 SMAppService.mainApp 不需要新增 sandbox entitlement。

git diff --check
# PASS。

! rg -n '<credential-patterns>' --hidden --glob '!.git/**' --glob '!.build/**' --glob '!dist/**' .
! rg -n '[[:blank:]]+$' <Stage-07 changed source/test/resource paths>
! rg -n 'OpenAI|Anthropic|AIParse|AI parsing|iPhone.*PASS|seven.day|7.day' \
  Sources/CampusDashboard/Notifications Sources/CampusDashboard/Background \
  Tests/CampusDashboardTests/NotificationBackgroundTests.swift
! rg -n 'httpMethod.*(POST|PUT|PATCH|DELETE)|uploadTask|dataTask.*from:' \
  Sources/CampusDashboard/Notifications Sources/CampusDashboard/Background
# PASS: 凭证、尾随空白、越界 AI/iPhone/七天试运行及来源写操作扫描均为 clean。
```

`Info.plist` 含 `NSUserNotificationAlertStyle=alert` 和既有 Calendar usage description。后台采用 `SMAppService.mainApp`，无需嵌入 helper plist；生产代码已链接 `UserNotifications`、`ServiceManagement` 和 `Network`。

## 真实 Mac 手动验收步骤及结果

使用最终签名应用和完全合成数据：

```sh
open -n -W "dist/Campus Dashboard.app" --args --background-smoke-test \
  "/Users/yang/Library/Containers/com.campusdashboard.desktop/Data/Library/Application Support/com.campusdashboard.desktop/stage-07-background-result.txt"
# PASS login_item=enabled short_interval=1 disabled_count=1 recovery_count=2 final=disabled
```

- PASS：真实 `SMAppService.mainApp` 登录项从签名应用注册，状态为 `enabled`；测试结束后注销并确认 `disabled`。
- PASS：开发模式短间隔明确触发一次合成调度。
- PASS：禁用后再次 evaluate，执行计数保持不变。
- PASS：重新启用后把上次成功时间改为合成的过期值，发送 wake-recovery 信号，执行一次补偿同步。
- PASS：最终后台项目已关闭，没有在系统中遗留启用的测试登录项。
- 未声称或测试 Mac 睡眠/关机期间执行。

通知 smoke：

```sh
open -n -W "dist/Campus Dashboard.app" --args --notification-smoke-test \
  "/Users/yang/Library/Containers/com.campusdashboard.desktop/Data/Library/Application Support/com.campusdashboard.desktop/stage-07-notification-result.txt"
# 首次 Stage 07 执行：PARTIAL permission=denied initial=denied
```

- PASS：从最终签名应用显式触发权限请求路径；首次执行验证了真实 `denied` 状态。
- PASS：权限拒绝后再次执行 `verify-app.sh`，签名应用仍正常启动并完成独立 Keychain smoke，说明拒绝没有破坏其他应用能力。

主线程随后在真实 Mac 上开启通知权限并使用最终签名应用复验：

```text
PASS permission=authorized pending=1 delivered=1 disabled_blocks=1
```

结果文件：`/Users/yang/Library/Containers/com.campusdashboard.desktop/Data/Library/Application Support/com.campusdashboard.desktop/stage-07-main-review-authorized-1788422390.txt`

- PASS：真实通知权限状态为 `authorized`。
- PASS：合成测试通知成功进入 UserNotifications pending 队列，`pending=1`。
- PASS：短时间合成测试通知成功实际投递，`delivered=1`。
- PASS：关闭通知总开关后不再安排新通知，`disabled_blocks=1`。

## 未完成项和限制

- Stage 07 的强制自动与真实 Mac 手动验收项目均已完成，没有剩余 Stage 07 验收缺口。
- 登录项让应用在用户登录时启动；周期执行仍要求应用进程可运行。macOS 可延迟登录项启动，且睡眠、关机和未登录期间不会严格每小时执行。
- 没有进行 iPhone/iCloud 最终验收、七天试运行、AI 解析或 Stage 08 工作。

## 对早期组件的必要兼容修复

- `Package.swift` 增加 Stage 07 所需系统 framework 链接。
- `AppEnvironment`/`CampusDashboardApp`/`DashboardModel`/`SettingsView` 增加 Stage 07 依赖和设置接点；没有改变 Stage 01–06 的来源、日历或本地状态语义。
- 数据库从 v4 迁移到 v5（通知/后台状态）并到 v6（持久失败周期）。单独保留 v6 是为了让已经在本 Stage 开发过程中打开过 v5 数据库的签名应用也能安全补列；没有猜测或迁移来源内容。
- `PersistenceTests` 仅更新 schema 版本预期并新增 v4 升级测试。
- 未修改 Stage 05 同步引擎或 Stage 06 日历所有权逻辑；Stage 07 通过既有协议和 durable outbox 接入。

## Handoff 结论

Stage 07 的实现、自动测试、完整回归、签名构建、安全扫描、后台真实 Mac 验收，以及通知 `authorized`、pending、实际 delivered 和关闭后阻止安排的主线程复验均已完成并通过。handoff 标记为 `PASS`，等待主线程最终检查与接受；Stage 08 仍须等主线程正式接受 Stage 07 后才能授权。
