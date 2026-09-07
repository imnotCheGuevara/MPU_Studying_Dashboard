# Stage 15R release evaluation protocol

This protocol defines local, aggregate-only measurements for the release candidate. It does not collect source content, credentials, URLs, event titles, course names, notification bodies, or provider payloads. Observed results must never be combined with synthetic test estimates.

## Measurement boundaries

- **Observed seven-day results** come only from normal use of the signed candidate. Until the trial is complete, they are reported as “not yet observed,” never estimated.
- **Synthetic evaluation** uses labeled fixture announcements and fake Calendar/notification services. Its results must be labeled “synthetic” and cannot support a real-world reliability claim.
- Local timing samples record only duration, action category, and timestamp. The user can remove them with Sync history from Settings.
- All ratios report their numerator and denominator. A zero denominator is “not measured,” not 0% or 100%.

## Definitions

| Outcome | Definition |
|---|---|
| Sync success rate | Runs whose persistence state is `committed` divided by all recorded runs. Cancellation and failed persistence are not successes. |
| Sync latency | Mean `finished_at - started_at` among finished runs; also report sample count and median/p95 in trial analysis. |
| AI precision / recall / F1 | Per class (`course_schedule_change`, `assignment_deadline`, `exam_time`, `other`) against a separately labeled fixture set: TP/(TP+FP), TP/(TP+FN), and harmonic mean. Report macro and support-weighted summaries. |
| Critical-event miss rate | Labeled schedule/deadline/exam items incorrectly emitted as `other` or with no actionable signal, divided by all labeled critical items. |
| Correction rate | User corrections divided by reviewed results. Report analysis-level and signal-level corrections separately. |
| Fallback recovery rate | Provider-failed announcements later producing an analyzed or deterministic-only result, divided by provider-failed announcements eligible for retry. |
| Calendar duplicates | Extra active bindings for one `(object_type, object_id)`. Release target: zero. |
| Unsafe Calendar writes | Active bindings outside the revalidated dedicated calendar identity. Release target: zero. |
| Notification duplication | Extra records sharing one stable notification key. Release target: zero. |
| Observed handling time | Mean elapsed time from opening review to confirm, correct, or ignore. Report count; omit distribution claims with fewer than 10 samples. |

## Synthetic pre-release procedure

1. Freeze a privacy-safe fixture manifest with independent ground-truth labels, including ambiguous/no-date, cancellation, makeup/change, deadline, exam, empty `other`, and provider-failure cases.
2. Run the complete automated suite from a clean build. Export only aggregate confusion counts and pass/fail totals.
3. With fake services, verify ambiguous and unconfirmed inference causes zero Calendar writes. Confirmed schedule changes and exams must converge to exactly one app-owned binding after replay.
4. Verify cancellation/update/undo never touches an unrelated calendar or an event without the exact ownership marker.
5. Record synthetic metrics in the stage handoff under a section explicitly named “Synthetic,” separate from observed values.

## Seven-day observed procedure

1. Freeze the signed app hash, Git commit, version, signing identity, and CDHash before day one.
2. Use only the dedicated Campus Dashboard calendar and supported read-only sources. Do not enable Outlook.
3. Daily, record aggregate counts shown in Settings plus whether any permission or source recovery was needed. Do not copy course content into the log.
4. For a labeled quality audit, the user manually assigns ground truth without storing private text in the report; retain only per-class confusion counts.
5. At day seven, report numerator/denominator, sample count, mean latency, per-class precision/recall/F1, critical miss rate, correction/fallback recovery, duplicate/unsafe-write counts, notification duplication, and handling-time summary.
6. Any unresolved permission, credential, provider, or source check remains a limitation. Missing observations are never replaced with fixture results.

## Release thresholds

- Zero unsafe Calendar writes, Calendar duplicates, and notification duplicate keys.
- Zero inferred-date writes before explicit confirmation.
- Exactly one bound-event result under replay for confirmed schedule changes and exams.
- Every supported recovery remains isolated: cached history and unrelated integrations survive.
- AI quality thresholds are not claimed until the fixed labeled set and seven-day observed sample are both reported.
