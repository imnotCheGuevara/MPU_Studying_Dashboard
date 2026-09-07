import Foundation

struct CredentialTarget: Sendable {
    let store: any SecretStore
    let account: String
}

final class PrivacyDiagnosticsService: @unchecked Sendable {
    private let database: SQLiteDatabase
    private let credentialTargets: [CredentialTarget]
    private let clock: any Clock

    init(
        database: SQLiteDatabase,
        credentialTargets: [CredentialTarget] = [],
        clock: any Clock = SystemClock()
    ) {
        self.database = database
        self.credentialTargets = credentialTargets
        self.clock = clock
    }

    func sourceHealth() throws -> [DiagnosticSourceHealth] {
        let rows = try database.query(
            """
            SELECT a.source_kind, a.authorization_state, a.last_successful_sync,
              (SELECT r.error_category FROM sync_runs r WHERE r.source_account_id=a.id
               ORDER BY r.started_at DESC LIMIT 1) AS latest_error,
              (SELECT COALESCE(r.finished_at,r.started_at) FROM sync_runs r WHERE r.source_account_id=a.id
               ORDER BY r.started_at DESC LIMIT 1) AS latest_attempt_at
            FROM source_accounts a ORDER BY a.source_kind
            """
        )
        var health = rows.compactMap(decodeSourceHealth)
        for source in SourceKind.allCases.map(\.rawValue) where !health.contains(where: { $0.source == source }) {
            health.append(DiagnosticSourceHealth(
                source: source, category: .notConfigured, lastSuccessfulSync: nil,
                message: "Not configured.", recoveryAction: "Configure this source before synchronizing."
            ))
        }
        return health.sorted { $0.source < $1.source }
    }

    func diagnosticSnapshot(subsystems: [SubsystemHealth]) throws -> DiagnosticSnapshot {
        DiagnosticSnapshot(
            formatVersion: 2,
            generatedAt: clock.now,
            databaseSchemaVersion: SQLiteDatabase.currentSchemaVersion,
            sources: try sourceHealth(),
            subsystems: sanitizedSubsystems(subsystems),
            aggregateCounts: try aggregateCounts(),
            deepSeekDirectHTTPS: try deepSeekDirectHTTPS()
        )
    }

    private func deepSeekDirectHTTPS() throws -> Bool {
        try database.query("SELECT deepseek_direct_https FROM ai_settings WHERE singleton_key=1")
            .first?.int("deepseek_direct_https") == 1
    }

    func encodedDiagnosticSnapshot(subsystems: [SubsystemHealth]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(diagnosticSnapshot(subsystems: subsystems))
    }

    func exportDiagnostics(to url: URL, subsystems: [SubsystemHealth]) throws {
        guard url.isFileURL else { throw PrivacyDiagnosticsError.invalidExportLocation }
        do {
            try encodedDiagnosticSnapshot(subsystems: subsystems).write(to: url, options: .atomic)
        } catch let error as PrivacyDiagnosticsError {
            throw error
        } catch {
            throw PrivacyDiagnosticsError.diagnosticExportFailed
        }
    }

    @discardableResult
    func clear(_ category: LocalDataCategory) throws -> LocalDataClearResult {
        let before = try rowCount(for: category)
        try database.transaction {
            switch category {
            case .sourceCache:
                // Bindings deliberately survive so Calendar cleanup remains a separate,
                // previewable user action even after cached source content is removed.
                // Pending side-effect intents are local cache too; dropping them prevents
                // a previously queued Calendar mutation from running after this action.
                for table in ["outbox_work", "source_presence", "source_baselines", "raw_source_records",
                              "course_meetings", "announcements", "learning_tasks", "courses"] {
                    try database.execute("DELETE FROM \(table)")
                }
            case .localUserState:
                try database.execute("DELETE FROM local_user_states")
            case .syncHistory:
                try database.execute("DELETE FROM change_records")
                try database.execute("DELETE FROM sync_runs")
                try database.execute("DELETE FROM release_metric_events")
            case .aiHistory:
                try database.execute("DELETE FROM academic_signal_analyses")
                try database.execute("DELETE FROM ai_parse_results")
                try database.execute("DELETE FROM ai_provider_cache")
            case .notificationHistory:
                try database.execute("DELETE FROM notification_deliveries WHERE state != 'scheduled'")
            }
        }
        return LocalDataClearResult(category: category, deletedRows: before - (try rowCount(for: category)))
    }

    func clearCredentials() throws {
        var failed = false
        for target in credentialTargets {
            do { try target.store.remove(account: target.account) }
            catch { failed = true }
        }
        if failed { throw PrivacyDiagnosticsError.credentialClearFailed }
    }

