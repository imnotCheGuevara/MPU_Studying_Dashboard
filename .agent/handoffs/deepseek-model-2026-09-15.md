# DeepSeek model compatibility repair — 2026-09-15

Status: PARTIAL — implementation and signed delivery verified; live provider retry awaits renewed user consent in the app.

User authorized repairing the model mismatch after the official September 10 model migration. Official reference: https://api-docs.deepseek.com/news/news260910/ and https://api-docs.deepseek.com/api/create-chat-completion/ .

Changes: DeepSeekDisclosure requests deepseek-flash instead of retired deepseek-v4-flash. Exact response model checking remains in place. Existing model-bound consent becomes stale; the Keychain credential is retained. AcademicSignalModels normalizes legacy camelCase failure codes and displays a specific model mismatch recovery message. DashboardModel prevents duplicate concurrent reprocessing per announcement; AnnouncementsView and ConfirmationQueueView show Processing and disable the button until completion. Localization supplies Chinese copy. DeepSeekProviderTests and AcademicSignalTests cover migration, current response acceptance, rejection before renewed consent, credential retention and legacy error presentation. Existing unrelated worktree changes preserved.

Validation: ./scripts/test.sh — 250 tests / 21 suites PASS. ./scripts/build-app.sh dist/deepseek-fix — Release PASS. ./scripts/verify-app.sh with absolute candidate path — signed app and Keychain smoke PASS. codesign --verify --deep --strict for candidate and delivered app PASS. git diff --check PASS. Logs: /tmp/campus-deepseek-fix-{tests,build,verify}.log.

Delivery: previous dist bundle moved to dist/backups/2026-09-15-before-deepseek-fix/Campus Dashboard.app; verified candidate copied to dist/Campus Dashboard.app and launched. Live UI confirms deepseek-flash, AI off pending consent, and key stored in Keychain. Prior modelMismatch now appears explicitly in recovery UI. Restored Chinese interface. UI transient Processing state has not been manually exercised against a real request. No live AI retry, consent grant, Calendar write, secret output, database cleanup or GitHub publication performed. Local fallback keyword gaps and invalid_schedule_target errors remain outside this model repair.
