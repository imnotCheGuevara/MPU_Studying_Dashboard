# Stage 08 handoff

Status: PASS

## 主线程复审缺陷与修复

主线程首次复审发现四项强制缺口：撤销只恢复任务字段而未协调已排队/已创建的 Calendar 事件；撤销未触发通知 desired-state reconciliation；生产输入始终使用空的 known-object context；`normalizedTitle`、`suggestedType` 和整体 provider JSON 缺少完整大小边界。本次 Stage 08 修复全部四项，未开始 Stage 09。

- Calendar 确认和撤销现在写入 durable `calendarReconcile` intent。deduplication key 由任务 ID、parse result ID 和持久审计 transition sequence 确定，不依赖随机 outbox ID。
- outbox 消费时重新读取当前已提交领域状态。官方日期或仍确认的建议日期产生 upsert；没有合格日期则只删除有效 app binding。没有 binding 时 reconcile 幂等完成，不要求 Calendar 权限，也不会永久重试。
- 因为消费时使用当前状态，确认 intent 尚未消费就撤销时，旧 intent 和撤销 intent 都看到撤销后的状态，不会随后创建失效事件。旧版已排队的 learning-task `calendarUpsert` 也经过同一 desired-state 检查。
- 若官方截止时间仍存在，撤销只移除 AI 建议字段，Calendar reconcile 继续 upsert 官方日期，不会误删或改用 AI 日期。
- 重复撤销为无副作用成功；重复 outbox 重放只重用同一 binding/desired state，不产生重复事件或删除。
- `DashboardModel` 在撤销提交后调用既有通知服务的 desired-state reconciliation，旧 inferred deadline keys 被取消。AI 模块仍不调用或导入 UserNotifications。
- 生产输入从同课程、active 且已提交的统一任务与公告构造最多八条 typed known-object summaries，排除当前对象和其他课程。字段仅含稳定本地 ID、对象类型、短标题/类型和日期，并执行与目标输入相同的长度限制、URL/疑似凭证脱敏。
- provider 的 related ID 只能引用本次实际提供的 known-object ID；未知或自行编造的 ID 会使整个输出安全失败并留下 failure 记录。
- 输出 schema/prompt 升至 v2；provider JSON 上限 32 KiB，`normalizedTitle` 上限 240 字符，`suggestedType` 上限 80 字符。超限在 JSON 进入类型解码和持久化前拒绝。

## 主线程并发复验修复

主线程第二次复验发现完整并发测试存在稳定竞态：`DashboardModel.confirmAIResult`、`correctAIResult` 和 `undoAIResult` 在 AI 决定提交后，通过未等待的 `Task` 启动通知 reconciliation。方法可能在通知状态收敛前返回；AI 专项单独运行通常通过，但完整并发套件可立即读到旧 reminder。

- 三个 model 方法全部改为 `async`。AI 确认、更正或撤销提交成功并刷新持久队列后，直接 `await notificationService.reconcileReminders()`，方法只在通知 desired state 已收敛或明确失败后返回。
- SwiftUI 的 Confirm、Correction save 和 Undo 同步按钮闭包通过 `Task` 调用并等待对应 async model 方法；未在 model 内生成脱离调用生命周期的 reconciliation task。
- 回归测试在 `await confirmAIResult`、`await correctAIResult` 和 `await undoAIResult` 返回后立即断言数据库及通知状态，不使用 `Task.yield`、sleep、轮询或延长等待时间。
- 若 AI 决定已提交但通知服务失败，决定和审计记录保持提交；model 显示“decision was saved, but deadline notifications could not be updated”，并说明后续 refresh 会再次 reconciliation。该失败不会回滚决定，也不会报告为完全成功。
- 确认队列现在直接显示 `aiMessage`，因此上述部分成功状态在执行操作的页面可见。
- AI 模块没有新增 UserNotifications import 或调用；Dashboard application orchestration 仍只通过既有 `CampusNotificationService` 边界处理通知。

## 实现范围

