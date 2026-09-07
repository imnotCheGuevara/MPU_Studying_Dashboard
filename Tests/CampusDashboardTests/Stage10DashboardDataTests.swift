import Foundation
import Testing
@testable import CampusDashboard

@MainActor
@Suite("Stage 10 production dashboard data")
struct Stage10DashboardDataTests {
    @Test("Seeded unified SQLite data maps to a DashboardSnapshot with local state")
    func seededDatabaseMapsToSnapshot() throws {
        let database = try SQLiteDatabase(path: ":memory:")
        try seedDashboard(database)

        let snapshot = try SQLiteDashboardDataReader(database: database).loadSnapshot()

        #expect(snapshot.courses.count == 1)
        #expect(snapshot.meetings.count == 1)
        #expect(snapshot.tasks.count == 1)
        #expect(snapshot.announcements.count == 1)
        #expect(snapshot.confirmations.isEmpty)
        #expect(snapshot.tasks[0].isLocallyComplete)
        #expect(snapshot.tasks[0].localPriority == .high)
        #expect(snapshot.announcements[0].isLocallyRead)
        #expect(snapshot.courses[0].sourceURL == "https://source.invalid/course")
        #expect(snapshot.meetings[0].sourceURL == "https://source.invalid/course")
        #expect(snapshot.tasks[0].sourceURL == "https://source.invalid/task")
        #expect(snapshot.announcements[0].sourceURL == "https://source.invalid/announcement")
        #expect(snapshot.courses.allSatisfy { !$0.sourceObjectID.hasPrefix("synthetic-") })
    }

    @Test("Production model reloads persisted data after recreation")
    func persistedDataSurvivesModelRecreation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stage10-dashboard-restart-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("dashboard.sqlite3").path
        try seedDashboard(SQLiteDatabase(path: path))

        let firstDatabase = try SQLiteDatabase(path: path)
        let first = DashboardModel(dataReader: SQLiteDashboardDataReader(database: firstDatabase))
        await first.startRuntimeServices()
        let firstIDs = first.snapshot.tasks.map(\.id)

        let secondDatabase = try SQLiteDatabase(path: path)
        let second = DashboardModel(dataReader: SQLiteDashboardDataReader(database: secondDatabase))
        await second.startRuntimeServices()

