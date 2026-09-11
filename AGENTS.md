# Campus Dashboard agent instructions

This repository uses a main-thread/stage-thread workflow. These are stable rules that apply to every task; stage-specific details belong in `.agent/stages/stage-XX.md`.

## Lightweight startup

At the beginning of a new task, read only, in order:

1. `AGENTS.md`;
2. `.agent/CURRENT.md`;
3. the assigned `.agent/stages/stage-XX.md`;
4. the single most recent directly related handoff named by `CURRENT.md` or the stage file.

If resuming a `PARTIAL` or `PAUSED` stage, its own handoff is the directly related handoff. Do not default to reading every historical handoff, the full `docs/project-spec.md`, the full `.agent/STAGE_PROMPTS.md`, or all central planning files. If a required startup file is missing, stop and report it rather than inventing a contract.

Read older or larger material only when a concrete information gap exists. First locate the relevant heading, keyword, or line with `rg -n`; then use `sed -n` for the smallest necessary range. Do not reread an unchanged file already read in the same task.

## Stable safety and product boundaries

- Canvas and SIweb/school-site access is authorized and read-only. Never submit forms, change school data, bypass login, CAPTCHA, MFA, access controls, tenant policy, or school rules.
- Credentials, API keys, cookies, access/refresh tokens, and allowed session secrets belong only in macOS Keychain. Never request them in chat or place them in source, databases, ordinary configuration, fixtures, logs, screenshots, diagnostics, commands, or handoffs.
- AI operates only on already lawfully obtained minimum necessary content. It cannot log in, browse school systems, write to them, or directly change Calendar/notifications. Official source fields remain authoritative; every text-inferred date requires explicit user confirmation before Calendar or deadline-notification eligibility.
- Apple Calendar work is limited to the app-owned or explicitly selected dedicated Campus Dashboard calendar. Never modify or delete personal, family, shared, subscribed, or unrelated events.
- Outlook integration has been removed from the product and repository. Do not add mailbox authorization, Graph/mail access, scraping, or mail-to-AI transfer without a new explicit user-approved scope.
- Preserve user changes and accepted-stage work. Inspect the worktree before editing; never use destructive Git or filesystem operations without explicit authorization.

## Ownership and stage gates

- The main project conversation owns roadmap/status changes, cross-stage decisions, acceptance, and edits to `AGENTS.md`, `.agent/CURRENT.md`, `.agent/PROJECT_CONSTRAINTS.md`, `.agent/EXECUTION_RULES.md`, `.agent/ROADMAP.md`, `.agent/STATUS.md`, `.agent/STAGE_PROMPTS.md`, `.agent/stages/`, and `docs/project-spec.md`.
- A stage task owns only its assigned implementation scope and `.agent/handoffs/stage-XX.md`. It must not begin future stages, edit central control files, weaken prior criteria, or perform opportunistic refactors.
- A narrow compatibility fix to an earlier component is allowed only when required by the assigned stage and must be documented and regression-tested.
- Only the main conversation may accept a stage and authorize its dependent stage. A `PAUSED` or `LOCKED` stage is not implementable.

## Completion protocol

A stage is complete only after it:

1. runs every automated check required by its stage file;
2. performs available mandatory manual/real-service checks without exposing private data;
3. records changed files, commands, concise results, limitations, and privacy-safe evidence in its handoff;
4. marks the handoff `PASS`, `PARTIAL`, or `BLOCKED`, never `PASS` when a mandatory item was skipped;
5. updates `.agent/CURRENT.md` if and only if it is the main conversation, then recommends continuing the next authorized stage in a new Codex task.

Stage tasks that cannot edit `CURRENT.md` must state the proposed current-context updates in their handoff for the main conversation to apply.

## Context and output discipline

- Use focused reads and focused tests while developing; run the stage's complete required suite only at its final gate.
- Keep verbose command/test output in a temporary log. Return only the summary, failures, and relevant tail; do not print complete successful test listings.
- Never paste full specifications, old handoffs, provider responses, private source content, or repeated history into prompts or handoffs.
- Prefer conclusions in `CURRENT.md` over chains of historical reads. Historical handoffs remain immutable evidence and are read only for a named gap.
- Context efficiency never waives security, privacy, authorization, tests, evidence, or acceptance criteria.
