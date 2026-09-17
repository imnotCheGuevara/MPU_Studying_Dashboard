import Foundation
import Testing
@testable import CampusDashboard

@Suite("Stage 05 deterministic sync engine")
struct SyncEngineTests {
    @Test("Canvas and SIweb boundary payloads map deterministically without AI")
    func connectorBoundaryMapping() async throws {
        let canvasService = FakeCanvasService(
            coursePage: .init(values: [CanvasCoursePayload(
                sourceObjectID: "course-1", name: "Course", code: "C-1", term: "Term",
                timeZone: "Asia/Macau", sourceURL: URL(string: "https://canvas.invalid/courses/1")
            )], nextPageToken: nil, isCompleteSnapshot: true),
            taskPages: ["course-1": .init(values: [CanvasTaskPayload(
                sourceObjectID: "task-1", courseSourceObjectID: "course-1", title: "Quiz",
                officialType: "new_quiz", officialDueAt: Date(timeIntervalSince1970: 50_000)
            )], nextPageToken: nil, isCompleteSnapshot: true)],
            announcementPages: ["course-1": .init(values: [], nextPageToken: nil, isCompleteSnapshot: true)]
        )
        let canvas = try await CanvasSyncSourceReader(service: canvasService).read()
        #expect(canvas.tasks.first?.normalizedType == "quiz")
        #expect(canvas.tasks.first?.officialDueAt == Date(timeIntervalSince1970: 50_000))
        #expect(canvas.completeObjectTypes == [.course, .learningTask, .announcement])
        #expect(canvas.rawRecords.count == 2)

        let siwebService = FakeSIwebService(page: .init(values: [SIwebMeetingPayload(
            sourceObjectID: "meeting-1", courseSourceObjectID: "si-course-1",
            courseName: "SI Course", courseCode: "SI-1",
            startsAt: Date(timeIntervalSince1970: 60_000), endsAt: Date(timeIntervalSince1970: 63_600),
            timeZoneIdentifier: "Asia/Macau", location: "Room A", isCancelled: false,
            parserVersion: "synthetic-v1", sourceContentHash: "content-hash"
        )], nextPageToken: nil, isCompleteSnapshot: true))
        let siweb = try await SIwebSyncSourceReader(service: siwebService).read()
        #expect(siweb.courses.first?.sourceObjectID == "si-course-1")
        #expect(siweb.meetings.first?.location == "Room A")
        #expect(siweb.completeObjectTypes == [.course, .courseMeeting])
        #expect(siweb.rawRecords.first?.objectType == .courseMeeting)
    }

    @Test("A connector page marked incomplete cannot become deletion evidence")
    func connectorIncompleteSemantics() async throws {
        let service = IncompleteCanvasBoundaryService()
        let snapshot = try await CanvasSyncSourceReader(service: service).read()
        #expect(!snapshot.completeObjectTypes.contains(.course))
        #expect(!snapshot.completeObjectTypes.contains(.learningTask))
        #expect(!snapshot.completeObjectTypes.contains(.announcement))
    }

