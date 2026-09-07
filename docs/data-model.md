# Campus Dashboard local data model

Schema version: **7**

SQLite stores UTC-comparable timestamps as seconds from the Unix epoch and retains original time-zone/all-day metadata in dedicated columns. IDs are text UUIDs internally. Source identity is always the composite `(source_account_id, source_object_id)`; a title is never an identity.

| Table | Purpose and identity |
| --- | --- |
| `source_accounts` | Source instance and authorization state; unique source kind + instance URL. No credential value. |
| `raw_source_records` | Minimal opaque source snapshot, batch, hash, and fetch time; composite source/object/hash uniqueness. |
| `courses` | Unified course; unique source account + source object. |
| `course_meetings` | Unified meeting; unique course + source object, with explicit all-day/time-zone/cancellation state. |
| `learning_tasks` | Unified task; unique source account + source object. Official due fields are separate from suggested date, origin, and confirmation. |
| `announcements` | Unified announcement; unique source account + source object and content hash. |
| `local_user_states` | Local completion/read/hidden/priority keyed by local object type + ID, never mixed with source state. |
| `sync_runs` | Per-source pipeline states, counts, timing, and redacted failure category/summary. |
| `change_records` | Auditable important field changes with summarized old/new values. |
| `calendar_bindings` | Per-object owned event binding, calendar/source identity, ownership marker, and verification state. |
| `notification_deliveries` | Globally unique notification key and delivery state. |
| `ai_parse_results` | Input hash, provider/model/schema/prompt trace, official-date echo, inferred suggestion, confidence, rationale, conflict and confirmation state. |
| `ai_settings` | Disabled-by-default provider selection plus external-provider disclosure, transmitted fields, retention policy, and consent timestamp. |
| `ai_confirmation_audit` | Append-only confirm, correct, reject, and undo decisions with state transitions and corrected values. |
| `ai_applied_values` | Exact pre-confirmation local task values used to restore deterministic/user state on undo. |
| `outbox_work` | Durable, uniquely deduplicated post-transaction side-effect work with retry state and availability time. |

The database intentionally has no password, token, cookie, refresh token, session secret, or authorization-header column. Such values belong exclusively to `SecretStore`/macOS Keychain.

Repository upserts use database uniqueness constraints, so a changed title or date updates the existing source object while retaining its original local UUID and first-seen timestamp. Local state has a separate repository facade used by the Stage 02 app. Durable outbox insertion uses a unique deduplication key; enqueuing the same work twice returns the original record rather than creating another side effect.