        #expect(second.snapshot.tasks.map(\.id) == firstIDs)
        #expect(second.snapshot.tasks.first?.title == "Database task")
        #expect(!second.isPreviewMode)
    }

    @Test("Completed background synchronization reloads the production snapshot")
    func backgroundCompletionReloadsSnapshot() async throws {
        let database = try SQLiteDatabase(path: ":memory:")
        try seedDashboard(database)
        let runner = Stage10MutatingRunner(database: database)
        let notifications = CampusNotificationService(
            database: database, center: Stage10NoopNotificationCenter()
        )
        let scheduler = BackgroundSyncScheduler(
            database: database, runner: runner, notifications: notifications,
            itemController: Stage10BackgroundItemController()
        )
        let model = DashboardModel(
            dataReader: SQLiteDashboardDataReader(database: database),
            backgroundScheduler: scheduler
        )
        await model.startRuntimeServices()
        try await scheduler.setEnabled(true, developmentInterval: 3_600)

        await scheduler.evaluate(reason: .development)

        #expect(model.snapshot.tasks.contains { $0.title == "Updated database task" })
        #expect(model.snapshot.tasks.contains { $0.title == "New database task" })
        await scheduler.stop()
    }

    @Test("Manual refresh waits for an active background run and then executes")
    func manualRefreshQueuesBehindBackgroundRun() async throws {
        let database = try SQLiteDatabase(path: ":memory:")
        let runner = Stage10BlockingRunner()
        let notifications = CampusNotificationService(
            database: database, center: Stage10NoopNotificationCenter()
        )
        let scheduler = BackgroundSyncScheduler(
            database: database, runner: runner, notifications: notifications,
            itemController: Stage10BackgroundItemController()
        )
        try await scheduler.setEnabled(true, developmentInterval: 3_600)
        let background = Task { await scheduler.evaluate(reason: .development) }
        await runner.waitUntilFirstStarted()
        let manual = Task { await scheduler.runManual() }
        await Task.yield()

        await runner.releaseFirst()
        await background.value
        _ = await manual.value

        #expect(await runner.triggers == [.scheduled, .manual])
        await scheduler.stop()
    }

    @Test("Configured source failure produces real health and empty data without fixtures")
    func sourceFailureUsesRealEmptyState() throws {
        let database = try SQLiteDatabase(path: ":memory:")
        try database.execute(
            """
            INSERT INTO source_accounts
              (id,source_kind,instance_url,display_name,authorization_state,created_at,updated_at)
            VALUES ('20000000-0000-0000-0000-000000000001','Canvas','https://canvas.invalid',
                    'Canvas','authorized',1,1)
            """
        )
        try database.execute(
            """
            INSERT INTO sync_runs
              (id,trigger_kind,source_account_id,fetch_state,normalize_state,persistence_state,
               started_at,finished_at,error_category,redacted_error_summary)
            VALUES ('20000000-0000-0000-0000-000000000002','manual',
                    '20000000-0000-0000-0000-000000000001','failed','not_started','not_started',
                    2,2,'offline','offline')
            """
        )

        let snapshot = try SQLiteDashboardDataReader(database: database).loadSnapshot()

        #expect(snapshot.courses.isEmpty)
        #expect(snapshot.tasks.isEmpty)
        #expect(snapshot.sourceHealth.count == 1)
        #expect(snapshot.sourceHealth[0].source == .canvas)
        #expect(snapshot.sourceHealth[0].level == .warning)
        #expect(!snapshot.sourceHealth[0].detail.localizedCaseInsensitiveContains("synthetic"))
    }

    @Test("Manual refresh commits additions updates and cancellation before reloading")
    func manualRefreshReloadsCommittedChanges() async throws {
        let database = try SQLiteDatabase(path: ":memory:")
        try seedDashboard(database)
        let runner = Stage10MutatingRunner(database: database)
        let notifications = CampusNotificationService(
            database: database, center: Stage10NoopNotificationCenter()
        )
        let scheduler = BackgroundSyncScheduler(
            database: database, runner: runner, notifications: notifications,
            itemController: Stage10BackgroundItemController()
        )
        let model = DashboardModel(
            dataReader: SQLiteDashboardDataReader(database: database),
            backgroundScheduler: scheduler
        )
        await model.startRuntimeServices()
        let stableID = try #require(model.snapshot.tasks.first?.id)

        await model.refresh()
        #expect(model.snapshot.tasks.first { $0.id == stableID }?.title == "Updated database task")
        #expect(model.snapshot.tasks.contains { $0.title == "New database task" })

        await model.refresh()
        #expect(!model.snapshot.tasks.contains { $0.id == stableID })
        #expect(model.snapshot.tasks.count == 1)
        #expect(model.refreshCount == 2)
    }

    @Test("Empty production database and default model never load fixtures")
    func emptyProductionDoesNotUseFixtures() async throws {
        let database = try SQLiteDatabase(path: ":memory:")
        let model = DashboardModel(dataReader: SQLiteDashboardDataReader(database: database))
        await model.reloadDashboardData()

        #expect(model.snapshot == .empty)
        #expect(!model.isPreviewMode)
        #expect(model.scenarioForEmpty(true) == .empty)
        #expect(DashboardModel().snapshot == .empty)
    }

    @Test("Current-day filtering uses injected local now instead of fixture reference date")
    func currentDateDoesNotUseFixtureReference() throws {
        let localNow = Date(timeIntervalSince1970: 1_900_000_000)
        let otherDay = SyntheticFixtures.referenceDate
        let course = Course(
            id: UUID(), sourceAccountID: "account", sourceObjectID: "real-course",
            name: "Current course", code: "NOW", term: "", colorName: "blue"
        )
        let currentTask = task(id: UUID(), courseID: course.id, title: "Current", due: localNow)
        let fixtureDayTask = task(id: UUID(), courseID: course.id, title: "Fixture", due: otherDay)
        let snapshot = DashboardSnapshot(
            sourceHealth: [], courses: [course], meetings: [],
            tasks: [currentTask, fixtureDayTask], announcements: [], confirmations: []
        )
        let model = DashboardModel(snapshot: snapshot, now: { localNow })

        #expect(model.dueToday.map(\.id) == [currentTask.id])
        #expect(model.dueToday.allSatisfy { $0.officialDueAt != SyntheticFixtures.referenceDate })
    }

    private func task(id: UUID, courseID: UUID, title: String, due: Date) -> LearningTask {
        LearningTask(
            id: id, sourceAccountID: "account", sourceObjectID: id.uuidString,
            courseID: courseID, title: title, kind: .assignment,
            officialDueAt: due, suggestedCompleteAt: nil, suggestedDateConfirmed: false,
            source: .canvas, isLocallyComplete: false, localPriority: .medium
        )
    }

    private func seedDashboard(_ database: SQLiteDatabase) throws {
        let due = Date().addingTimeInterval(86_400).timeIntervalSince1970
        try database.execute(
            """
            INSERT INTO source_accounts
              (id,source_kind,instance_url,display_name,authorization_state,last_successful_sync,created_at,updated_at)
            VALUES ('10000000-0000-0000-0000-000000000001','Canvas','https://canvas.invalid','Canvas','authorized',1,1,1)
            """
        )
        try database.execute(
            """
            INSERT INTO courses
              (id,source_account_id,source_object_id,name,code,term,time_zone,source_url,source_state,first_seen_at,last_seen_at)
            VALUES ('10000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',
                    'course-real','Database course','DB101','Term','UTC','https://source.invalid/course','active',1,1)
            """
        )
        try database.execute(
            """
            INSERT INTO course_meetings
              (id,course_id,source_object_id,starts_at,ends_at,original_time_zone,location,source_state)
            VALUES ('10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002',
                    'meeting-real',?,?, 'UTC','Room','active')
            """,
            bindings: [.real(due), .real(due + 3_600)]
        )
        try database.execute(
            """
            INSERT INTO learning_tasks
              (id,source_account_id,source_object_id,course_id,title,official_type,normalized_type,
               official_due_at,source_url,source_state,first_seen_at,last_seen_at)
            VALUES ('10000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001',
                    'task-real','10000000-0000-0000-0000-000000000002','Database task','assignment',
                    'assignment',?,'https://source.invalid/task','active',1,1)
            """,
            bindings: [.real(due)]
        )
        try database.execute(
            """
            INSERT INTO announcements
              (id,source_account_id,source_object_id,course_id,title,published_at,summary,content_hash,
               source_url,source_state,first_seen_at,last_seen_at)
            VALUES ('10000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001',
                    'announcement-real','10000000-0000-0000-0000-000000000002','Database announcement',
                    1,'Database summary','hash','https://source.invalid/announcement','active',1,1)
            """
        )
        try database.execute(
            """
            INSERT INTO local_user_states(object_type,object_id,is_complete,is_read,is_hidden,priority,modified_at)
            VALUES ('learning_task','10000000-0000-0000-0000-000000000004',1,0,0,'High',1),
                   ('announcement','10000000-0000-0000-0000-000000000005',0,1,0,NULL,1)
            """
        )
    }
}