    @Test("Connector errors map to retry policy and redacted run categories")
    func retryClassification() async throws {
        try await withDatabase { database in
            let reader = ConnectorErrorReader(
                source: .canvas,
                error: CanvasConnectorError(
                    category: .rateLimited, retryable: true, retryAfter: 30,
                    diagnostic: "synthetic private marker"
                )
            )
            let engine = makeEngine(database: database, readers: [reader])
            await #expect(throws: SyncEngineError(category: .rateLimited, retryable: true)) {
                try await engine.synchronize(source: .canvas, trigger: .manual)
            }
            let row = try #require(database.query("SELECT * FROM sync_runs").first)
            #expect(row.string("error_category") == "rate_limited")
            #expect(row.string("redacted_error_summary") == "rate_limited")
            #expect(row.string("redacted_error_summary")?.contains("private") == false)
        }
    }

    @Test("Repeated sync is idempotent and baseline suppresses historical notifications")
    func idempotencyAndBaseline() async throws {
        try await withDatabase { database in
            let clock = MutableTestClock(Date(timeIntervalSince1970: 1_000))
            let reader = MutableSyncReader(source: .canvas, snapshot: canvasSnapshot(taskIDs: ["task-1"]))
            let engine = makeEngine(database: database, readers: [reader], clock: clock)

            let first = try await engine.synchronize(source: .canvas, trigger: .manual)
            let countsAfterFirst = try tableCounts(database)
            #expect(first.insertedCount == 3)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work WHERE kind LIKE 'notification.%'") == 0)

            clock.advance(60)
            let second = try await engine.synchronize(source: .canvas, trigger: .scheduled)
            #expect(second.insertedCount == 0)
            #expect(second.updatedCount == 0)
            #expect(try tableCounts(database) == countsAfterFirst)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 1)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM raw_source_records") == 3)
        }
    }

    @Test("A post-baseline item creates one durable notification intent")
    func postBaselineNotification() async throws {
        try await withDatabase { database in
            let clock = MutableTestClock(Date(timeIntervalSince1970: 2_000))
            let reader = MutableSyncReader(source: .canvas, snapshot: canvasSnapshot(taskIDs: ["task-1"]))
            let engine = makeEngine(database: database, readers: [reader], clock: clock)
            _ = try await engine.synchronize(source: .canvas, trigger: .manual)

            await reader.set(snapshot: canvasSnapshot(taskIDs: ["task-1", "task-2"]))
            clock.advance(60)
            _ = try await engine.synchronize(source: .canvas, trigger: .manual)
            clock.advance(60)
            _ = try await engine.synchronize(source: .canvas, trigger: .manual)

            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 2)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work WHERE kind = 'notification.schedule'") == 1)
        }
    }

    @Test("Baseline does not enqueue calendar work for already expired items")
    func baselineSkipsExpiredCalendarWork() async throws {
        try await withDatabase { database in
            let clock = MutableTestClock(Date(timeIntervalSince1970: 30_000))
            let reader = MutableSyncReader(source: .canvas, snapshot: canvasSnapshot(taskIDs: ["task-1"]))
            let engine = makeEngine(database: database, readers: [reader], clock: clock)
            _ = try await engine.synchronize(source: .canvas, trigger: .manual)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work") == 0)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 1)
        }
    }

    @Test("Incomplete first snapshots preserve task and announcement baselines across restart")
    func incompleteBaselineSurvivesRestart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-baseline-restart-\(UUID().uuidString)", isDirectory: true)
        let path = directory.appendingPathComponent("sync.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            let database = try SQLiteDatabase(path: path)
            var partial = canvasSnapshot(taskIDs: ["partial-task"])
            partial.announcements = [announcement(id: "partial-announcement")]
            partial.completeObjectTypes = [.course]
            let reader = MutableSyncReader(source: .canvas, snapshot: partial)
            let engine = makeEngine(
                database: database, readers: [reader],
                clock: MutableTestClock(Date(timeIntervalSince1970: 1_000))
            )
            _ = try await engine.synchronize(source: .canvas, trigger: .manual)
            #expect(try database.scalarInt(
                "SELECT COUNT(*) AS value FROM source_baselines WHERE object_type IN ('learning_task', 'announcement')"
            ) == 0)
        }

        do {
            let database = try SQLiteDatabase(path: path)
            var firstComplete = canvasSnapshot(taskIDs: ["partial-task", "historical-task"])
            firstComplete.announcements = [
                announcement(id: "partial-announcement"), announcement(id: "historical-announcement")
            ]
            let reader = MutableSyncReader(source: .canvas, snapshot: firstComplete)
            let engine = makeEngine(
                database: database, readers: [reader],
                clock: MutableTestClock(Date(timeIntervalSince1970: 2_000))
            )
            _ = try await engine.synchronize(source: .canvas, trigger: .recovery)
            #expect(try database.scalarInt(
                "SELECT COUNT(*) AS value FROM outbox_work WHERE kind = 'notification.schedule'"
            ) == 0)
            #expect(try database.scalarInt(
                "SELECT COUNT(*) AS value FROM source_baselines WHERE object_type IN ('learning_task', 'announcement')"
            ) == 2)
        }

        do {
            let database = try SQLiteDatabase(path: path)
            var afterBaseline = canvasSnapshot(taskIDs: ["partial-task", "historical-task", "new-task"])
            afterBaseline.announcements = [
                announcement(id: "partial-announcement"), announcement(id: "historical-announcement"),
                announcement(id: "new-announcement")
            ]
            let reader = MutableSyncReader(source: .canvas, snapshot: afterBaseline)
            let engine = makeEngine(
                database: database, readers: [reader],
                clock: MutableTestClock(Date(timeIntervalSince1970: 3_000))
            )
            _ = try await engine.synchronize(source: .canvas, trigger: .manual)
            #expect(try database.scalarInt(
                "SELECT COUNT(*) AS value FROM outbox_work WHERE kind = 'notification.schedule'"
            ) == 2)
        }
    }

    @Test("Timestamp-free announcements retain their first local fallback across restart")
    func timestampFreeAnnouncementIsIdempotent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-announcement-restart-\(UUID().uuidString)", isDirectory: true)
        let path = directory.appendingPathComponent("sync.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }
        var storedPublishedAt: Double = 0
        var storedChangeCount = 0
        var storedOutboxCount = 0

        do {
            let database = try SQLiteDatabase(path: path)
            let clock = MutableTestClock(Date(timeIntervalSince1970: 1_000))
            let reader = MutableSyncReader(source: .canvas, snapshot: canvasSnapshot(taskIDs: []))
            let engine = makeEngine(database: database, readers: [reader], clock: clock)
            _ = try await engine.synchronize(source: .canvas, trigger: .manual)

            var withUndated = canvasSnapshot(taskIDs: [])
            withUndated.announcements.append(announcement(
                id: "announcement-without-source-time", publishedAt: nil, updatedAt: nil
            ))
            await reader.set(snapshot: withUndated)
            clock.advance(1_000)
            let inserted = try await engine.synchronize(source: .canvas, trigger: .manual)
            #expect(inserted.insertedCount == 1)
            let row = try #require(database.query(
                "SELECT published_at FROM announcements WHERE source_object_id = 'announcement-without-source-time'"
            ).first)
            storedPublishedAt = try #require(row.double("published_at"))
            #expect(storedPublishedAt == 2_000)
            storedChangeCount = try database.scalarInt("SELECT COUNT(*) AS value FROM change_records")
            storedOutboxCount = try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work")
        }

        do {
            let database = try SQLiteDatabase(path: path)
            var unchanged = canvasSnapshot(taskIDs: [])
            unchanged.announcements.append(announcement(
                id: "announcement-without-source-time", publishedAt: nil, updatedAt: nil
            ))
            let reader = MutableSyncReader(source: .canvas, snapshot: unchanged)
            let engine = makeEngine(
                database: database, readers: [reader],
                clock: MutableTestClock(Date(timeIntervalSince1970: 9_000))
            )
            let repeated = try await engine.synchronize(source: .canvas, trigger: .recovery)
            let row = try #require(database.query(
                "SELECT published_at FROM announcements WHERE source_object_id = 'announcement-without-source-time'"
            ).first)
            #expect(row.double("published_at") == storedPublishedAt)
            #expect(repeated.updatedCount == 0)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM change_records") == storedChangeCount)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work") == storedOutboxCount)
        }
    }

    @Test("Title and due-date updates preserve identity and create field changes")
    func taskUpdates() async throws {
        try await withDatabase { database in
            let clock = MutableTestClock(Date(timeIntervalSince1970: 3_000))
            let reader = MutableSyncReader(source: .canvas, snapshot: canvasSnapshot(taskIDs: ["task-1"]))
            let engine = makeEngine(database: database, readers: [reader], clock: clock)
            _ = try await engine.synchronize(source: .canvas, trigger: .manual)
            let originalID = try #require(database.query("SELECT id FROM learning_tasks").first?.string("id"))

            var changed = canvasSnapshot(taskIDs: ["task-1"])
            changed.tasks = [NormalizedTask(
                sourceObjectID: "task-1", courseSourceObjectID: "course-1", title: "Revised title",
                officialType: "quiz", normalizedType: "quiz",
                officialDueAt: Date(timeIntervalSince1970: 20_000), opensAt: nil, locksAt: nil,
                sourceURL: "https://canvas.invalid/tasks/task-1"
            )]
            await reader.set(snapshot: changed)
            clock.advance(60)
            let summary = try await engine.synchronize(source: .canvas, trigger: .manual)

            let row = try #require(database.query("SELECT * FROM learning_tasks").first)
            #expect(row.string("id") == originalID)
            #expect(row.string("title") == "Revised title")
            #expect(summary.updatedCount == 1)
            let fields = Set(try database.query(
                "SELECT field_name FROM change_records WHERE object_id = ?",
                bindings: [.text(originalID)]
            ).compactMap { $0.string("field_name") })
            #expect(fields.contains("title"))
            #expect(fields.contains("official_type"))
            #expect(fields.contains("normalized_type"))
            #expect(fields.contains("official_due_at"))
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 1)
        }
    }

    @Test("Meeting time/location changes and explicit cancellation update the same object")
    func meetingUpdatesAndCancellation() async throws {
        try await withDatabase { database in
            let clock = MutableTestClock(Date(timeIntervalSince1970: 4_000))
            let reader = MutableSyncReader(source: .siweb, snapshot: siwebSnapshot(cancelled: false))
            let engine = makeEngine(database: database, readers: [reader], clock: clock)
            _ = try await engine.synchronize(source: .siweb, trigger: .manual)
            let originalID = try #require(database.query("SELECT id FROM course_meetings").first?.string("id"))

            await reader.set(snapshot: siwebSnapshot(cancelled: true, shifted: true))
            clock.advance(60)
            let summary = try await engine.synchronize(source: .siweb, trigger: .manual)
            let row = try #require(database.query("SELECT * FROM course_meetings").first)
            #expect(row.string("id") == originalID)
            #expect(row.string("source_state") == "cancelled")
            #expect(row.string("location") == "Room B")
            #expect(summary.cancelledCount == 1)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work WHERE kind = 'calendar.remove'") == 1)
        }
    }

    @Test("Incomplete and first complete absence do not delete; second complete absence soft-deletes")
    func deletionEvidence() async throws {
        try await withDatabase { database in
            let clock = MutableTestClock(Date(timeIntervalSince1970: 5_000))
            let reader = MutableSyncReader(source: .canvas, snapshot: canvasSnapshot(taskIDs: ["task-1"]))
            let engine = makeEngine(database: database, readers: [reader], clock: clock)
            _ = try await engine.synchronize(source: .canvas, trigger: .manual)

            await reader.set(snapshot: canvasSnapshot(taskIDs: [], completeTasks: false))
            clock.advance(60)
            _ = try await engine.synchronize(source: .canvas, trigger: .manual)
            #expect(try taskState(database) == "active")

            await reader.set(snapshot: canvasSnapshot(taskIDs: [], completeTasks: true))
            clock.advance(60)
            _ = try await engine.synchronize(source: .canvas, trigger: .manual)
            #expect(try taskState(database) == "active")

            clock.advance(60)
            let final = try await engine.synchronize(source: .canvas, trigger: .manual)
            #expect(try taskState(database) == "cancelled")
            #expect(final.cancelledCount == 1)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 1)
        }
    }

    @Test("Failed request neither corrupts data nor contributes deletion evidence")
    func failedRequestNoDeletion() async throws {
        try await withDatabase { database in
            let clock = MutableTestClock(Date(timeIntervalSince1970: 6_000))
            let reader = MutableSyncReader(source: .canvas, snapshot: canvasSnapshot(taskIDs: ["task-1"]))
            let engine = makeEngine(database: database, readers: [reader], clock: clock)
            _ = try await engine.synchronize(source: .canvas, trigger: .manual)
            await reader.set(error: SyncEngineError(category: .offline, retryable: true))
            clock.advance(60)
            await #expect(throws: SyncEngineError(category: .offline, retryable: true)) {
                try await engine.synchronize(source: .canvas, trigger: .manual)
            }
            #expect(try taskState(database) == "active")
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM source_presence WHERE consecutive_complete_absences > 0") == 0)
        }
    }

    @Test("One source failure is isolated from the other source")
    func sourceFailureIsolation() async throws {
        try await withDatabase { database in
            let canvas = MutableSyncReader(source: .canvas, snapshot: canvasSnapshot(taskIDs: ["task-1"]))
            await canvas.set(error: SyncEngineError(category: .unauthorized, retryable: false))
            let siweb = MutableSyncReader(source: .siweb, snapshot: siwebSnapshot(cancelled: false))
            let engine = makeEngine(database: database, readers: [canvas, siweb])

            let outcomes = await engine.synchronizeAll(trigger: .manual)
            #expect(outcomes.count == 2)
            let canvasResult = try #require(outcomes.first { $0.source == .canvas })
            let siwebResult = try #require(outcomes.first { $0.source == .siweb })
            if case .failure(let error) = canvasResult.result { #expect(error.category == .unauthorized) }
            else { Issue.record("Canvas should fail") }
            if case .success(let summary) = siwebResult.result { #expect(summary.insertedCount == 2) }
            else { Issue.record("SIweb should succeed") }
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM course_meetings") == 1)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 0)
        }
    }

    @Test("Keychain failures are recorded as actionable authorization failures")
    func keychainFailureClassification() async throws {
        try await withDatabase { database in
            let engine = makeEngine(
                database: database,
                readers: [KeychainFailingSyncReader(source: .canvas, error: .denied)]
            )

            await #expect(throws: SyncEngineError(category: .unauthorized, retryable: false)) {
                try await engine.synchronize(source: .canvas, trigger: .recovery)
            }
            let run = try #require(database.query(
                "SELECT fetch_state, error_category, redacted_error_summary FROM sync_runs"
            ).first)
            #expect(run.string("fetch_state") == "failed")
            #expect(run.string("error_category") == SyncErrorCategory.unauthorized.rawValue)
            #expect(run.string("redacted_error_summary") == SyncErrorCategory.unauthorized.rawValue)
            #expect(try database.query(
                "SELECT authorization_state FROM source_accounts WHERE source_kind = 'Canvas'"
            ).first?.string("authorization_state") == "unauthorized")
        }
    }

    @Test("SIweb login redirects require reconnection and a later success restores authorization")
    func siwebSessionStateRecovery() async throws {
        try await withDatabase { database in
            let failed = ConnectorErrorReader(
                source: SourceKind.siweb,
                error: SIwebConnectorError.structural(.loginRedirect)
            )
            let failedEngine = makeEngine(database: database, readers: [failed])

            await #expect(throws: SyncEngineError(category: .unauthorized, retryable: false)) {
                try await failedEngine.synchronize(source: .siweb, trigger: .scheduled)
            }
            #expect(try database.query(
                "SELECT authorization_state FROM source_accounts WHERE source_kind = 'SIweb'"
            ).first?.string("authorization_state") == "unauthorized")

            let recovered = MutableSyncReader(
                source: .siweb, snapshot: siwebSnapshot(cancelled: false)
            )
            let recoveredEngine = makeEngine(database: database, readers: [recovered])
            _ = try await recoveredEngine.synchronize(source: .siweb, trigger: .manual)
            #expect(try database.query(
                "SELECT authorization_state FROM source_accounts WHERE source_kind = 'SIweb'"
            ).first?.string("authorization_state") == "authorized")
        }
    }

    @Test("Known-expired SIweb sessions pause only automatic attempts")
    func siwebExpiredSessionScheduling() {
        for state in ["missing", "expired", "revoked", "unauthorized"] {
            #expect(!ProductionSyncRunner.shouldAttemptSIweb(
                trigger: .scheduled, authorizationState: state
            ))
            #expect(!ProductionSyncRunner.shouldAttemptSIweb(
                trigger: .recovery, authorizationState: state
            ))
            #expect(ProductionSyncRunner.shouldAttemptSIweb(
                trigger: .manual, authorizationState: state
            ))
        }
        #expect(ProductionSyncRunner.shouldAttemptSIweb(
            trigger: .scheduled, authorizationState: "authorized"
        ))
        #expect(ProductionSyncRunner.shouldAttemptSIweb(
            trigger: .scheduled, authorizationState: nil
        ))
    }

    @Test("Domain, raw, change, run success, and outbox writes roll back together")
    func transactionRollback() async throws {
        try await withDatabase { database in
            let reader = MutableSyncReader(source: .canvas, snapshot: canvasSnapshot(taskIDs: ["task-1"]))
            let engine = makeEngine(database: database, readers: [reader], transactionFault: { throw InjectedFault.failure })
            do {
                _ = try await engine.synchronize(source: .canvas, trigger: .manual)
                Issue.record("Expected injected transaction failure")
            } catch let error as SyncEngineError {
                #expect(error.category == .unknown)
            }
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM courses") == 0)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 0)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM raw_source_records") == 0)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM change_records") == 0)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work") == 0)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM source_baselines") == 0)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM sync_runs WHERE persistence_state = 'committed'") == 0)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM sync_runs WHERE error_category IS NOT NULL") == 1)
        }
    }

    @Test("Outbox survives processing crash state and is delivered exactly once on recovery")
    func outboxCrashRecovery() async throws {
        try await withDatabase { database in
            let clock = MutableTestClock(Date(timeIntervalSince1970: 8_000))
            let reader = MutableSyncReader(source: .canvas, snapshot: canvasSnapshot(taskIDs: ["task-1"]))
            let engine = makeEngine(database: database, readers: [reader], clock: clock)
            _ = try await engine.synchronize(source: .canvas, trigger: .manual)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work") == 1)
            try database.execute("UPDATE outbox_work SET state = 'processing'")

            let calendar = FakeCalendarService()
            let notifications = FakeNotificationService()
            let processor = OutboxProcessor(
                database: database, calendar: calendar, notifications: notifications, clock: clock
            )
            #expect(await processor.processPending() == 1)
            #expect(await processor.processPending() == 0)
            #expect(await calendar.received.count == 1)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work WHERE state = 'completed'") == 1)
        }
    }

    @Test("Outbox delivery failure persists bounded retry state and reuses the same command identity")
    func outboxRetry() async throws {
        try await withDatabase { database in
            let clock = MutableTestClock(Date(timeIntervalSince1970: 8_500))
            let reader = MutableSyncReader(source: .canvas, snapshot: canvasSnapshot(taskIDs: ["task-1"]))
            let engine = makeEngine(database: database, readers: [reader], clock: clock)
            _ = try await engine.synchronize(source: .canvas, trigger: .manual)
            let calendar = FlakyCalendarService()
            let processor = OutboxProcessor(
                database: database, calendar: calendar,
                notifications: FakeNotificationService(), clock: clock
            )

            #expect(await processor.processPending() == 0)
            let failed = try #require(database.query("SELECT * FROM outbox_work").first)
            #expect(failed.string("state") == "pending")
            #expect(failed.int("attempt_count") == 1)
            #expect(failed.string("last_error_category") == "delivery_failed")

            clock.advance(60)
            #expect(await processor.processPending() == 1)
            let delivered = await calendar.commands
            #expect(delivered.count == 2)
            #expect(delivered[0] == delivered[1])
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work WHERE state = 'completed'") == 1)
        }
    }

    @Test("Only one active run is allowed per source")
    func singleFlight() async throws {
        try await withDatabase { database in
            let reader = BlockingSyncReader(source: .canvas, snapshot: canvasSnapshot(taskIDs: []))
            let engine = makeEngine(database: database, readers: [reader])
            let first = Task { try await engine.synchronize(source: .canvas, trigger: .manual) }
            while !(await reader.hasStarted) { await Task.yield() }
            await #expect(throws: SyncEngineError(category: .alreadyRunning, retryable: false)) {
                try await engine.synchronize(source: .canvas, trigger: .scheduled)
            }
            await reader.release()
            _ = try await first.value
        }
    }

    @Test("Cancelling a run writes a redacted cancelled run and no source data")
    func cancellation() async throws {
        try await withDatabase { database in
            let reader = CancellationSyncReader(source: .canvas)
            let engine = makeEngine(database: database, readers: [reader])
            let task = Task { try await engine.synchronize(source: .canvas, trigger: .manual) }
            while !(await reader.hasStarted) { await Task.yield() }
            task.cancel()
            await #expect(throws: SyncEngineError(category: .cancelled, retryable: false)) {
                try await task.value
            }
            let courseCount = try database.scalarInt("SELECT COUNT(*) AS value FROM courses")
            let cancelledRuns = try database.scalarInt(
                "SELECT COUNT(*) AS value FROM sync_runs WHERE error_category = 'cancelled'"
            )
            #expect(courseCount == 0)
            #expect(cancelledRuns == 1)
        }
    }

    private func makeEngine(
        database: SQLiteDatabase,
        readers: [any SyncSourceReader],
        clock: any Clock = MutableTestClock(Date(timeIntervalSince1970: 10_000)),
        transactionFault: DeterministicSyncEngine.TransactionFault? = nil
    ) -> DeterministicSyncEngine {
        DeterministicSyncEngine(
            database: database,
            accounts: [canvasAccount, siwebAccount],
            readers: readers,
            clock: clock,
            transactionFault: transactionFault
        )
    }

    private var canvasAccount: SyncSourceAccount {
        SyncSourceAccount(
            id: UUID(uuidString: "a0000000-0000-0000-0000-000000000001")!, source: .canvas,
            instanceURL: "https://canvas.invalid", displayName: "Synthetic Canvas"
        )
    }

    private var siwebAccount: SyncSourceAccount {
        SyncSourceAccount(
            id: UUID(uuidString: "b0000000-0000-0000-0000-000000000001")!, source: .siweb,
            instanceURL: "https://siweb.invalid", displayName: "Synthetic SIweb"
        )
    }

    private func canvasSnapshot(taskIDs: [String], completeTasks: Bool = true) -> SyncSnapshot {
        SyncSnapshot(
            courses: [NormalizedCourse(
                sourceObjectID: "course-1", name: "Synthetic Course", code: "SYN-1",
                term: "Synthetic term", timeZone: "UTC", sourceURL: "https://canvas.invalid/courses/1"
            )],
            meetings: [],
            tasks: taskIDs.map { id in
                NormalizedTask(
                    sourceObjectID: id, courseSourceObjectID: "course-1", title: "Task \(id)",
                    officialType: "assignment", normalizedType: "assignment",
                    officialDueAt: Date(timeIntervalSince1970: 10_000), opensAt: nil, locksAt: nil,
                    sourceURL: "https://canvas.invalid/tasks/\(id)"
                )
            },
            announcements: [NormalizedAnnouncement(
                sourceObjectID: "announcement-1", courseSourceObjectID: "course-1",
                title: "Synthetic announcement", publishedAt: Date(timeIntervalSince1970: 900),
                updatedAt: nil, summary: "Synthetic summary", contentHash: "hash-1",
                sourceURL: "https://canvas.invalid/announcements/1"
            )],
            completeObjectTypes: completeTasks ? [.course, .learningTask, .announcement] : [.course, .announcement]
        )
    }

    private func announcement(
        id: String,
        publishedAt: Date? = Date(timeIntervalSince1970: 900),
        updatedAt: Date? = nil
    ) -> NormalizedAnnouncement {
        NormalizedAnnouncement(
            sourceObjectID: id, courseSourceObjectID: "course-1", title: "Announcement \(id)",
            publishedAt: publishedAt, updatedAt: updatedAt, summary: "Summary \(id)",
            contentHash: "hash-\(id)", sourceURL: "https://canvas.invalid/announcements/\(id)"
        )
    }

    private func siwebSnapshot(cancelled: Bool, shifted: Bool = false) -> SyncSnapshot {
        let offset: TimeInterval = shifted ? 3_600 : 0
        return SyncSnapshot(
            courses: [NormalizedCourse(
                sourceObjectID: "si-course-1", name: "Synthetic SI Course", code: "SI-1",
                term: "", timeZone: "Asia/Macau", sourceURL: "https://siweb.invalid/schedule"
            )],
            meetings: [NormalizedMeeting(
                sourceObjectID: "meeting-1", courseSourceObjectID: "si-course-1",
                startsAt: Date(timeIntervalSince1970: 20_000 + offset),
                endsAt: Date(timeIntervalSince1970: 23_600 + offset), timeZone: "Asia/Macau",
                location: shifted ? "Room B" : "Room A", sourceURL: "https://siweb.invalid/schedule",
                sourceState: cancelled ? .cancelled : .active,
                parserVersion: "synthetic-v1", contentHash: shifted ? "hash-2" : "hash-1"
            )],
            tasks: [], announcements: [], completeObjectTypes: [.course, .courseMeeting]
        )
    }

    private func withDatabase(_ operation: (SQLiteDatabase) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-sync-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await operation(try SQLiteDatabase(path: directory.appendingPathComponent("sync.sqlite3").path))
    }

    private func tableCounts(_ database: SQLiteDatabase) throws -> [Int] {
        try [
            "courses", "learning_tasks", "announcements", "raw_source_records", "change_records",
            "outbox_work", "source_presence", "source_baselines"
        ]
            .map { try database.scalarInt("SELECT COUNT(*) AS value FROM \($0)") }
    }

    private func taskState(_ database: SQLiteDatabase) throws -> String {
        try #require(database.query("SELECT source_state FROM learning_tasks").first?.string("source_state"))
    }
}

