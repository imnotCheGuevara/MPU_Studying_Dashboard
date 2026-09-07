import Foundation
import Testing
@testable import CampusDashboard

@Suite("Stage 09 end-to-end integration hardening")
struct IntegrationHardeningTests {
    @Test("First sync, incremental update, source isolation, offline recovery, and restart preserve state")
    func synchronizationLifecycle() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-stage09-e2e-\(UUID().uuidString)", isDirectory: true)
        let path = directory.appendingPathComponent("integration.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }
        let canvas = Stage09MutableReader(source: .canvas, snapshot: canvasSnapshot(title: "First", includeSecond: false))
        let siweb = Stage09MutableReader(source: .siweb, snapshot: siwebSnapshot())

        do {
            let database = try SQLiteDatabase(path: path)
            let engine = makeEngine(database: database, readers: [canvas, siweb])
            let first = await engine.synchronizeAll(trigger: .manual)
            #expect(first.count == 2)
            #expect(first.allSatisfy { if case .success = $0.result { true } else { false } })
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 1)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM course_meetings") == 1)

            await canvas.set(snapshot: canvasSnapshot(title: "Incremental", includeSecond: false))
            await siweb.set(error: SyncEngineError(category: .temporaryServer, retryable: true))
            let isolated = await engine.synchronizeAll(trigger: .scheduled)
            let canvasOutcome = try #require(isolated.first { $0.source == .canvas })
            let siwebOutcome = try #require(isolated.first { $0.source == .siweb })
            if case .success(let summary) = canvasOutcome.result { #expect(summary.updatedCount == 1) }
            else { Issue.record("Canvas should succeed independently") }
            #expect(siwebOutcome.result == .failure(SyncEngineError(category: .temporaryServer, retryable: true)))
            #expect(try database.query("SELECT title FROM learning_tasks").first?.string("title") == "Incremental")
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM course_meetings") == 1)

            await canvas.set(error: SyncEngineError(category: .offline, retryable: true))
            await #expect(throws: SyncEngineError(category: .offline, retryable: true)) {
                try await engine.synchronize(source: .canvas, trigger: .scheduled)
            }
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 1)
            await canvas.set(snapshot: canvasSnapshot(title: "Recovered", includeSecond: true))
            let recovered = try await engine.synchronize(source: .canvas, trigger: .recovery)
            #expect(recovered.insertedCount == 1)
            #expect(recovered.updatedCount == 1)
        }

        let reopened = try SQLiteDatabase(path: path)
        #expect(try reopened.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 2)
        #expect(try reopened.query(
            "SELECT title FROM learning_tasks WHERE source_object_id='task-1'"
        ).first?.string("title") == "Recovered")
        #expect(try reopened.scalarInt("SELECT COUNT(*) AS value FROM sync_runs WHERE error_category='offline'") == 1)
    }

    @Test("Cancellation commits only a redacted run record and remains recoverable")
    func cancellationAndRecovery() async throws {
        let database = try SQLiteDatabase(path: ":memory:")
        let reader = Stage09BlockingReader(source: .canvas)
        let engine = makeEngine(database: database, readers: [reader])
        let task = Task { try await engine.synchronize(source: .canvas, trigger: .manual) }
        while !(await reader.started) { await Task.yield() }
        task.cancel()
        await #expect(throws: SyncEngineError(category: .cancelled, retryable: false)) { try await task.value }
        #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM raw_source_records") == 0)
        #expect(try database.query("SELECT redacted_error_summary FROM sync_runs").first?.string("redacted_error_summary") == "cancelled")

        let recovery = Stage09MutableReader(source: .canvas, snapshot: canvasSnapshot(title: "Recovered", includeSecond: false))
        let recoveryEngine = makeEngine(database: database, readers: [recovery])
        #expect(try await recoveryEngine.synchronize(source: .canvas, trigger: .recovery).insertedCount == 2)
    }

    @Test("Calendar and notification durable outbox items retry independently and converge once")
    func durableOutboxRecovery() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let clock = Stage09Clock(now)
        let database = try SQLiteDatabase(path: ":memory:")
        try enqueue(database, id: "calendar-work", key: "calendar-key", envelope: .calendarUpsert(
            objectType: "course_meeting", objectID: "meeting"
        ), now: now)
        try enqueue(database, id: "notification-work", key: "notification-key", envelope: .notificationNew(
            key: "notice", objectID: "task", at: now.addingTimeInterval(60)
        ), now: now)
        let calendar = Stage09FlakyCalendar()
        let notifications = Stage09FlakyNotifications()
        let processor = OutboxProcessor(
            database: database, calendar: calendar, notifications: notifications, clock: clock
        )

        #expect(await processor.processPending() == 0)
        #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work WHERE state='pending' AND attempt_count=1") == 2)
        clock.advance(60)
        #expect(await processor.processPending() == 2)
        #expect(await calendar.successCount == 1)
        #expect(await notifications.successCount == 1)
        #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work WHERE state='completed'") == 2)
    }

    private func makeEngine(
        database: SQLiteDatabase, readers: [any SyncSourceReader]
    ) -> DeterministicSyncEngine {
        DeterministicSyncEngine(database: database, accounts: [
            SyncSourceAccount(id: UUID(uuidString: "a0000000-0000-0000-0000-000000000009")!, source: .canvas,
                              instanceURL: "https://canvas.invalid", displayName: "Synthetic Canvas"),
            SyncSourceAccount(id: UUID(uuidString: "b0000000-0000-0000-0000-000000000009")!, source: .siweb,
                              instanceURL: "https://siweb.invalid", displayName: "Synthetic SIweb")
        ], readers: readers, clock: Stage09Clock(Date(timeIntervalSince1970: 5_000)))
    }

    private func canvasSnapshot(title: String, includeSecond: Bool) -> SyncSnapshot {
        let ids = includeSecond ? ["task-1", "task-2"] : ["task-1"]
        return SyncSnapshot(
            courses: [NormalizedCourse(sourceObjectID: "canvas-course", name: "Synthetic", code: "SYN",
                                       term: "Term", timeZone: "UTC", sourceURL: nil)],
            meetings: [],
            tasks: ids.map { id in NormalizedTask(
                sourceObjectID: id, courseSourceObjectID: "canvas-course",
                title: id == "task-1" ? title : "Second", officialType: "assignment",
                normalizedType: "assignment", officialDueAt: Date(timeIntervalSince1970: 20_000),
                opensAt: nil, locksAt: nil, sourceURL: nil
            ) },
            announcements: [], completeObjectTypes: [.course, .learningTask, .announcement]
        )
    }

    private func siwebSnapshot() -> SyncSnapshot {
        SyncSnapshot(
            courses: [NormalizedCourse(sourceObjectID: "si-course", name: "Synthetic SI", code: "SI",
                                       term: "", timeZone: "UTC", sourceURL: nil)],
            meetings: [NormalizedMeeting(
                sourceObjectID: "meeting", courseSourceObjectID: "si-course",
                startsAt: Date(timeIntervalSince1970: 30_000), endsAt: Date(timeIntervalSince1970: 33_600),
                timeZone: "UTC", location: "Room", sourceURL: nil, sourceState: .active,
                parserVersion: "fixture-v1", contentHash: "fixture-hash"
            )], tasks: [], announcements: [], completeObjectTypes: [.course, .courseMeeting]
        )
    }

    private func enqueue(
        _ database: SQLiteDatabase, id: String, key: String, envelope: OutboxEnvelope, now: Date
    ) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        try database.execute(
            """
            INSERT INTO outbox_work(id, kind, deduplication_key, object_type, object_id, payload,
              state, attempt_count, available_at, created_at, updated_at)
            VALUES (?, 'stage09', ?, 'fixture', 'fixture', ?, 'pending', 0, ?, ?, ?)
            """, bindings: [
                .text(id), .text(key), .blob(try encoder.encode(envelope)),
                .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970)
            ]
        )
    }
}

