# Stage roadmap

The main project conversation owns this roadmap and accepts each stage. Stage conversations implement one stage only.

## Stage sequence

| Stage | Name | Depends on | Primary acceptance result |
| --- | --- | --- | --- |
| 01 | App foundation and fake-data UI | Project specification | A buildable macOS app shows all primary screens using synthetic data |
| 02 | Persistence, Keychain, and service contracts | 01 | Data survives restart; secrets use Keychain; external systems have testable interfaces |
| 03 | Canvas API connector | 02 | Courses, assignments/quiz-like items, and announcements sync read-only without duplicates |
| 04 | SIweb read-only crawler | 02 | Course meetings and locations parse from authorized pages with structural-change detection |
| 05 | Sync engine and deterministic normalization | 03, 04 | Independent sources, transactions, outbox, idempotency, retries, and deletion evidence work |
| 06 | Apple Calendar integration | 05 | Only bound events in the dedicated calendar are created, updated, and safely removed |
| 07 | Notifications and background scheduling | 05 | Deduplicated reminders, quiet hours, hourly target scheduling, and recovery sync work |
| 08 | AI parsing and confirmation queue | 05, 06, 07 | Controlled AI suggestions work; inferred dates cannot bypass confirmation |
| 09 | Integration hardening, privacy, and diagnostics | 06, 07, 08 | End-to-end flows, permission denial, clearing, redaction, and diagnostics pass |
| 10R | Pre-trial UI and Simplified Chinese repair | 09; Stage 10 field feedback | Weekly timetable, spatial day/week/month schedule, unread-announcement sidebar, and complete Simplified Chinese system UI pass |
| 10 | Final real-device acceptance and seven-day trial | 10R, 15R | The frozen no-Outlook release candidate passes Mac/iPhone, source, AI, notification, and seven-day operational acceptance |
| 11 | DeepSeek provider, consent, and security gate | 09, 10R; Stage 10 paused by user | External AI is opt-in, Keychain-backed, schema-validated, minimal, auditable, and proven with a synthetic live smoke |
| 12 | Canvas announcement academic-signal classification | 11 | Announcements yield explainable schedule-change, assignment-deadline, exam-time, or other signals without bypassing date confirmation |
| 13 | Outlook tenant feasibility and delegated authorization (deferred) | Future main-thread authorization | Preserved pending school IT policy; not part of the active Stage 10 release path |
| 14 | Outlook read-only mail sync and local mailbox UI (deferred) | Accepted 13 and future authorization | Preserved for a later Outlook release path |
| 15 | Final integration, AI field repair, and release candidate | 12; Outlook deferred | Correctable local feedback improves announcement classification; confirmed schedule/exam signals reconcile safely; measurable no-Outlook integration passes and a signed build is frozen for Stage 10 |
| 15R | Release usability closure | 15 partial | All setup is available in-app; failures are recoverable; AI review and Calendar actions are explicit; the release is reproducible and instrumented for honest seven-day metrics |
| 15S | Schedule-change targeting safety repair | 15R partial; real acceptance defect | Multi-section cancellation dates are section-aware, uniquely bound to SIweb meetings, never shown or written as standalone confirmed changes when unresolved, and always require explicit confirmation |

## Parallelism policy

- Stages 03 and 04 may run in parallel after Stage 02 is accepted because they own separate connectors, but only when each task uses an isolated Git worktree. In the same checkout, run them sequentially to avoid shared-file races.
- Stages 06 and 07 may run in parallel after Stage 05 is accepted, but only in isolated Git worktrees. In the same checkout, run them sequentially.
- All other dependency edges are sequential.
- The DeepSeek track ended with accepted Stage 12. The Outlook track (Stages 13–14) is explicitly deferred pending school IT guidance and is not on the current critical path.
- Stage 15S is the active release-blocking repair discovered during the Stage 15R real walkthrough. Stage 15R cannot pass until Stage 15S passes and the corrected real schedule-change/Calendar lifecycle is revalidated. Only then may the main conversation freeze a reproducible no-Outlook candidate and resume Stage 10 at 0/7.
- Historical Stage 10R gate remains satisfied. Outlook work performed offline during partial Stage 13 earns no acceptance credit and must remain dormant during the trial.
- Parallel stages must not edit the same central planning files. Each writes only its own handoff.

## Execution-efficiency policy

- Every stage follows `.agent/EXECUTION_RULES.md`.
- Each new stage starts in a fresh task and reads only `AGENTS.md`, `.agent/CURRENT.md`, its `.agent/stages/stage-XX.md`, and the latest directly related handoff at bootstrap.
- Focused tests are preferred during development; the complete required suite and all stage-specific checks remain mandatory before handoff.
- Large successful logs stay outside the conversation. Handoffs preserve exact commands and concise, auditable outcomes.
- Large repair rounds should use a fresh task with a bounded defect prompt instead of extending an already oversized context.

## Main-conversation acceptance checklist

For every returned stage:

1. Read its `.agent/handoffs/stage-XX.md`.
2. Inspect the actual diff and repository status.
3. Re-run high-risk or failed checks when appropriate.
4. Confirm every mandatory acceptance item is evidenced.
5. Record the acceptance decision in the main conversation.
6. Only then send the next stage prompt.

`PARTIAL` and `BLOCKED` stages are not accepted. The main conversation decides whether to send a repair prompt to the same stage task or revise the roadmap with the user.
