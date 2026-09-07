# Stage 15 reproducible evaluation

## Frozen sample and method

The held-out sample is `Tests/CampusDashboardTests/Fixtures/Stage15/academic-signals-v1.json`, SHA-256 `157e18c74c986af872ef211cd2d7f89cbfc4f4e5e5c405be5a4605a2fd431478`. It contains 20 synthetic cases: 6 schedule changes, 4 assignment deadlines, 4 exams, and 6 other announcements. No school or user data was used. The test decodes this file at runtime and evaluates one primary label per case. Per-class precision, recall, and F1 use one-vs-rest counts; primary accuracy is correct primary labels divided by 20.

The baseline is a frozen pre-repair output snapshot: the three exact cancellation cases `s01`–`s03` were `other`; all other outputs matched their labels. The post-repair output is produced by `DeterministicAcademicSignalClassifier` during `AcademicSignalTests/frozenFixtureEvaluation()`.

| Class | Baseline P / R / F1 | Post-repair P / R / F1 |
|---|---:|---:|
| Schedule change | 1.000 / 0.500 / 0.667 | 1.000 / 1.000 / 1.000 |
| Assignment deadline | 1.000 / 1.000 / 1.000 | 1.000 / 1.000 / 1.000 |
| Exam time | 1.000 / 1.000 / 1.000 | 1.000 / 1.000 / 1.000 |
| Other | 0.667 / 1.000 / 0.800 | 1.000 / 1.000 / 1.000 |

Primary accuracy improved from 17/20 (85%) to 20/20 (100%). Schedule recall improved from 3/6 to 6/6; exam recall remained 4/4. These synthetic results are regression evidence, not an estimate of real-world accuracy.

## Recovery, correction, and write safety

- Provider-failure presentation recovered to a retained deterministic result and a fixed, privacy-safe action in 8/8 representative failure groups: consent/configuration, Keychain, connectivity/timeout, authorization, balance, rate limit, local budget, and schema/response failure.
- The empty-`other` supervised-correction workflow completed 5/5 asserted phases: create correction, preserve it after restart, replay the course-local rule, undo, and reset. Rules retain local provenance/versioning and are scoped by course plus normalized title trigger; correction history is never added to the external payload.
- The section-safety fixture resolved 1/1 uniquely mapped meeting. The two-section ambiguity fixture produced 0 Calendar outbox writes and rejected confirmation. Repeated analysis/decision/reconciliation regression cases produced 0 observed duplicate Calendar or notification intents.
- Confirmed mapped cancellation preserves the SIweb meeting identity, start, duration, and location; it adds a `[CANCELLED]` marker and exposes both the SIweb event URL and related Canvas announcement URL in the in-app detail. The dedicated Apple Calendar binding remains the original `course_meeting` binding.

## Timed workflow proxy

The automated empty-result correction/restart/personalization/undo/reset workflow was run three warm times using `./scripts/test.sh --filter 'AcademicSignalTests/emptyAnalysisCorrectionAndPersonalization'`. Test-body times were 0.014, 0.012, and 0.012 seconds (median 0.012 seconds); whole-command wall times were 0.37, 0.34, and 0.34 seconds (median 0.34 seconds).

A manual-only comparator would require finding the announcement, interpreting it, recording at least category/course/requirement, optionally entering date/time zone, and separately updating the calendar. A conservative task-analysis estimate is 45–90 seconds for those steps, implying an estimated 44.7–89.7 seconds avoided after a corrected pattern is replayed locally. This is an estimate, not an observed human timing or resume metric. A real user timing must be collected separately during an authorized later evaluation; Stage 15 does not start the seven-day Stage 10 trial.

## Reproduction

```sh
shasum -a 256 Tests/CampusDashboardTests/Fixtures/Stage15/academic-signals-v1.json
./scripts/test.sh --filter AcademicSignalTests
```

Expected: the hash above, 19 focused tests passing, post-repair primary accuracy 20/20, and protected date/section gates passing.