private actor Stage09MutableReader: SyncSourceReader {
    nonisolated let source: SourceKind
    private var snapshot: SyncSnapshot
    private var error: SyncEngineError?
    init(source: SourceKind, snapshot: SyncSnapshot) { self.source = source; self.snapshot = snapshot }
    func set(snapshot: SyncSnapshot) { self.snapshot = snapshot; error = nil }
    func set(error: SyncEngineError) { self.error = error }
    func read() throws -> SyncSnapshot { if let error { throw error }; return snapshot }
}

private actor Stage09BlockingReader: SyncSourceReader {
    nonisolated let source: SourceKind
    private(set) var started = false
    init(source: SourceKind) { self.source = source }
    func read() async throws -> SyncSnapshot {
        started = true
        try await Task.sleep(for: .seconds(30))
        return SyncSnapshot(courses: [], meetings: [], tasks: [], announcements: [], completeObjectTypes: [])
    }
}

private final class Stage09Clock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

private enum Stage09Failure: Error { case unavailable }

private actor Stage09FlakyCalendar: CalendarService {
    private var shouldFail = true
    private(set) var successCount = 0
    func apply(_ commands: [CalendarCommand]) throws -> [CalendarCommandResult] {
        if shouldFail { shouldFail = false; throw Stage09Failure.unavailable }
        successCount += commands.count
        return commands.map { command in
            switch command {
            case .upsert(_, let objectID), .removeBoundEvent(_, let objectID):
                CalendarCommandResult(objectID: objectID, bindingIdentifier: "fixture")
            }
        }
    }
}

private actor Stage09FlakyNotifications: NotificationService {
    private var shouldFail = true
    private(set) var successCount = 0
    func apply(_ commands: [NotificationCommand]) throws {
        if shouldFail { shouldFail = false; throw Stage09Failure.unavailable }
        successCount += commands.count
    }
}