private enum InjectedFault: Error { case failure }

private final class MutableTestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.withLock { value } }
    func advance(_ interval: TimeInterval) { lock.withLock { value = value.addingTimeInterval(interval) } }
}

private actor MutableSyncReader: SyncSourceReader {
    nonisolated let source: SourceKind
    private var snapshot: SyncSnapshot
    private var error: SyncEngineError?

    init(source: SourceKind, snapshot: SyncSnapshot) {
        self.source = source
        self.snapshot = snapshot
    }

    func set(snapshot: SyncSnapshot) { self.snapshot = snapshot; error = nil }
    func set(error: SyncEngineError) { self.error = error }
    func read() async throws -> SyncSnapshot {
        if let error { throw error }
        return snapshot
    }
}

private struct KeychainFailingSyncReader: SyncSourceReader {
    let source: SourceKind
    let error: SecretStoreError

    func read() async throws -> SyncSnapshot { throw error }
}

private actor BlockingSyncReader: SyncSourceReader {
    nonisolated let source: SourceKind
    private let snapshot: SyncSnapshot
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasStarted = false

    init(source: SourceKind, snapshot: SyncSnapshot) {
        self.source = source
        self.snapshot = snapshot
    }

    func read() async throws -> SyncSnapshot {
        hasStarted = true
        await withCheckedContinuation { continuation = $0 }
        return snapshot
    }

    func release() { continuation?.resume(); continuation = nil }
}

