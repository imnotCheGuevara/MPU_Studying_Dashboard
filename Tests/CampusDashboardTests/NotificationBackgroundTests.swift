import Foundation
import Testing
@testable import CampusDashboard

@Suite("Stage 07 notifications and background scheduling")
struct NotificationBackgroundTests {
    @Test("Permission states and explicit request handle denial, grant, and revocation")
    func permissionLifecycle() async throws {
        let database = try SQLiteDatabase(path: ":memory:")
        let center = TestNotificationCenter(state: .notDetermined, requestResult: true)
        let service = CampusNotificationService(database: database, center: center)
        #expect(await service.authorizationState() == .notDetermined)
        #expect(try await service.requestAccessFromUserAction())
        #expect(await center.requestCount == 1)
        await center.setState(.denied)
        #expect(await service.authorizationState() == .denied)
        #expect(try await service.requestAccessFromUserAction() == false)
        #expect(await center.requestCount == 1)
    }

    @Test("Revoked permission cancels the app's tracked pending reminders without affecting data")
    func permissionRevocation() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let database = try SQLiteDatabase(path: ":memory:")
        try seedTask(database, due: now.addingTimeInterval(100_000))
        try enableNotifications(database, now: now)
        let center = TestNotificationCenter(state: .authorized)
        let service = CampusNotificationService(database: database, center: center, clock: FixedClock(now: now))
        try await service.reconcileReminders()
        #expect(!((await center.requests).isEmpty))
        await center.setState(.denied)
        try await service.reconcileReminders()
        #expect(await center.requests.isEmpty)
        #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 1)
    }

    @MainActor
    @Test("Denied notification permission leaves local UI state and sync service usable")
    func denialIsolation() async throws {
        let center = TestNotificationCenter(state: .denied)
        let database = try SQLiteDatabase(path: ":memory:")
        let service = CampusNotificationService(database: database, center: center)
        let model = DashboardModel(scenario: .populated, notificationService: service)
        let task = try #require(model.snapshot.tasks.first)
        model.toggleTask(task.id)
        #expect(model.snapshot.tasks.first?.isLocallyComplete == true)
        let sync = FakeSyncService(summaries: [.canvas: .init(
            source: .canvas, readCount: 1, insertedCount: 0, updatedCount: 0, cancelledCount: 0
        )])
        #expect(try await sync.synchronize(source: .canvas, trigger: .manual).readCount == 1)
    }

    @Test("Notification keys are stable and unique across objects, types, slots, and versions")
    func stableKeys() {
        let args = ("learning_task", "task-1", CampusNotificationType.deadlineReminder, "due-1-lead-60", 2)
        let first = NotificationKey.make(
            objectType: args.0, objectID: args.1, type: args.2, slot: args.3, policyVersion: args.4
        )
        let second = NotificationKey.make(
            objectType: args.0, objectID: args.1, type: args.2, slot: args.3, policyVersion: args.4
        )
        #expect(first == second)
        #expect(first != NotificationKey.make(
            objectType: args.0, objectID: "task-2", type: args.2, slot: args.3, policyVersion: args.4
        ))
        #expect(first != NotificationKey.make(
            objectType: args.0, objectID: args.1, type: .newAssignment, slot: args.3, policyVersion: args.4
        ))
    }

    @Test("Notification outbox replay and repeated service commands schedule once")
    func outboxReplay() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let clock = MutableStage07Clock(now)
        let database = try SQLiteDatabase(path: ":memory:")
        try seedTask(database, due: now.addingTimeInterval(10_000))
        try enableNotifications(database, now: now)
        let center = TestNotificationCenter(state: .authorized)
        let service = CampusNotificationService(database: database, center: center, clock: clock)
        let envelope = OutboxEnvelope.notificationNew(key: "new:learning_task:task", objectID: "task", at: now)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        try database.execute(
            """
            INSERT INTO outbox_work(id, kind, deduplication_key, object_type, object_id, payload,
              state, attempt_count, available_at, created_at, updated_at)
            VALUES ('outbox', 'notification.schedule', 'stable-outbox', 'notification', 'task', ?,
              'pending', 0, ?, ?, ?)
            """, bindings: [
                .blob(try encoder.encode(envelope)), .real(now.timeIntervalSince1970),
                .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970)
            ]
        )
        let processor = OutboxProcessor(
            database: database, calendar: FakeCalendarService(), notifications: service, clock: clock
        )
        #expect(await processor.processPending() == 1)
        try database.execute("UPDATE outbox_work SET state='pending' WHERE id='outbox'")
        #expect(await processor.processPending() == 1)
        #expect(await center.requests.count == 1)
        #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM notification_deliveries") == 1)
    }

    @Test("Due changes cancel old reminders and schedule new stable reminders")
    func dueChange() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let database = try SQLiteDatabase(path: ":memory:")
        try seedTask(database, due: now.addingTimeInterval(48 * 3_600))
        try enableNotifications(database, now: now)
        let center = TestNotificationCenter(state: .authorized)
        let service = CampusNotificationService(database: database, center: center, clock: FixedClock(now: now))
        try await service.reconcileReminders()
        let old = Set(await center.requests.map(\.identifier))
        try database.execute(
            "UPDATE learning_tasks SET official_due_at=? WHERE id='task'",
            bindings: [.real(now.addingTimeInterval(72 * 3_600).timeIntervalSince1970)]
        )
        try await service.reconcileReminders()
        let current = Set(await center.requests.map(\.identifier))
        #expect(old.isDisjoint(with: current))
        let removedOld = await center.removed.filter(old.contains)
        #expect(!removedOld.isEmpty)
    }

    @Test("Source cancellation and course-time changes cancel or replace reminders")
    func cancellationAndMeetingChange() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let database = try SQLiteDatabase(path: ":memory:")
        try seedMeeting(database, start: now.addingTimeInterval(10_000))
        try enableNotifications(database, now: now)
        let center = TestNotificationCenter(state: .authorized)
        let service = CampusNotificationService(database: database, center: center, clock: FixedClock(now: now))
        try await service.reconcileReminders()
        let first = try #require(await center.requests.first?.identifier)
        try database.execute(
            "UPDATE course_meetings SET starts_at=? WHERE id='meeting'",
            bindings: [.real(now.addingTimeInterval(20_000).timeIntervalSince1970)]
        )
        try await service.reconcileReminders()
        #expect(await center.requests.count == 1)
        #expect(await center.requests.first?.identifier != first)
        try database.execute("UPDATE course_meetings SET source_state='cancelled' WHERE id='meeting'")
        try await service.reconcileReminders()
        #expect(await center.requests.isEmpty)
    }

    @Test("Master and course switches prevent and cancel scheduling")
    func switches() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let database = try SQLiteDatabase(path: ":memory:")
        try seedTask(database, due: now.addingTimeInterval(48 * 3_600))
        try enableNotifications(database, now: now)
        let center = TestNotificationCenter(state: .authorized)
        let service = CampusNotificationService(database: database, center: center, clock: FixedClock(now: now))
        try await service.reconcileReminders()
        let initiallyScheduled = await center.requests
        #expect(!initiallyScheduled.isEmpty)
        try await service.setCourseEnabled(false, courseID: "course")
        #expect(await center.requests.isEmpty)
        var preferences = try service.preferences(); preferences.enabled = false
        try await service.updatePreferences(preferences)
        try await service.setCourseEnabled(true, courseID: "course")
        #expect(await center.requests.isEmpty)
    }

    @Test("Quiet hours delay useful reminders and discard reminders that would become stale")
    func quietDelayAndDrop() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Macau")!
        let now = date(2026, 9, 3, 21, 0, calendar: calendar)
        let database = try SQLiteDatabase(path: ":memory:")
        try seedTask(database, due: date(2026, 9, 4, 12, 0, calendar: calendar))
        var preferences = NotificationPreferences(
            enabled: true, deadlineOffsetsMinutes: [840], classLeadMinutes: 15,
            quietStartMinutes: 22 * 60, quietEndMinutes: 8 * 60, policyVersion: 1
        )
        try NotificationPersistence(database: database).save(preferences, now: now)
        let center = TestNotificationCenter(state: .authorized)
        let service = CampusNotificationService(
            database: database, center: center, clock: FixedClock(now: now), calendar: calendar
        )
        try await service.reconcileReminders()
        #expect(await center.requests.first?.fireDate == date(2026, 9, 4, 8, 0, calendar: calendar))
        await center.clear()
        try database.execute(
            "UPDATE learning_tasks SET official_due_at=? WHERE id='task'",
            bindings: [.real(date(2026, 9, 4, 7, 0, calendar: calendar).timeIntervalSince1970)]
        )
        preferences.deadlineOffsetsMinutes = [180]
        preferences.policyVersion = 2
        try NotificationPersistence(database: database).save(preferences, now: now)
        try await service.reconcileReminders()
        #expect(await center.requests.isEmpty)
    }

    @Test("Expired reminders and unconfirmed inferred dates are never scheduled")
    func expiredAndInferredGate() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let database = try SQLiteDatabase(path: ":memory:")
        try seedTask(database, due: now.addingTimeInterval(-100))
        try enableNotifications(database, now: now)
        let center = TestNotificationCenter(state: .authorized)
        let service = CampusNotificationService(database: database, center: center, clock: FixedClock(now: now))
        try await service.reconcileReminders()
        #expect(await center.requests.isEmpty)
        try database.execute(
            "UPDATE learning_tasks SET official_due_at=NULL, suggested_complete_at=?, suggestion_origin='ai', suggestion_confirmed_at=NULL WHERE id='task'",
            bindings: [.real(now.addingTimeInterval(100_000).timeIntervalSince1970)]
        )
        try await service.reconcileReminders()
        #expect(await center.requests.isEmpty)
        try database.execute(
            "UPDATE learning_tasks SET suggestion_confirmed_at=? WHERE id='task'",
            bindings: [.real(now.timeIntervalSince1970)]
        )
        try await service.reconcileReminders()
        let confirmedScheduled = await center.requests
        #expect(!confirmedScheduled.isEmpty)
    }

    @Test("New assignment, quiz, and announcement are classified and emitted once")
    func newItemTypesOnce() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let database = try SQLiteDatabase(path: ":memory:")
        try seedTask(database, id: "assignment", due: nil, normalizedType: "assignment")
        try seedTask(database, id: "quiz", due: nil, normalizedType: "quiz", reuseAccountAndCourse: true)
        try seedAnnouncement(database)
        try enableNotifications(database, now: now)
        let center = TestNotificationCenter(state: .authorized)
        let service = CampusNotificationService(database: database, center: center, clock: FixedClock(now: now))
        for id in ["assignment", "quiz", "announcement"] {
            try await service.apply([.schedule(key: "legacy:\(id)", objectID: id, at: now)])
            try await service.apply([.schedule(key: "legacy:\(id)", objectID: id, at: now)])
        }
        let types = Set(try database.query("SELECT notification_type FROM notification_deliveries")
            .compactMap { $0.string("notification_type") })
        #expect(types == ["new_assignment", "new_quiz", "new_announcement"])
        #expect(await center.requests.count == 3)
    }

    @Test("Failure and recovery notifications are each emitted once and suppression resets")
    func failureRecovery() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let database = try SQLiteDatabase(path: ":memory:")
        try seedAccountAndCourse(database)
        try enableNotifications(database, now: now)
        let center = TestNotificationCenter(state: .authorized)
        let service = CampusNotificationService(database: database, center: center, clock: FixedClock(now: now))
        try await service.recordSyncResult(sourceAccountID: "account", sourceName: "Synthetic", errorCategory: "offline")
        try await service.recordSyncResult(sourceAccountID: "account", sourceName: "Synthetic", errorCategory: "offline")
        #expect(await center.requests.count == 1)
        try await service.recordSyncResult(sourceAccountID: "account", sourceName: "Synthetic", errorCategory: nil)
        try await service.recordSyncResult(sourceAccountID: "account", sourceName: "Synthetic", errorCategory: nil)
        #expect(await center.requests.count == 2)
        try await service.recordSyncResult(sourceAccountID: "account", sourceName: "Synthetic", errorCategory: "offline")
        #expect(await center.requests.count == 3)
    }

    @Test("Timezone and DST forward/backward boundaries produce one valid reminder")
    func timezoneDST() async throws {
        for (month, day) in [(3, 8), (11, 1)] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/New_York")!
            let now = date(2026, month, day, 0, 30, calendar: calendar)
            let due = date(2026, month, day, 4, 0, calendar: calendar)
            let database = try SQLiteDatabase(path: ":memory:")
            try seedTask(database, due: due)
            try NotificationPersistence(database: database).save(.init(
                enabled: true, deadlineOffsetsMinutes: [60], classLeadMinutes: 15,
                quietStartMinutes: 60, quietEndMinutes: 210, policyVersion: 1
            ), now: now)
            let center = TestNotificationCenter(state: .authorized)
            let service = CampusNotificationService(
                database: database, center: center, clock: FixedClock(now: now), calendar: calendar
            )
            try await service.reconcileReminders()
            #expect(await center.requests.count == 1)
            #expect(await center.requests.first!.fireDate < due)
        }
    }

    @Test("Background enable/disable, missed-run recovery, and development interval persist across restart")
    func backgroundLifecycle() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stage07-background-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("db.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let clock = MutableStage07Clock(now)
        let item = TestBackgroundItem()
        let runner = TestScheduledRunner()
        do {
            let database = try SQLiteDatabase(path: path)
            let notification = CampusNotificationService(
                database: database, center: TestNotificationCenter(state: .denied), clock: clock
            )
            let scheduler = BackgroundSyncScheduler(
                database: database, runner: runner, notifications: notification,
                itemController: item, clock: clock
            )
            try await scheduler.setEnabled(true, developmentInterval: 2)
            let configuration = try await scheduler.configuration()
            #expect(configuration.targetInterval == 2)
            await scheduler.evaluate(reason: .development)
            #expect(await runner.count == 1)
            try await scheduler.setEnabled(false)
            clock.set(now.addingTimeInterval(100))
            await scheduler.evaluate(reason: .wakeRecovery)
            #expect(await runner.count == 1)
        }
        do {
            let database = try SQLiteDatabase(path: path)
            let state = try BackgroundPersistence(database: database).load()
            #expect(!state.enabled)
            #expect(state.lastCompletedAt == now)
        }
    }

    @Test("Overdue enabled schedule performs one compensating recovery after restart")
    func restartRecovery() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let clock = MutableStage07Clock(now)
        let database = try SQLiteDatabase(path: ":memory:")
        try BackgroundPersistence(database: database).setEnabled(true, targetInterval: 3_600, now: now)
        try database.execute(
            "UPDATE background_schedule_state SET last_completed_at=?",
            bindings: [.real(now.addingTimeInterval(-7_200).timeIntervalSince1970)]
        )
        let runner = TestScheduledRunner()
        let service = CampusNotificationService(
            database: database, center: TestNotificationCenter(state: .denied), clock: clock
        )
        let scheduler = BackgroundSyncScheduler(
            database: database, runner: runner, notifications: service,
            itemController: TestBackgroundItem(enabled: true), clock: clock
        )
        await scheduler.start()
        #expect(await runner.count == 1)
        #expect(await runner.triggers == [.recovery])
        await scheduler.signalRecovery(.wakeRecovery)
        #expect(await runner.count == 1)
        await scheduler.stop()
    }

    @Test("Offline failure keeps the schedule overdue so network recovery compensates immediately")
    func offlineRecovery() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let database = try SQLiteDatabase(path: ":memory:")
        try seedAccountAndCourse(database)
        try BackgroundPersistence(database: database).setEnabled(true, targetInterval: 3_600, now: now)
        let clock = MutableStage07Clock(now)
        let runner = TestScheduledRunner(results: [ScheduledSourceResult(
            sourceAccountID: "account", sourceName: "Synthetic", errorCategory: "offline"
        )])
        let notifications = CampusNotificationService(
            database: database, center: TestNotificationCenter(state: .denied), clock: clock
        )
        let scheduler = BackgroundSyncScheduler(
            database: database, runner: runner, notifications: notifications,
            itemController: TestBackgroundItem(enabled: true), clock: clock
        )
        await scheduler.evaluate(reason: .launchRecovery)
        #expect(try BackgroundPersistence(database: database).load().lastCompletedAt == nil)
        await runner.setResults([])
        clock.set(now.addingTimeInterval(10))
        await scheduler.signalRecovery(.networkRecovery)
        #expect(await runner.count == 2)
        #expect(try BackgroundPersistence(database: database).load().lastCompletedAt == clock.now)
        await scheduler.stop()
    }

    @Test("Notification delivery identity survives database and service recreation")
    func notificationRestartDeduplication() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stage07-notification-restart-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("db.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let center = TestNotificationCenter(state: .authorized)
        do {
            let database = try SQLiteDatabase(path: path)
            try seedTask(database, due: now.addingTimeInterval(100_000))
            try enableNotifications(database, now: now)
            let service = CampusNotificationService(database: database, center: center, clock: FixedClock(now: now))
            try await service.apply([.schedule(key: "legacy", objectID: "task", at: now)])
        }
        do {
            let database = try SQLiteDatabase(path: path)
            let service = CampusNotificationService(database: database, center: center, clock: FixedClock(now: now))
            try await service.apply([.schedule(key: "legacy", objectID: "task", at: now)])
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM notification_deliveries") == 1)
        }
        #expect(await center.requests.count == 1)
    }
}

