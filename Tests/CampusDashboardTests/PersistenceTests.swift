import Foundation
import Testing
@testable import CampusDashboard

@Suite("SQLite persistence")
struct PersistenceTests {
    @Test("An empty database migrates to every required table")
    func emptyDatabaseMigration() throws {
        try withTemporaryDatabase { database, _ in
            #expect(try database.scalarInt("PRAGMA user_version") == SQLiteDatabase.currentSchemaVersion)
            let rows = try database.query(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
            let names = Set(rows.compactMap { $0.string("name") })
            #expect(names == Set([
                "source_accounts", "raw_source_records", "courses", "course_meetings",
                "learning_tasks", "announcements", "local_user_states", "sync_runs",
                "change_records", "calendar_bindings", "notification_deliveries",
                "ai_parse_results", "outbox_work", "source_presence", "source_baselines",
                "managed_calendar_identity", "notification_preferences",
                "course_notification_preferences", "sync_notification_state",
                "background_schedule_state", "ai_settings", "ai_confirmation_audit",
                "ai_applied_values", "ai_provider_cache", "ai_provider_usage",
                "academic_signal_analyses", "academic_signals", "academic_signal_audit",
                "academic_personalization_rules", "academic_course_mappings",
                "academic_course_mapping_audit", "release_metric_events", "academic_analysis_decisions"
            ]))
            #expect(try database.scalarInt("PRAGMA foreign_keys") == 1)
        }
    }

    @Test("Migration is idempotent and rejects a newer unknown schema")
    func migrationVersionSafety() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-migration-\(UUID().uuidString)", isDirectory: true)
        let path = directory.appendingPathComponent("migration.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            _ = try SQLiteDatabase(path: path)
            _ = try SQLiteDatabase(path: path)
        }
        do {
            let database = try SQLiteDatabase(path: path, migrate: false)
            try database.execute("PRAGMA user_version = 99")
        }
        #expect(throws: DatabaseError.migration(expected: SQLiteDatabase.currentSchemaVersion, actual: 99)) {
            try SQLiteDatabase(path: path)
        }
    }

    @Test("Version 1 databases gain durable deletion-evidence state")
    func versionOneUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-v1-\(UUID().uuidString)", isDirectory: true)
        let path = directory.appendingPathComponent("migration.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let database = try SQLiteDatabase(path: path, migrate: false)
            try database.execute("CREATE TABLE source_accounts (id TEXT PRIMARY KEY)")
            try createLegacyAIParseTable(database)
            try database.execute("PRAGMA user_version = 1")
        }
        let upgraded = try SQLiteDatabase(path: path)
        #expect(try upgraded.scalarInt("PRAGMA user_version") == SQLiteDatabase.currentSchemaVersion)
        let names = try upgraded.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('source_presence', 'source_baselines')"
        )
        #expect(Set(names.compactMap { $0.string("name") }) == ["source_presence", "source_baselines"])
    }

    @Test("Version 2 databases gain conservative per-family baseline state")
    func versionTwoUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-v2-\(UUID().uuidString)", isDirectory: true)
        let path = directory.appendingPathComponent("migration.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let database = try SQLiteDatabase(path: path, migrate: false)
            try database.execute("CREATE TABLE source_accounts (id TEXT PRIMARY KEY)")
            try createLegacyAIParseTable(database)
            try database.execute("PRAGMA user_version = 2")
        }
        let upgraded = try SQLiteDatabase(path: path)
        #expect(try upgraded.scalarInt("PRAGMA user_version") == SQLiteDatabase.currentSchemaVersion)
        #expect(try upgraded.scalarInt("SELECT COUNT(*) AS value FROM source_baselines") == 0)
    }

    @Test("Version 3 databases gain managed Calendar identity without guessing a selection")
    func versionThreeUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-v3-\(UUID().uuidString)", isDirectory: true)
        let path = directory.appendingPathComponent("migration.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let database = try SQLiteDatabase(path: path, migrate: false)
            try database.execute("CREATE TABLE source_accounts (id TEXT PRIMARY KEY)")
            try createLegacyAIParseTable(database)
            try database.execute("PRAGMA user_version = 3")
        }
        let upgraded = try SQLiteDatabase(path: path)
        #expect(try upgraded.scalarInt("PRAGMA user_version") == SQLiteDatabase.currentSchemaVersion)
        #expect(try upgraded.scalarInt("SELECT COUNT(*) AS value FROM managed_calendar_identity") == 0)
    }

    @Test("Version 4 databases gain conservative notification and background defaults")
    func versionFourUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-v4-\(UUID().uuidString)", isDirectory: true)
        let path = directory.appendingPathComponent("migration.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let database = try SQLiteDatabase(path: path, migrate: false)
            try database.execute("CREATE TABLE source_accounts (id TEXT PRIMARY KEY)")
            try database.execute("CREATE TABLE courses (id TEXT PRIMARY KEY)")
            try database.execute("CREATE TABLE notification_deliveries (notification_key TEXT PRIMARY KEY, object_type TEXT, object_id TEXT, state TEXT)")
            try createLegacyAIParseTable(database)
            try database.execute("PRAGMA user_version = 4")
        }
        let upgraded = try SQLiteDatabase(path: path)
        #expect(try upgraded.scalarInt("PRAGMA user_version") == SQLiteDatabase.currentSchemaVersion)
        let notifications = try NotificationPersistence(database: upgraded).preferences()
        let background = try BackgroundPersistence(database: upgraded).load()
        #expect(!notifications.enabled)
        #expect(notifications.deadlineOffsetsMinutes == [1_440, 180, 60])
        #expect(!background.enabled)
        #expect(background.targetInterval == 3_600)
    }

    @Test("Version 6 databases gain disabled AI settings and confirmation audit")
    func versionSixUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-v6-\(UUID().uuidString)", isDirectory: true)
        let path = directory.appendingPathComponent("migration.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let database = try SQLiteDatabase(path: path, migrate: false)
            try createLegacyAIParseTable(database)
            try database.execute("PRAGMA user_version = 6")
        }
        let upgraded = try SQLiteDatabase(path: path)
        #expect(try upgraded.scalarInt("PRAGMA user_version") == SQLiteDatabase.currentSchemaVersion)
        let settings = try AIPersistence(database: upgraded).settings()
        #expect(!settings.enabled)
        #expect(settings.providerKind == .external)
        #expect(try upgraded.scalarInt("SELECT COUNT(*) AS value FROM ai_confirmation_audit") == 0)
    }

    @Test("Version 8 databases gain an off-by-default DeepSeek direct HTTPS preference")
    func versionEightUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-v8-\(UUID().uuidString)", isDirectory: true)
        let path = directory.appendingPathComponent("migration.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let database = try SQLiteDatabase(path: path, migrate: false)
            try database.execute(
                """
                CREATE TABLE ai_settings (
                  singleton_key INTEGER PRIMARY KEY, enabled INTEGER NOT NULL,
                  provider_kind TEXT NOT NULL, provider_disclosure TEXT,
                  transmitted_fields TEXT, retention_policy TEXT, consented_at REAL,
                  updated_at REAL NOT NULL, consent_version TEXT, consent_signature TEXT,
                  school_policy_confirmed INTEGER NOT NULL DEFAULT 0, provider_model TEXT,
                  per_run_request_budget INTEGER NOT NULL DEFAULT 10,
                  daily_request_budget INTEGER NOT NULL DEFAULT 50,
                  per_run_token_budget INTEGER NOT NULL DEFAULT 20000,
                  daily_token_budget INTEGER NOT NULL DEFAULT 100000
                )
                """
            )
            try database.execute(
                "INSERT INTO ai_settings(singleton_key,enabled,provider_kind,updated_at) VALUES(1,0,'external',0)"
            )
            try database.execute("PRAGMA user_version = 8")
        }
        let upgraded = try SQLiteDatabase(path: path)
        #expect(try upgraded.scalarInt("PRAGMA user_version") == SQLiteDatabase.currentSchemaVersion)
        #expect(!(try AIPersistence(database: upgraded).settings().directHTTPSForDeepSeek))
    }

    @Test("Version 9 databases gain additive academic-signal history and audit tables")
    func versionNineUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-v9-\(UUID().uuidString)", isDirectory: true)
        let path = directory.appendingPathComponent("migration.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let database = try SQLiteDatabase(path: path, migrate: false)
            try database.execute("CREATE TABLE raw_source_records(id TEXT PRIMARY KEY)")
            try database.execute("CREATE TABLE announcements(id TEXT PRIMARY KEY)")
            try database.execute("PRAGMA user_version = 9")
        }
        let upgraded = try SQLiteDatabase(path: path)
        #expect(try upgraded.scalarInt("PRAGMA user_version") == SQLiteDatabase.currentSchemaVersion)
        let names = Set(try upgraded.query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'academic_signal%'"
        ).compactMap { $0.string("name") })
        #expect(names == ["academic_signal_analyses", "academic_signals", "academic_signal_audit"])
    }

    @Test("Source account CRUD is durable")
    func sourceAccountCRUD() throws {
        try withTemporaryDatabase { database, _ in
            let repository = SQLitePersistenceRepository(database: database)
            let account = makeAccount()
            try repository.upsertSourceAccount(account)
            #expect(try repository.sourceAccounts() == [account])
            try repository.deleteSourceAccount(id: account.id)
            #expect(try repository.sourceAccounts().isEmpty)
        }
    }

    @Test("Composite source identity upserts instead of duplicating")
    func compositeUniqueness() throws {
        try withTemporaryDatabase { database, _ in
            let repository = SQLitePersistenceRepository(database: database)
            let account = try repository.upsertSourceAccount(makeAccount())
            let original = makeCourse(accountID: account.id, name: "Original title")
            let inserted = try repository.upsertCourse(original)
            var changed = makeCourse(
                id: UUID(uuidString: "20000000-0000-0000-0000-000000000099")!,
                accountID: account.id,
                name: "Changed title"
            )
            changed.lastSeenAt = Date(timeIntervalSince1970: 200)
            let updated = try repository.upsertCourse(changed)

            #expect(try repository.courses().count == 1)
            #expect(inserted.id == original.id)
            #expect(updated.id == original.id)
            #expect(updated.name == "Changed title")
            #expect(updated.firstSeenAt == original.firstSeenAt)
        }
    }

    @Test("Official, suggested, and local task state stay separate")
    func fieldSeparation() throws {
        try withTemporaryDatabase { database, _ in
            let repository = SQLitePersistenceRepository(database: database)
            let account = try repository.upsertSourceAccount(makeAccount())
            let course = try repository.upsertCourse(makeCourse(accountID: account.id))
            let task = makeTask(accountID: account.id, courseID: course.id)
            try repository.upsertLearningTask(task)
            try repository.saveLocalState(LocalUserStateRecord(
                objectType: "learning_task", objectID: task.id.uuidString, isComplete: true,
                isRead: false, isHidden: false, priority: "High",
                modifiedAt: Date(timeIntervalSince1970: 300)
            ))

            let persistedTask = try #require(repository.learningTasks().first)
            let storedLocal = try repository.localState(
                objectType: "learning_task", objectID: task.id.uuidString
            )
            let local = try #require(storedLocal)
            #expect(persistedTask.officialDueAt == task.officialDueAt)
            #expect(persistedTask.suggestedCompleteAt == task.suggestedCompleteAt)
            #expect(persistedTask.suggestionConfirmedAt == nil)
            #expect(local.isComplete)
        }
    }

    @Test("History and outbox work survive repository recreation")
    func restartPersistence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-tests-\(UUID().uuidString)", isDirectory: true)
        let path = directory.appendingPathComponent("restart.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = makeAccount()
        let outbox = makeOutbox()

        do {
            let database = try SQLiteDatabase(path: path)
            let repository = SQLitePersistenceRepository(database: database)
            try repository.upsertSourceAccount(account)
            try repository.enqueue(outbox)
        }

        do {
            let database = try SQLiteDatabase(path: path)
            let repository = SQLitePersistenceRepository(database: database)
            #expect(try repository.sourceAccounts().first?.id == account.id)
            #expect(try repository.pendingOutbox(now: Date(timeIntervalSince1970: 500)) == [outbox])

            let duplicate = OutboxWorkRecord(
                id: UUID(), kind: outbox.kind, deduplicationKey: outbox.deduplicationKey,
                objectType: outbox.objectType, objectID: outbox.objectID,
                payload: Data("different".utf8), state: "pending", attemptCount: 0,
                availableAt: outbox.availableAt, createdAt: outbox.createdAt,
                updatedAt: outbox.updatedAt, lastErrorCategory: nil
            )
            let returned = try repository.enqueue(duplicate)
            #expect(returned == outbox)
            #expect(try repository.pendingOutbox(now: Date(timeIntervalSince1970: 500)).count == 1)
        }
    }

    @MainActor
    @Test("Dashboard local state survives model recreation")
    func dashboardRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-model-\(UUID().uuidString)", isDirectory: true)
        let path = directory.appendingPathComponent("model.sqlite3").path
        defer { try? FileManager.default.removeItem(at: directory) }
        let taskID = try #require(SyntheticFixtures.populated.tasks.first?.id)

        do {
            let persistence = SQLitePersistenceRepository(database: try SQLiteDatabase(path: path))
            let model = DashboardModel(
                scenario: .populated,
                localStateRepository: SQLiteLocalStateRepository(persistence: persistence)
            )
            model.toggleTask(taskID)
            #expect(model.snapshot.tasks.first { $0.id == taskID }?.isLocallyComplete == true)
        }

        do {
            let persistence = SQLitePersistenceRepository(database: try SQLiteDatabase(path: path))
            let model = DashboardModel(
                scenario: .populated,
                localStateRepository: SQLiteLocalStateRepository(persistence: persistence)
            )
            #expect(model.snapshot.tasks.first { $0.id == taskID }?.isLocallyComplete == true)
            #expect(model.persistenceError == nil)
        }
    }

    private func withTemporaryDatabase(
        _ operation: (SQLiteDatabase, URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-db-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try SQLiteDatabase(path: directory.appendingPathComponent("test.sqlite3").path)
        try operation(database, directory)
    }

    private func createLegacyAIParseTable(_ database: SQLiteDatabase) throws {
        try database.execute(
            """
            CREATE TABLE ai_parse_results (
                id TEXT PRIMARY KEY, raw_source_record_id TEXT NOT NULL,
                input_hash TEXT NOT NULL, provider TEXT NOT NULL, model TEXT NOT NULL,
                prompt_version TEXT NOT NULL, schema_version TEXT NOT NULL,
                suggested_type TEXT, normalized_title TEXT, official_date_echo REAL,
                suggested_date REAL, confidence REAL NOT NULL, rationale TEXT NOT NULL,
                has_conflict INTEGER NOT NULL DEFAULT 0,
                confirmation_state TEXT NOT NULL, created_at REAL NOT NULL
            )
            """
        )
    }

    private func makeAccount() -> SourceAccountRecord {
        SourceAccountRecord(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, kind: .canvas,
            instanceURL: "https://canvas.invalid", displayName: "Synthetic Canvas",
            authorizationState: "disconnected", capabilitiesJSON: "{}", lastSuccessfulSync: nil,
            createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func makeCourse(
        id: UUID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
        accountID: UUID,
        name: String = "Synthetic Course"
    ) -> PersistedCourse {
        PersistedCourse(
            id: id, sourceAccountID: accountID, sourceObjectID: "course-1", name: name,
            code: "SYN-1", term: "Synthetic term", timeZone: "UTC", sourceURL: nil,
            sourceState: "active", firstSeenAt: Date(timeIntervalSince1970: 100),
            lastSeenAt: Date(timeIntervalSince1970: 100), sourceUpdatedAt: nil
        )
    }

    private func makeTask(accountID: UUID, courseID: UUID) -> PersistedLearningTask {
        PersistedLearningTask(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            sourceAccountID: accountID, sourceObjectID: "task-1", courseID: courseID,
            title: "Synthetic task", officialType: "assignment", normalizedType: "reading",
            officialDueAt: Date(timeIntervalSince1970: 1_000), officialDueTimeZone: "UTC",
            officialDueIsAllDay: false, suggestedCompleteAt: Date(timeIntervalSince1970: 900),
            suggestionOrigin: "ai", suggestionConfirmedAt: nil, sourceState: "active",
            firstSeenAt: Date(timeIntervalSince1970: 100), lastSeenAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func makeOutbox() -> OutboxWorkRecord {
        OutboxWorkRecord(
            id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!, kind: "calendar.upsert",
            deduplicationKey: "synthetic-dedupe-1", objectType: "learning_task", objectID: "task-1",
            payload: Data("{}".utf8), state: "pending", attemptCount: 0,
            availableAt: Date(timeIntervalSince1970: 100), createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100), lastErrorCategory: nil
        )
    }
}
