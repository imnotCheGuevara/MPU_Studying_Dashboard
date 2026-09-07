import Foundation

enum AcademicSignalLocalTool {
    private struct Evidence: Codable {
        let status: String
        let analyzedAnnouncements: Int
        let activeSignalCount: Int
        let inferredDateCount: Int
        let pendingInferredDateCount: Int
        let unauthorizedCalendarOutboxDelta: Int
        let unauthorizedNotificationDelta: Int
        let providerRequestDelta: Int
        let inputTokenDelta: Int
        let outputTokenDelta: Int
        let sourceContentHashUnchanged: Bool
        let providerSchemaValidated: Bool
        let validatorFailureCategory: String?
        let containedPrivateContent: Bool
        let containedCredential: Bool
    }

    static func smokeTest(resultPath: String) async -> Int32 {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let directory = base.appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "com.campusdashboard.desktop", isDirectory: true
            )
            let database = try SQLiteDatabase(
                path: directory.appendingPathComponent("campus-dashboard.sqlite3").path
            )
            let beforeUsage = try usage(database)
            let beforeOutbox = try database.scalarInt(
                "SELECT COUNT(*) AS value FROM outbox_work WHERE kind='calendar'"
            )
            let beforeNotifications = try database.scalarInt(
                "SELECT COUNT(*) AS value FROM notification_deliveries"
            )
            guard let source = try database.query(
                """
                SELECT a.content_hash
                FROM announcements a JOIN source_accounts sa ON sa.id=a.source_account_id
                WHERE sa.source_kind='Canvas' AND a.source_state='active'
                ORDER BY a.published_at DESC LIMIT 1
                """
            ).first, let originalHash = source.string("content_hash") else {
                try write(Evidence(
                    status: "blocked_no_local_canvas_announcement", analyzedAnnouncements: 0,
                    activeSignalCount: 0, inferredDateCount: 0, pendingInferredDateCount: 0,
                    unauthorizedCalendarOutboxDelta: 0, unauthorizedNotificationDelta: 0,
                    providerRequestDelta: 0, inputTokenDelta: 0, outputTokenDelta: 0,
                    sourceContentHashUnchanged: true, providerSchemaValidated: false,
                    validatorFailureCategory: nil,
                    containedPrivateContent: false,
                    containedCredential: false
                ), to: resultPath)
                return 2
            }
            let configuration = DeepSeekConfigurationService(
                database: database,
                secrets: KeychainSecretStore(service: DeepSeekConfigurationService.keychainService)
            )
            let provider = DeepSeekAIProvider(database: database, configuration: configuration)
            let coordinator = AcademicSignalCoordinator(database: database, provider: provider)
            let analyzed = await coordinator.processPending(limit: 1)
            let signals = try coordinator.activeSignals()
            let latestAnalysis = try coordinator.analyses().first
            let afterUsage = try usage(database)
            let currentHash = try database.query(
                """
                SELECT a.content_hash FROM announcements a
                JOIN source_accounts sa ON sa.id=a.source_account_id
                WHERE sa.source_kind='Canvas' AND a.source_state='active'
                ORDER BY a.published_at DESC LIMIT 1
                """
            ).first?.string("content_hash")
            let schemaValidated = latestAnalysis?.status == .analyzed
            let validatorFailureCategory: String? = {
                guard let value = latestAnalysis?.failureCategory else { return nil }
                return AcademicSignalValidationError(rawValue: value)?.rawValue
                    ?? AcademicSignalValidationError.other.rawValue
            }()
            let evidence = Evidence(
                status: analyzed == 1 && schemaValidated ? "pass" : "blocked_provider_validation",
                analyzedAnnouncements: analyzed, activeSignalCount: signals.count,
                inferredDateCount: signals.filter { $0.inferredDate != nil }.count,
                pendingInferredDateCount: signals.filter {
                    $0.inferredDate != nil && $0.confirmationState == .pending
                }.count,
                unauthorizedCalendarOutboxDelta: try database.scalarInt(
                    "SELECT COUNT(*) AS value FROM outbox_work WHERE kind='calendar'"
                ) - beforeOutbox,
                unauthorizedNotificationDelta: try database.scalarInt(
                    "SELECT COUNT(*) AS value FROM notification_deliveries"
                ) - beforeNotifications,
                providerRequestDelta: afterUsage.requests - beforeUsage.requests,
                inputTokenDelta: afterUsage.input - beforeUsage.input,
                outputTokenDelta: afterUsage.output - beforeUsage.output,
                sourceContentHashUnchanged: currentHash == originalHash,
                providerSchemaValidated: schemaValidated,
                validatorFailureCategory: validatorFailureCategory,
                containedPrivateContent: false, containedCredential: false
            )
            try write(evidence, to: resultPath)
            return evidence.status == "pass" && evidence.unauthorizedCalendarOutboxDelta == 0
                && evidence.unauthorizedNotificationDelta == 0
                && evidence.inferredDateCount == evidence.pendingInferredDateCount
                && evidence.sourceContentHashUnchanged && evidence.providerSchemaValidated ? 0 : 2
        } catch {
            try? write(Evidence(
                status: "blocked_safe_failure", analyzedAnnouncements: 0, activeSignalCount: 0,
                inferredDateCount: 0, pendingInferredDateCount: 0,
                unauthorizedCalendarOutboxDelta: 0, unauthorizedNotificationDelta: 0,
                providerRequestDelta: 0, inputTokenDelta: 0, outputTokenDelta: 0,
                sourceContentHashUnchanged: true, providerSchemaValidated: false,
                validatorFailureCategory: nil,
                containedPrivateContent: false,
                containedCredential: false
            ), to: resultPath)
            return 2
        }
    }

    private static func usage(_ database: SQLiteDatabase) throws -> (requests: Int, input: Int, output: Int) {
        let row = try database.query(
            "SELECT COALESCE(SUM(request_count),0) AS requests,COALESCE(SUM(input_tokens),0) AS input,COALESCE(SUM(output_tokens),0) AS output FROM ai_provider_usage"
        ).first
        return (Int(row?.int("requests") ?? 0), Int(row?.int("input") ?? 0), Int(row?.int("output") ?? 0))
    }

    private static func write(_ value: Evidence, to path: String) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