- 实现“确定性规则优先”的 Canvas 辅助整理管线。只有已提交的 Canvas task/announcement 原始记录会进入 AI 处理；SIweb 和其他来源不会调用 provider。
- 新增 provider-neutral `AIParsingProvider` 协议和确定性 fake provider。应用默认关闭 AI；用户只能在设置页显式启用本地 fake，且界面明确说明不会联网或把内容发送出 Mac。
- 为未来外部 provider 增加 disclosure、传输字段、保留策略和明确同意门禁。四项不完整时持久层拒绝启用；Stage 08 没有接入任何真实外部模型。
- 构造有界、最小化的 provider 输入，去除 URL 和疑似凭证文本。来源 URL 只保留在本地确认界面，不发送给 provider。
- 对 provider JSON 执行严格结构验证：键集合、字段类型、长度、置信度范围、日期和官方日期回显均受校验。畸形、越界或冲突输出会记录失败并安全退出，不改变正常同步结果。
- 持久化 provider/model/prompt/schema 版本、输入 hash、原始结构化输出、置信度、理由、冲突、变更摘要、相关项目建议和动作建议。相同已提交原始记录与输入不会重复解析。
- 保持 `official_due_at`、`suggested_complete_at` 和 `suggestion_confirmed_at` 分离。任何文本提取日期一律标记为 inferred；官方日期始终优先且不可由 AI 改写。
- 相关项目只作为建议展示；只接受输入中明确提供的同课程已知对象，且不会删除、合并或改变来源记录身份。
- 实现持久化确认队列和历史：确认、更正、拒绝、撤销均在事务中记录审计事件。最终采用值和原始来源上下文可在重启后恢复。
- 保存 AI 应用前的精确领域字段；撤销时恢复原值，而不是猜测默认值。用户已规范化的值和官方值优先于 AI 建议。
- 只有确认或更正后的 inferred date 才会写入 durable Calendar reconcile intent；撤销写入相反的 desired-state reconcile intent。AI 层从不直接调用连接器、EventKit 或通知 API。未确认日期仍会被 Stage 06/07 的 Calendar 与通知边界拒绝。
- 将 AI 后处理挂接在确定性同步提交之后。AI 关闭或 AI 解析失败时，原有同步、日历、通知和本地功能保持可用。
- 新增真实执行 fake provider 的 8 条合成评估集，覆盖分类、日期提取、相关项目、动作和不确定性。

## 修改文件

- `Sources/CampusDashboard/AI/AIModels.swift`
- `Sources/CampusDashboard/AI/AIStructuredOutputValidator.swift`
- `Sources/CampusDashboard/AI/DeterministicAIProvider.swift`
- `Sources/CampusDashboard/AI/AIPersistence.swift`
- `Sources/CampusDashboard/AI/AIParsingCoordinator.swift`
- `Sources/CampusDashboard/AI/AISyntheticEvaluation.swift`
- `Sources/CampusDashboard/App/AppEnvironment.swift`
- `Sources/CampusDashboard/App/CampusDashboardApp.swift`
- `Sources/CampusDashboard/App/DashboardModel.swift`
- `Sources/CampusDashboard/Background/ProductionSyncRunner.swift`
- `Sources/CampusDashboard/Domain/Models.swift`
- `Sources/CampusDashboard/Features/Confirmations/ConfirmationQueueView.swift`
- `Sources/CampusDashboard/Features/Settings/SettingsView.swift`
- `Sources/CampusDashboard/Persistence/DatabaseMigrator.swift`
- `Sources/CampusDashboard/Persistence/SQLiteDatabase.swift`
- `Sources/CampusDashboard/Sync/SyncModels.swift`
- `Sources/CampusDashboard/Sync/OutboxProcessor.swift`
- `Sources/CampusDashboard/Sync/SyncEngine.swift`
- `Tests/CampusDashboardTests/AIParsingTests.swift`
- `Tests/CampusDashboardTests/PersistenceTests.swift`
- `README.md`
- `docs/ai-assisted-parsing.md`
- `docs/data-model.md`
- `.agent/handoffs/stage-08.md`

未修改 `AGENTS.md`、`.agent/PROJECT_CONSTRAINTS.md`、`.agent/ROADMAP.md`、`.agent/STATUS.md`、`.agent/STAGE_PROMPTS.md`、`docs/project-spec.md` 或其他 Stage handoff。仓库进入本任务时所有项目文件已经显示为 untracked；本任务没有执行 reset、checkout 或清理用户文件。

## 验收证据

