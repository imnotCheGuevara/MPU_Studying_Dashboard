# Stage execution and context-efficiency rules

These rules apply to the main project conversation and every stage task. They
reduce avoidable context/token usage without weakening acceptance, safety, or
handoff evidence.

## 1. Task and context lifecycle

- Start every new stage in a fresh task. Do not fork accumulated chat history; point it to `AGENTS.md`, `.agent/CURRENT.md`, its `.agent/stages/stage-XX.md`, and one directly related handoff.
- Perform the mandatory AGENTS bootstrap read once at the start of a task. A user message such as `continue` does not require reading unchanged bootstrap files again.
- If a central contract or prerequisite handoff changes, re-read only the changed file and the directly affected per-stage file.
- For a substantial repair after a long or compacted task, prefer a fresh task with a concise defect list. The new task must still perform its own mandatory bootstrap read.
- After a major implementation or verification milestone, keep a compact working summary: decisions, changed paths, failed checks, and remaining acceptance items.

## 2. File and tool-output discipline

- Use `rg` and narrow line ranges for implementation inspection. Do not dump entire large source trees or repeatedly print documents already read.
- Keep verbose command output in a uniquely created temporary directory. On success, report only the command, exit status, test/suite count, and timing when useful. On failure, show the complete relevant failure section and retain enough context to diagnose it.
- Never hide, discard, or summarize away an error that affects acceptance.
- Avoid printing generated build trees, large JSON payloads, all passing test names, or repetitive loop output into the conversation.
- Handoffs record exact commands and concise results; they do not embed full successful logs.

## 3. Verification strategy

- During implementation, run the smallest relevant test target first.
- Run the full required suite once the stage is ready for handoff, plus any specifically required build, signing, security, integration, or manual checks.
- Repeat a full suite only to investigate nondeterminism, prove a repaired flaky regression, or satisfy an explicit acceptance requirement. Record a compact aggregate such as `10/10 PASS`.
- A quiet test run is still a real test run. Preserve its exit status and surface failure details.

## 4. Reasoning and repair policy

- Use medium reasoning effort by default when the task supports model selection. Reserve high reasoning for architecture, security, destructive side effects, race conditions, or difficult root-cause analysis.
- Long input context is the primary cost risk. Avoid tool-call loops that repeatedly carry large unchanged outputs.
- If progress is blocked, state the concrete blocker instead of repeatedly retrying unchanged commands.
- These efficiency rules never authorize skipping the completion protocol or marking a stage PASS without mandatory evidence.

## 5. External-service call and cost discipline

- Use fake transports and synthetic fixtures for normal development and automated tests. Never use live DeepSeek, Canvas, SIweb, or Microsoft Graph calls as an implementation loop.
- A stage may make only the minimum live calls required by its explicit smoke-test acceptance. Repeat a successful live smoke only when a material code/configuration change invalidates it; document why.
- DeepSeek requests require deterministic input-length and output-token caps, bounded retries, single-flight processing, and a durable cache key based on source content hash plus provider/model/prompt/schema versions. Unchanged content must not be billed twice.
- Expose privacy-safe aggregate input/output token and request counts plus a user-configurable per-run/daily budget. Stop and report budget exhaustion; never silently continue paid calls.
- Outlook and other remote connectors must use pagination/delta state, bounded recent windows, minimum selected fields, and Retry-After-aware backoff rather than repeated full scans.
- Never print live response bodies or use verbose network tracing with real accounts. Aggregate status/count/timing evidence is sufficient unless a sanitized error contract is under test.