private actor CancellationSyncReader: SyncSourceReader {
    nonisolated let source: SourceKind
    private(set) var hasStarted = false
    init(source: SourceKind) { self.source = source }
    func read() async throws -> SyncSnapshot {
        hasStarted = true
        try await Task.sleep(for: .seconds(30))
        return SyncSnapshot(courses: [], meetings: [], tasks: [], announcements: [], completeObjectTypes: [])
    }
}

private struct ConnectorErrorReader<Failure: Error & Sendable>: SyncSourceReader {
    let source: SourceKind
    let error: Failure
    func read() async throws -> SyncSnapshot { throw error }
}

private struct IncompleteCanvasBoundaryService: CanvasService {
    func courses(pageToken: String?) async throws -> FetchPage<CanvasCoursePayload> {
        FetchPage(
            values: [CanvasCoursePayload(sourceObjectID: "course-1", name: "Course", code: "C-1")],
            nextPageToken: nil, isCompleteSnapshot: false
        )
    }

    func learningTasks(courseID: String, pageToken: String?) async throws -> FetchPage<CanvasTaskPayload> {
        FetchPage(values: [], nextPageToken: nil, isCompleteSnapshot: true)
    }

    func announcements(courseID: String, pageToken: String?) async throws -> FetchPage<CanvasAnnouncementPayload> {
        FetchPage(values: [], nextPageToken: nil, isCompleteSnapshot: true)
    }
}

private actor FlakyCalendarService: CalendarService {
    private(set) var commands: [[CalendarCommand]] = []
    private var shouldFail = true

    func apply(_ commands: [CalendarCommand]) async throws -> [CalendarCommandResult] {
        self.commands.append(commands)
        if shouldFail {
            shouldFail = false
            throw InjectedFault.failure
        }
        return commands.map { command in
            switch command {
            case .upsert(_, let objectID), .removeBoundEvent(_, let objectID):
                CalendarCommandResult(objectID: objectID, bindingIdentifier: nil)
            }
        }
    }
}