| Stage 08 验收项 | 结果与证据 |
| --- | --- |
| 官方日期不可变且优先 | PASS：自动测试验证冲突官方日期回显被拒绝；确认、更正和撤销均不改写 `official_due_at`。 |
| 文本提取日期始终为 inferred | PASS：验证器和持久化模型显式保存 `suggestedDateOrigin=inferred`，不以置信度改变来源类型。 |
| Calendar 与截止通知拒绝未确认推断 | PASS：Stage 06/07 既有边界测试随全量回归通过；新增测试同时证明 pending 不产生 Calendar outbox，确认后才产生一个 durable outbox。 |
| 畸形输出安全失败且不阻塞同步 | PASS：严格键集合/类型/范围测试通过；生产 runner 在确定性提交后隔离 AI 错误。 |
| 重复建议不删除或物理合并来源记录 | PASS：自动测试验证相关项目建议只保存引用，来源任务总数和稳定身份不变。 |
| 关闭 AI 时确定性功能可用 | PASS：默认设置为关闭；自动测试验证 provider 调用数为零且确定性同步结果仍存在。 |
| 合成评估和零越权写入 | PASS：8 条 fixture 实际调用 fake provider；classification 1.00、duplicate-suggestion precision 1.00、date-extraction 1.00、uncertainty recall 1.00；unauthorized Calendar writes 0、unauthorized notification writes 0。 |
| 撤销后的 Calendar 最终一致性 | PASS：新增回归覆盖已消费事件后撤销、安全删除、消费前立即撤销、重复撤销/重放、无永久 retry，以及官方日期事件保留。 |
| 撤销后的通知最终一致性 | PASS：通过生产 `DashboardModel` 撤销入口验证旧 inferred deadline notification 被 desired-state reconciliation 取消。 |
| 生产关联上下文 | PASS：捕获真实 `processPendingCanvasRecords` provider 输入，验证同课程、排除自身/其他课程、最多八条、字段长度受限并脱敏。 |
| 输出与关联引用边界 | PASS：未知 related ID、超过 240 字符的标题、超过 80 字符的类型和超过 32 KiB 的 JSON 均安全拒绝，确定性任务不受影响。 |

## 自动测试命令及真实结果

```sh
swift package clean && swift build --jobs 1
# PASS：复审修复后的干净 debug 构建完成，34.40s。

./scripts/test.sh --filter AIParsingTests
# PASS：并发修复后 22 tests / 1 suite，0.070s。

./scripts/test.sh --filter CalendarIntegrationTests
# PASS：14 tests / 1 suite，0.042s。

./scripts/test.sh --filter NotificationBackgroundTests
# PASS：17 tests / 1 suite，0.015s。

./scripts/test.sh --filter PersistenceTests
# PASS：12 tests / 1 suite，0.033s；包含 schema v7 和 v6 -> v7 迁移。

./scripts/test.sh
# PASS：并发修复前单次复跑 133 tests / 10 suites；随后新增失败语义测试后为 134 tests / 10 suites。

for run_index in {1..10}; do
  ./scripts/test.sh
done
# PASS：并发修复后的完整套件连续 10/10 次通过，每次 134 tests / 10 suites。
# 用时依次为 0.404s、0.358s、0.393s、0.404s、0.403s、0.404s、
# 0.395s、0.359s、0.416s、0.411s；未观察到间歇失败。
```

AI 专项测试覆盖：默认关闭、Canvas-only 门禁、已提交原始记录入队、最小输入和脱敏、生产 known-object context、未知 related ID、字段/整体输出大小、畸形结构、官方日期冲突、inferred 日期确认门禁、Calendar 消费前后撤销、官方事件保留、重复撤销/重放、awaited confirm/correct/undo 后的即时通知收敛、通知失败时决定保留与可解释错误、相关项目不合并、确认/更正/拒绝/撤销审计、数据库重启持久化、确定性/用户值优先、精确撤销、幂等解析、外部 provider 同意门禁，以及合成评估指标。

## 构建、签名、配置和扫描

