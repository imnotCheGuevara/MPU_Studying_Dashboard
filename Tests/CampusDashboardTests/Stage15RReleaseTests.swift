import Foundation
import Testing
@testable import CampusDashboard

@Suite("Stage 15R release readiness")
struct Stage15RReleaseTests {
    @Test("Outlook stays dormant in the release dependency graph")
    func outlookDormancy() {
        #expect(!AppEnvironment.outlookEnabledInRelease)
    }

    @Test("First-run checklist is persistent and Keychain-backed sources are isolated")
    func setupChecklist() throws {
        try withReleaseService { service, canvasSecrets, siwebSecrets, defaults, _ in
            #expect(service.shouldPresentFirstRun())
            service.markFirstRunPresented()
            #expect(!service.shouldPresentFirstRun())

            var items = service.sourceSetupItems(
                calendarReady: true, notificationsReady: false, deepSeekReady: false
            )
            #expect(items.count == ReleaseSetupIntegration.allCases.count)
            #expect(items.first(where: { $0.integration == .canvas })?.isComplete == false)
            #expect(items.first(where: { $0.integration == .calendar })?.isComplete == true)
            #expect(items.allSatisfy { !$0.minimumData.isEmpty })

            try service.configureCanvas(baseURL: "https://canvas.example.edu", token: "synthetic-token")
            items = service.sourceSetupItems(
                calendarReady: true, notificationsReady: false, deepSeekReady: false
            )
            #expect(items.first(where: { $0.integration == .canvas })?.isComplete == true)
            #expect(try canvasSecrets.data(account: CanvasConfiguration.tokenAccount) == Data("synthetic-token".utf8))
            #expect(throws: SecretStoreError.notFound) {
                try siwebSecrets.data(account: SIwebConfiguration.sessionAccount)
            }

            try service.revokeCanvas()
            #expect(throws: SecretStoreError.notFound) {
                try canvasSecrets.data(account: CanvasConfiguration.tokenAccount)
            }
            #expect(defaults.bool(forKey: "Stage15RSetupAssistantPresented"))
        }
    }

    @Test("Every required recovery is actionable and reports unaffected features")
    func recoveryTaxonomy() {
        #expect(RecoveryCategory.allCases.count == 9)
        #expect(RecoveryCategory.allCases.allSatisfy {
            !$0.recoveryAction.isEmpty && !$0.unaffectedFeatures.isEmpty
        })
        let sourceCategories: [SourceHealthCategory] = [
            .authorizationRequired, .notConfigured, .offline, .rateLimited,
            .cancelled, .sourceChanged
        ]
        let sources = sourceCategories.enumerated().map {
            DiagnosticSourceHealth(source: "source-\($0.offset)", category: $0.element,
                                   lastSuccessfulSync: nil, message: "Safe summary",
                                   recoveryAction: "Retry")
        }
        let recoveries = ReleaseReadinessService.recoveries(
            sources: sources, calendar: .denied, notifications: .denied,
            aiFailureCategories: ["budget_exceeded", "schema_validation"]
        )
        let categories = Set(recoveries.map(\.category))
        #expect(categories.contains(.authenticationExpired))
        #expect(categories.contains(.missingConsentOrKey))
        #expect(categories.contains(.networkOrExactHost))
        #expect(categories.contains(.httpOrRateLimit))
        #expect(categories.contains(.timeout))
        #expect(categories.contains(.schemaOrDecoding))
        #expect(categories.contains(.budget))
        #expect(categories.contains(.calendarPermission))
        #expect(categories.contains(.notificationPermission))
    }

    @Test("Release setup, recovery, review, and preview labels are bilingual")
    func bilingualReleaseSurfaces() {
        let keys = [
            "Release setup checklist", "Authorize or reauthorize SIweb in app",
            "Paused for school-policy review", "Recovery center", "Authentication expired",
            "Missing consent or Keychain item", "Network or exact-host route", "HTTP or rate limit",
            "Timeout", "Schema or decoding", "Local AI budget", "Calendar permission",
            "Notification permission", "Other / no actionable result", "Provider fallback",
            "Calendar written", "Ignore", "Undo", "Reset", "Calendar change preview",
            "Confirm and allow Calendar reconciliation", "Exam or Quiz"
        ]
        for key in keys {
            #expect(Localizer.text(key, language: .simplifiedChinese) != key)
        }
    }

    @Test("Ignored analysis decisions and observed timing are local and reversible")
    func reversibleLocalDecisionsAndMetrics() throws {
        try withReleaseService { service, _, _, _, database in
            try seedAnalysis(database, id: "10000000-0000-0000-0000-000000000001")
            let id = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
            try service.setAnalysisIgnored(id, ignored: true)
            #expect(try service.ignoredAnalysisIDs() == [id])
            try service.setAnalysisIgnored(id, ignored: false)
            #expect(try service.ignoredAnalysisIDs().isEmpty)

            try service.recordHandlingDuration(12.5, action: "confirm")
            try service.recordHandlingDuration(-1, action: "invalid")
            let metrics = try service.outcomeMetrics()
            #expect(metrics.observedHandlingSamples == 1)
            #expect(metrics.averageHandlingSeconds == 12.5)
            #expect(metrics.unsafeCalendarBindings == 0)
            #expect(metrics.duplicateNotificationKeys == 0)
        }
    }

    private func withReleaseService(
        _ operation: (ReleaseReadinessService, FakeSecretStore, FakeSecretStore, UserDefaults, SQLiteDatabase) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("campus-dashboard-stage15r-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try SQLiteDatabase(path: directory.appendingPathComponent("test.sqlite3").path)
        let suite = "CampusDashboard.Stage15R.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let canvasSecrets = FakeSecretStore()
        let siwebSecrets = FakeSecretStore()
        let service = ReleaseReadinessService(
            database: database,
            canvasConfigurations: UserDefaultsCanvasConfigurationStore(defaults: defaults),
            canvasSecrets: canvasSecrets,
            siwebConfigurations: UserDefaultsSIwebConfigurationStore(defaults: defaults),
            siwebSecrets: siwebSecrets,
            defaults: defaults
        )
        try operation(service, canvasSecrets, siwebSecrets, defaults, database)
    }

    private func seedAnalysis(_ database: SQLiteDatabase, id: String) throws {
        try database.execute(
            "INSERT INTO source_accounts(id,source_kind,instance_url,display_name,authorization_state,created_at,updated_at) VALUES('account','canvas','https://canvas.example.edu','Synthetic','ready',1,1)"
        )
        try database.execute(
            "INSERT INTO raw_source_records(id,source_account_id,object_type,source_object_id,fetch_batch_id,content_hash,payload,fetched_at) VALUES('raw','account','announcement','announcement-source','batch','hash',X'7B7D',1)"
        )
        try database.execute(
            "INSERT INTO announcements(id,source_account_id,source_object_id,title,published_at,summary,content_hash,source_state,first_seen_at,last_seen_at) VALUES('announcement','account','announcement-source','Synthetic',1,'Synthetic','hash','active',1,1)"
        )
        try database.execute(
            "INSERT INTO academic_signal_analyses(id,raw_source_record_id,announcement_id,source_account_id,source_object_id,content_hash,primary_category,status,provider,model,prompt_version,schema_version,created_at,updated_at) VALUES(?,'raw','announcement','account','announcement-source','hash','other','analyzed','deterministic','local','v1','v1',1,1)",
            bindings: [.text(id)]
        )
    }
}