private actor Stage10MutatingRunner: ScheduledSyncRunner {
    private let database: SQLiteDatabase
    private var runCount = 0

    init(database: SQLiteDatabase) { self.database = database }

    func run(trigger: SyncTrigger) async -> [ScheduledSourceResult] {
        runCount += 1
        do {
            if runCount == 1 {
                try database.execute(
                    "UPDATE learning_tasks SET title='Updated database task' WHERE id='10000000-0000-0000-0000-000000000004'"
                )
                try database.execute(
                    """
                    INSERT INTO learning_tasks
                      (id,source_account_id,source_object_id,course_id,title,official_type,normalized_type,
                       official_due_at,source_state,first_seen_at,last_seen_at)
                    SELECT '10000000-0000-0000-0000-000000000006',source_account_id,'task-new',course_id,
                           'New database task','assignment','assignment',official_due_at,'active',1,1
                    FROM learning_tasks WHERE id='10000000-0000-0000-0000-000000000004'
                    """
                )
            } else {
                try database.execute(
                    "UPDATE learning_tasks SET source_state='cancelled' WHERE id='10000000-0000-0000-0000-000000000004'"
                )
            }
            return [ScheduledSourceResult(sourceAccountID: "account", sourceName: "Canvas", errorCategory: nil)]
        } catch {
            return [ScheduledSourceResult(sourceAccountID: "account", sourceName: "Canvas", errorCategory: "persistence")]
        }
    }
}

private actor Stage10BlockingRunner: ScheduledSyncRunner {
    private(set) var triggers: [SyncTrigger] = []
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func run(trigger: SyncTrigger) async -> [ScheduledSourceResult] {
        triggers.append(trigger)
        if triggers.count == 1 {
            started = true
            let waiters = startedWaiters
            startedWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        return []
    }

    func waitUntilFirstStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func releaseFirst() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor Stage10NoopNotificationCenter: UserNotificationCenterClient {
    func authorizationState() -> NotificationAuthorizationState { .denied }
    func requestAuthorization() throws -> Bool { false }
    func add(_ request: LocalNotificationRequest) throws {}
    func removePending(identifiers: [String]) {}
}

private struct Stage10BackgroundItemController: BackgroundItemControlling {
    func state() -> BackgroundItemState { .disabled }
    func setEnabled(_ enabled: Bool) throws {}
}