private actor TestNotificationCenter: UserNotificationCenterClient {
    var state: NotificationAuthorizationState
    let requestResult: Bool
    private(set) var requestCount = 0
    private(set) var requests: [LocalNotificationRequest] = []
    private(set) var removed: [String] = []

    init(state: NotificationAuthorizationState, requestResult: Bool = false) {
        self.state = state; self.requestResult = requestResult
    }
    func authorizationState() async -> NotificationAuthorizationState { state }
    func requestAuthorization() async throws -> Bool {
        requestCount += 1
        if requestResult { state = .authorized }
        return requestResult
    }
    func add(_ request: LocalNotificationRequest) async throws {
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
    }
    func removePending(identifiers: [String]) async {
        removed.append(contentsOf: identifiers)
        requests.removeAll { identifiers.contains($0.identifier) }
    }
    func setState(_ value: NotificationAuthorizationState) { state = value }
    func clear() { requests = [] }
}

private final class MutableStage07Clock: Clock, @unchecked Sendable {
    private var value: Date
    private let lock = NSLock()
    init(_ value: Date) { self.value = value }
    var now: Date { lock.withLock { value } }
    func set(_ value: Date) { lock.withLock { self.value = value } }
}

private actor TestScheduledRunner: ScheduledSyncRunner {
    private(set) var count = 0
    private(set) var triggers: [SyncTrigger] = []
    private var results: [ScheduledSourceResult]
    init(results: [ScheduledSourceResult] = []) { self.results = results }
    func run(trigger: SyncTrigger) async -> [ScheduledSourceResult] {
        count += 1; triggers.append(trigger); return results
    }
    func setResults(_ results: [ScheduledSourceResult]) { self.results = results }
}