    private func decodeSourceHealth(_ row: SQLiteRow) -> DiagnosticSourceHealth? {
        guard let rawSource = row.string("source_kind"),
              let source = SourceKind(rawValue: rawSource)?.rawValue else { return nil }
        let authorization = row.string("authorization_state") ?? "unknown"
        let error = row.string("latest_error")
        let lastSuccessfulSync = row.double("last_successful_sync")
        let latestAttempt = row.double("latest_attempt_at")
        let recoveredHistoricalIssue: Bool
        if let lastSuccessfulSync, let latestAttempt {
            recoveredHistoricalIssue = error != nil && lastSuccessfulSync > latestAttempt
        } else {
            recoveredHistoricalIssue = false
        }
        let category: SourceHealthCategory
        if ["missing", "expired", "revoked", "unauthorized"].contains(authorization) {
            category = .authorizationRequired
        } else {
            switch recoveredHistoricalIssue ? nil : error {
            case nil: category = .ready
            case "unauthorized": category = .authorizationRequired
            case "forbidden": category = .permissionDenied
            case "offline": category = .offline
            case "rate_limited": category = .rateLimited
            case "source_changed", "malformed_response": category = .sourceChanged
            case "temporary_server": category = .serviceUnavailable
            case "cancelled": category = .cancelled
            default: category = .failed
            }
        }
        let guidance: (String, String) = switch category {
        case .ready where recoveredHistoricalIssue:
            ("Ready. A previous issue was recovered.", "No action needed. Historical recovery is retained locally.")
        case .ready: ("Ready.", "No action needed.")
        case .notConfigured: ("Not configured.", "Configure this source before synchronizing.")
        case .authorizationRequired: ("Authorization needs attention.", "Reconnect this source using the secure authorization flow.")
        case .permissionDenied: ("The source denied access.", "Check account access or reconnect the source.")
        case .offline: ("The Mac was offline during the last attempt.", "Reconnect to the network; recovery sync will retry.")
        case .rateLimited: ("The source asked the app to slow down.", "Wait for the automatic retry or refresh later.")
        case .sourceChanged: ("The source response no longer matches its safe contract.", "Update or repair the connector before retrying.")
        case .serviceUnavailable: ("The source service was temporarily unavailable.", "Try again later; other sources remain available.")
        case .cancelled: ("The last synchronization was cancelled.", "Refresh again when ready.")
        case .failed: ("The last synchronization failed.", "Review this source configuration and retry.")
        }
        return DiagnosticSourceHealth(
            source: source, category: category,
            lastSuccessfulSync: lastSuccessfulSync.map(Date.init(timeIntervalSince1970:)),
            message: guidance.0, recoveryAction: guidance.1
        )
    }

    private func sanitizedSubsystems(_ values: [SubsystemHealth]) -> [SubsystemHealth] {
        let allowedNames = Set(["calendar", "notifications", "ai", "background", "database"])
        let allowedCategories = Set([
            "not_determined", "denied", "restricted", "full_access", "write_only",
            "authorized", "enabled", "disabled", "enabled_local", "requires_approval",
            "unavailable", "healthy", "failed"
        ])
        return values.compactMap { value in
            guard allowedNames.contains(value.subsystem) else { return nil }
            let category = allowedCategories.contains(value.category) ? value.category : "unavailable"
            let action = category == "authorized" || category == "enabled"
                || category == "enabled_local" || category == "full_access" || category == "healthy"
                ? "No action needed."
                : "Review this subsystem in Settings; unrelated features remain available."
            return SubsystemHealth(
                subsystem: value.subsystem, category: category, recoveryAction: action
            )
        }.sorted { $0.subsystem < $1.subsystem }
    }

    private func aggregateCounts() throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for table in ["courses", "course_meetings", "learning_tasks", "announcements",
                      "sync_runs", "calendar_bindings", "notification_deliveries",
                      "ai_parse_results", "outbox_work"] {
            counts[table] = try database.scalarInt("SELECT COUNT(*) AS value FROM \(table)")
        }
        return counts
    }

    private func rowCount(for category: LocalDataCategory) throws -> Int {
        let tables: [String] = switch category {
        case .sourceCache: ["outbox_work", "source_presence", "source_baselines", "raw_source_records", "course_meetings", "announcements", "learning_tasks", "courses"]
        case .localUserState: ["local_user_states"]
        case .syncHistory: ["change_records", "sync_runs", "release_metric_events"]
        case .aiHistory: ["ai_parse_results", "ai_provider_cache", "academic_signal_analyses", "academic_signals", "academic_signal_audit", "academic_analysis_decisions"]
        case .notificationHistory: ["notification_deliveries"]
        }
        return try tables.reduce(0) { total, table in
            total + (try database.scalarInt("SELECT COUNT(*) AS value FROM \(table)"))
        }
    }
}