```sh
./scripts/build-app.sh
./scripts/verify-app.sh
codesign --verify --deep --strict "dist/Campus Dashboard.app"
# PASS：并发修复后的增量 release build 10.18s；签名应用成功启动并完成 packaged Keychain smoke。

plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
# PASS：两项配置有效。

! rg -n 'import (EventKit|UserNotifications)|URLSession|api\.openai|anthropic' \
  Sources/CampusDashboard/AI Tests/CampusDashboardTests/AIParsingTests.swift
! rg -n '(sk-[A-Za-z0-9_-]{12,}|Bearer[[:space:]]+[A-Za-z0-9._-]{12,})' \
  Sources Tests docs README.md
! rg -n '[[:blank:]]+$' <Stage-08 changed paths>
git diff --check
# PASS：AI 边界越权引用、疑似凭证、敏感日志、尾随空白和 tracked diff 最终扫描均为 clean。
```

由于进入任务时工作树全部为 untracked，tracked diff 不能反映 Stage 08 范围；因此对明确的 Stage 08 路径执行了扫描，并在 handoff 中逐项列出修改文件。

## 真实 Mac 手动验收

使用最终 `dist/Campus Dashboard.app` 在本机完成界面检查：

- PASS：侧栏显示 `Stage 08 · Controlled AI confirmation`，可进入 AI Confirmation Queue。
- PASS：默认状态明确显示 AI 关闭、官方值优先、队列为空，同时原有确定性功能可用。
- PASS：设置页显示 `AI-assisted organization` 默认关闭，并明确本地 deterministic fixture、无网络、无内容离开 Mac。
- PASS：外部 provider 的 disclosure、传输字段、保留策略和 consent 在当前版本不可用，界面没有暗示已连接真实模型。
- PASS：显式打开后显示 `Deterministic fake provider enabled. No content leaves this Mac.`；随后关闭并复验持久状态恢复为 off。
- PASS：确认队列页面可显示来源、置信度/理由/冲突、原始上下文、相关项目/动作，以及确认、更正、拒绝、历史与撤销入口；空数据库时正确显示空态。

所有手动检查均使用本地应用和合成/空数据；没有向外部服务发送内容，也没有执行真实 Calendar 或通知写入。

## 数据库迁移

- schema 从 v6 升至 v7。
- 扩展 `ai_parse_results`，保存目标身份、相关/动作建议、日期来源、变更摘要、结构输出、失败信息、采用值、来源摘要/URL和更新时间。
- 更新 `ai_settings` 的安全默认值和外部 provider disclosure/consent 字段。
- 新增 `ai_confirmation_audit` 和 `ai_applied_values`，分别保存追加式审计记录与撤销所需精确前态。
- fresh v7、旧表兼容和 v6 -> v7 自动迁移均通过持久化测试。

## 对早期组件的必要兼容修复

- `ProductionSyncRunner` 在 Stage 05 确定性提交成功后调用 Stage 08 coordinator；该调用为可失败后处理，不能回滚或覆盖来源同步结果。
- `RawSyncRecord` 和 `SourceKind` 增加 `Codable`，用于安全持久化已提交原始记录和解析上下文；没有改变来源身份或同步语义。
- `AppEnvironment`、`CampusDashboardApp` 和 `DashboardModel` 注入 Stage 08 服务与 UI 状态；既有 Calendar/通知服务仍保留自身确认门禁。
- `PersistenceTests` 只更新当前 schema 预期并增加 v7 迁移覆盖。

## 已知限制和风险

- deterministic fake 只用于离线测试和演示，合成评估中的日期、相关项目和动作使用明确 marker；这些满分指标不代表真实自然语言模型质量。
- Stage 08 没有配置或调用真实外部 provider，因此没有外部服务 smoke，也不声称 provider 可用。未来接入仍必须满足 disclosure、字段说明、保留策略和 consent 门禁。
- 当前 Canvas task 同步边界提供标题、类型和日期，announcement 提供已清理摘要；AI 只能使用已合法同步且最小化后的字段，不能补取额外来源内容。
- 确认或撤销 inferred date 会写入 durable Calendar desired-state reconcile，由既有 outbox 消费流程处理；AI 本身不会直接调用 EventKit。撤销后的通知重算仍由既有已授权通知边界执行。
- 未实现或扩展 Phase 2 学习规划功能。

## Handoff 结论

Stage 08 的实现、迁移、专项测试、完整回归、签名构建、安全扫描和真实 Mac 界面验收均完成并通过。handoff 标记为 `PASS`，等待主项目对话检查与接受；在主项目正式接受前不应开始依赖 Stage 08 的 Stage 09。