private final class TestBackgroundItem: BackgroundItemControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool
    init(enabled: Bool = false) { self.enabled = enabled }
    func state() -> BackgroundItemState { lock.withLock { enabled ? .enabled : .disabled } }
    func setEnabled(_ enabled: Bool) throws { lock.withLock { self.enabled = enabled } }
}

private func enableNotifications(_ database: SQLiteDatabase, now: Date) throws {
    try NotificationPersistence(database: database).save(
        NotificationPreferences(enabled: true), now: now
    )
}

private func seedAccountAndCourse(_ database: SQLiteDatabase) throws {
    try database.execute(
        """
        INSERT OR IGNORE INTO source_accounts
          (id, source_kind, instance_url, display_name, authorization_state,
           capabilities_json, created_at, updated_at)
        VALUES ('account', 'canvas', 'https://synthetic.invalid', 'Synthetic', 'authorized', '{}', 0, 0)
        """
    )
    try database.execute(
        """
        INSERT OR IGNORE INTO courses
          (id, source_account_id, source_object_id, name, code, term, time_zone,
           source_state, first_seen_at, last_seen_at)
        VALUES ('course', 'account', 'source-course', 'Synthetic Course', 'SYN', '', 'UTC', 'active', 0, 0)
        """
    )
}

private func seedTask(
    _ database: SQLiteDatabase, id: String = "task", due: Date?,
    normalizedType: String = "assignment", reuseAccountAndCourse: Bool = false
) throws {
    if !reuseAccountAndCourse { try seedAccountAndCourse(database) }
    try database.execute(
        """
        INSERT INTO learning_tasks
          (id, source_account_id, source_object_id, course_id, title, official_type,
           normalized_type, official_due_at, official_due_time_zone, source_state,
           first_seen_at, last_seen_at)
        VALUES (?, 'account', ?, 'course', 'Synthetic item', ?, ?, ?, 'UTC', 'active', 0, 0)
        """, bindings: [
            .text(id), .text("source-\(id)"), .text(normalizedType), .text(normalizedType),
            due.map { .real($0.timeIntervalSince1970) } ?? .null
        ]
    )
}

private func seedMeeting(_ database: SQLiteDatabase, start: Date) throws {
    try seedAccountAndCourse(database)
    try database.execute(
        """
        INSERT INTO course_meetings
          (id, course_id, source_object_id, starts_at, ends_at, original_time_zone,
           location, source_state)
        VALUES ('meeting', 'course', 'source-meeting', ?, ?, 'UTC', '', 'active')
        """, bindings: [
            .real(start.timeIntervalSince1970), .real(start.addingTimeInterval(3_600).timeIntervalSince1970)
        ]
    )
}

private func seedAnnouncement(_ database: SQLiteDatabase) throws {
    try database.execute(
        """
        INSERT INTO announcements
          (id, source_account_id, source_object_id, course_id, title, published_at,
           summary, content_hash, source_state, first_seen_at, last_seen_at)
        VALUES ('announcement', 'account', 'source-announcement', 'course', 'Synthetic announcement',
          0, '', 'hash', 'active', 0, 0)
        """
    )
}

private func date(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int,
    calendar: Calendar
) -> Date {
    calendar.date(from: DateComponents(
        timeZone: calendar.timeZone, year: year, month: month, day: day,
        hour: hour, minute: minute
    ))!
}
