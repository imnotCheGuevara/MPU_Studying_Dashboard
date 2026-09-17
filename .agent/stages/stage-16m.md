# Stage 16M — Manual events on macOS

Status: ACTIVE — authorized by the user's 2026-09-15 request to add manual events.

Scope: macOS Schedule creation, editing and deletion; title, start/end, all-day and location; independent durable local persistence; Today and Schedule presentation; Chinese/English copy. Manual events stay inside Dashboard. No external Calendar, source-system, AI or notification action is introduced. Preserve the five pre-existing SIweb/sync modifications and the accepted app bundle. Windows Stage 16W remains independent.

Required verification: full scripts/test.sh; scripts/build-app.sh into a separate candidate directory; scripts/verify-app.sh against that candidate; strict codesign and git diff --check. Automated evidence must cover validation, update/reopen/delete persistence, day boundaries, source filters, absence of Calendar outbox work and privacy cleanup. Verify creation and editing through the synthetic app UI. Record evidence and limitations in .agent/handoffs/stage-16m.md. Do not accept or publish the Windows stage as part of this work.
