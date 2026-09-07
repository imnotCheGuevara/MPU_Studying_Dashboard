import Foundation
import Testing
@testable import CampusDashboard

@Suite("Stage 09 privacy, diagnostics, and cleanup")
struct PrivacyDiagnosticsTests {
    @Test("A later successful sync labels retained errors as historical recovery")
    func historicalRecoveryIsNotCurrentFailure() throws {
        let database = try SQLiteDatabase(path: ":memory:")
        try database.execute(
            "INSERT INTO source_accounts(id,source_kind,instance_url,display_name,authorization_state,last_successful_sync,created_at,updated_at) VALUES('account-id','Canvas','https://fixture.invalid','Canvas','authorized',20,1,20)"
        )
        try database.execute(
            "INSERT INTO sync_runs(id,trigger_kind,source_account_id,fetch_state,normalize_state,persistence_state,started_at,finished_at,error_category) VALUES('old-failure','manual','account-id','failed','not_started','not_started',9,10,'offline')"
        )
        let health = try #require(PrivacyDiagnosticsService(database: database).sourceHealth().first {
            $0.source == SourceKind.canvas.rawValue
        })
        #expect(health.category == .ready)
        #expect(health.message == "Ready. A previous issue was recovered.")
        #expect(health.recoveryAction.contains("Historical recovery"))
        #expect(ReleaseReadinessService.recoveries(
            sources: [health], calendar: .fullAccess, notifications: .authorized,
            aiFailureCategories: []
        ).isEmpty)
        #expect(try database.scalarInt("SELECT COUNT(*) FROM sync_runs") == 1)
    }

    @Test("Every local-data category preserves credentials and Calendar bindings")
    func categoryClearingIsIndependent() throws {
        for category in LocalDataCategory.allCases {
            let database = try SQLiteDatabase(path: ":memory:")
            try seedPrivacyData(database)
            let secrets = FakeSecretStore()
            try secrets.set(Data("synthetic-secret-marker".utf8), account: "credential")
            let service = PrivacyDiagnosticsService(
                database: database,
                credentialTargets: [CredentialTarget(store: secrets, account: "credential")]
            )

            _ = try service.clear(category)

            #expect(try secrets.data(account: "credential") == Data("synthetic-secret-marker".utf8))
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM calendar_bindings") == 1)
            #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM managed_calendar_identity") == 1)
            if category == .sourceCache {
                #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM outbox_work") == 0)
            }
        }
    }

    @Test("Credential clearing is independent from cached data and Calendar state")
    func credentialClearingIsIndependent() throws {
        let database = try SQLiteDatabase(path: ":memory:")
        try seedPrivacyData(database)
        let canvas = FakeSecretStore()
        let siweb = FakeSecretStore()
        try canvas.set(Data("synthetic-canvas-secret".utf8), account: "canvas")
        try siweb.set(Data("synthetic-session-secret".utf8), account: "siweb")
        let service = PrivacyDiagnosticsService(database: database, credentialTargets: [
            CredentialTarget(store: canvas, account: "canvas"),
            CredentialTarget(store: siweb, account: "siweb")
        ])

        try service.clearCredentials()

        #expect(throws: SecretStoreError.notFound) { try canvas.data(account: "canvas") }
        #expect(throws: SecretStoreError.notFound) { try siweb.data(account: "siweb") }
        #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM learning_tasks") == 1)
        #expect(try database.scalarInt("SELECT COUNT(*) AS value FROM calendar_bindings") == 1)
    }

    @Test("Diagnostic export is allowlisted and excludes secrets, URLs, identifiers, and content")
    func diagnosticsAreRedacted() throws {
        let database = try SQLiteDatabase(path: ":memory:")
        try seedPrivacyData(database)
        let authorizationProbe = "Bearer " + "synthetic-secret-marker"
        let forbidden = [
            "synthetic-secret-marker", "synthetic-session-marker", "private-student-title",
            "https://private.invalid/path", authorizationProbe
        ]
        try database.execute(
            "UPDATE source_accounts SET instance_url=?, display_name=?",
            bindings: [.text(forbidden[3]), .text("private-student-title")]
        )
        try database.execute(
            "UPDATE sync_runs SET redacted_error_summary=?",
            bindings: [.text(authorizationProbe + " synthetic-session-marker")]
        )
        try database.execute(
            "UPDATE learning_tasks SET title='private-student-title', source_url=?",
            bindings: [.text(forbidden[3])]
        )
        let service = PrivacyDiagnosticsService(
            database: database, clock: FixedPrivacyClock(Date(timeIntervalSince1970: 2_000))
        )
        let data = try service.encodedDiagnosticSnapshot(subsystems: [
            SubsystemHealth(
                subsystem: "calendar", category: "denied",
                recoveryAction: authorizationProbe + " synthetic-session-marker"
            ),
            SubsystemHealth(
                subsystem: "synthetic-secret-marker", category: "synthetic-session-marker",
                recoveryAction: "private-student-title"
            )
        ])
        let text = String(decoding: data, as: UTF8.self)

        for marker in forbidden { #expect(!text.contains(marker)) }
        #expect(!text.contains("account-id"))
        #expect(!text.contains("task-id"))
        #expect(text.contains("permission_denied"))
        #expect(text.contains("aggregateCounts"))
    }

    @Test("Source failures are categorized with actionable, redacted recovery guidance")
    func actionableSourceHealth() throws {
        let database = try SQLiteDatabase(path: ":memory:")
        try seedPrivacyData(database)
        try database.execute("UPDATE sync_runs SET error_category='offline'")
        let health = try PrivacyDiagnosticsService(database: database).sourceHealth()
        let canvas = try #require(health.first { $0.source == SourceKind.canvas.rawValue })
        let siweb = try #require(health.first { $0.source == SourceKind.siweb.rawValue })
        #expect(canvas.category == .offline)
        #expect(canvas.recoveryAction.contains("network"))
        #expect(siweb.category == .notConfigured)
        #expect(!canvas.message.contains("private"))
    }

    @Test("Diagnostic generation stays responsive with a large local history")
    func diagnosticPerformance() throws {
        let database = try SQLiteDatabase(path: ":memory:")
        try seedPrivacyData(database)
        try database.transaction {
            for index in 0..<5_000 {
                try database.execute(
                    """
                    INSERT INTO sync_runs(id, trigger_kind, source_account_id, fetch_state,
                      normalize_state, persistence_state, started_at, error_category,
                      redacted_error_summary)
                    VALUES (?, 'scheduled', 'account-id', 'failed', 'not_started', 'not_started', ?,
                      'offline', 'offline')
                    """,
                    bindings: [.text("history-\(index)"), .real(Double(index + 10))]
                )
            }
        }
        let service = PrivacyDiagnosticsService(database: database)
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            _ = try service.encodedDiagnosticSnapshot(subsystems: [])
        }
        #expect(elapsed < .seconds(2))
    }

    private func seedPrivacyData(_ database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT INTO source_accounts
              (id, source_kind, instance_url, display_name, authorization_state,
               last_successful_sync, created_at, updated_at)
            VALUES ('account-id', 'Canvas', 'https://fixture.invalid', 'Synthetic', 'connected', 1, 1, 1)
            """
        )
        try database.execute(
            """
            INSERT INTO outbox_work
              (id, kind, deduplication_key, object_type, object_id, payload, state,
               available_at, created_at, updated_at)
            VALUES ('work-id', 'calendar.remove', 'work-key', 'learning_task', 'task-id',
              X'7B7D', 'pending', 1, 1, 1)
            """
        )
        try database.execute(
            """
            INSERT INTO courses
              (id, source_account_id, source_object_id, name, code, term, time_zone,
               source_state, first_seen_at, last_seen_at)
            VALUES ('course-id', 'account-id', 'course-source', 'Synthetic Course', 'SYN', 'Term',
              'UTC', 'active', 1, 1)
            """
        )
        try database.execute(
            """
            INSERT INTO learning_tasks
              (id, source_account_id, source_object_id, course_id, title, official_type,
               official_due_at, source_state, first_seen_at, last_seen_at)
            VALUES ('task-id', 'account-id', 'task-source', 'course-id', 'Synthetic Task',
              'assignment', 10000, 'active', 1, 1)
            """
        )
        try database.execute(
            """
            INSERT INTO local_user_states(object_type, object_id, modified_at)
            VALUES ('learning_task', 'task-id', 1)
            """
        )
        try database.execute(
            """
            INSERT INTO sync_runs
              (id, trigger_kind, source_account_id, fetch_state, normalize_state,
               persistence_state, started_at, error_category, redacted_error_summary)
            VALUES ('run-id', 'manual', 'account-id', 'failed', 'not_started', 'not_started', 1,
              'forbidden', 'forbidden')
            """
        )
        try database.execute(
            """
            INSERT INTO managed_calendar_identity
              (singleton_key, internal_id, calendar_identifier, source_identifier, source_kind,
               source_title, calendar_title, selection_kind, ownership_marker, validation_state)
            VALUES (1, '00000000-0000-0000-0000-000000000099', 'dedicated', 'source', 'iCloud',
              'iCloud', 'Campus Dashboard', 'app_created', 'calendar-marker', 'valid')
            """
        )
        try database.execute(
            """
            INSERT INTO calendar_bindings
              (id, object_type, object_id, event_identifier, external_event_identifier,
               ownership_marker, calendar_identifier, calendar_source_identifier, sync_state)
            VALUES ('00000000-0000-0000-0000-000000000100', 'learning_task', 'task-id',
              'event-id', 'external-id', 'event-marker', 'dedicated', 'source', 'synced')
            """
        )
    }
}

private struct FixedPrivacyClock: Clock {
    let now: Date
    init(_ now: Date) { self.now = now }
}
