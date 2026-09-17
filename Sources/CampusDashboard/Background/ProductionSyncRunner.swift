import Foundation

struct ProductionSyncRunner: SourceScopedScheduledSyncRunner {
    let database: SQLiteDatabase
    let calendar: any CalendarService
    let notifications: CampusNotificationService
    let aiCoordinator: AIParsingCoordinator?
    let academicSignalCoordinator: AcademicSignalCoordinator?

    init(database: SQLiteDatabase, calendar: any CalendarService,
         notifications: CampusNotificationService, aiCoordinator: AIParsingCoordinator? = nil,
         academicSignalCoordinator: AcademicSignalCoordinator? = nil) {
        self.database = database
        self.calendar = calendar
        self.notifications = notifications
        self.aiCoordinator = aiCoordinator
        self.academicSignalCoordinator = academicSignalCoordinator
    }

    func run(trigger: SyncTrigger) async -> [ScheduledSourceResult] {
        await runConfiguredSources(trigger: trigger, source: nil)
    }

    func run(trigger: SyncTrigger, source: SourceKind) async -> [ScheduledSourceResult] {
        await runConfiguredSources(trigger: trigger, source: source)
    }

    private func runConfiguredSources(
        trigger: SyncTrigger, source requestedSource: SourceKind?
    ) async -> [ScheduledSourceResult] {
        var accounts: [SyncSourceAccount] = []
        var readers: [any SyncSourceReader] = []
        var instanceBySource: [SourceKind: String] = [:]
        var skippedResults: [ScheduledSourceResult] = []
        if requestedSource == nil || requestedSource == .canvas,
           let configuration = try? UserDefaultsCanvasConfigurationStore().load() {
            instanceBySource[.canvas] = configuration.baseURL.absoluteString
            accounts.append(SyncSourceAccount(
                id: UUID(), source: .canvas, instanceURL: configuration.baseURL.absoluteString,
                displayName: "Canvas"
            ))
            readers.append(CanvasSyncSourceReader(service: CanvasAPIConnector(
                configuration: configuration,
                secretStore: KeychainSecretStore(service: "com.campusdashboard.desktop.canvas")
            )))
        }
        if requestedSource == nil || requestedSource == .siweb,
           let configuration = try? UserDefaultsSIwebConfigurationStore().load() {
            instanceBySource[.siweb] = configuration.baseURL.absoluteString
            let existing = (try? database.query(
                "SELECT id, display_name, authorization_state FROM source_accounts WHERE source_kind=? AND instance_url=? LIMIT 1",
                bindings: [.text(SourceKind.siweb.rawValue), .text(configuration.baseURL.absoluteString)]
            ))?.first
            if !Self.shouldAttemptSIweb(
                trigger: trigger, authorizationState: existing?.string("authorization_state")
            ) {
                skippedResults.append(ScheduledSourceResult(
                    sourceAccountID: existing?.string("id") ?? SourceKind.siweb.rawValue,
                    sourceName: existing?.string("display_name") ?? "SIweb",
                    errorCategory: SyncErrorCategory.unauthorized.rawValue
                ))
            } else {
                let secretStore = KeychainSecretStore(service: SIwebLocalTool.keychainService)
                accounts.append(SyncSourceAccount(
                    id: UUID(), source: .siweb, instanceURL: configuration.baseURL.absoluteString,
                    displayName: "SIweb"
                ))
                readers.append(SIwebSyncSourceReader(service: SIwebConnector(
                    configuration: configuration,
                    authorizer: KeychainSIwebSessionAuthorizer(
                        secretStore: secretStore, account: configuration.sessionAccount
                    ),
                    sessionLifecycle: KeychainSIwebSessionLifecycle(
                        secretStore: secretStore, account: configuration.sessionAccount
                    )
                )))
            }
        }
        guard !accounts.isEmpty else { return skippedResults }
        let engine = DeterministicSyncEngine(database: database, accounts: accounts, readers: readers)
        let outcomes = await engine.synchronizeAll(trigger: trigger)
        // This only updates local reconciliation metadata and signal targets. It never
        // enqueues Calendar work; Calendar remains behind the existing explicit preview/apply gate.
        _ = try? CourseReconciliationService(database: database).reconcile()
        if requestedSource == nil {
            // AI and explicit side-effect work remain part of the ordinary whole-product
            // sync. A source-scoped post-authorization check cannot trigger unrelated work.
            _ = await aiCoordinator?.processPendingCanvasRecords(limit: 100)
            _ = await academicSignalCoordinator?.processPending(limit: 100)
            let processor = OutboxProcessor(
                database: database, calendar: calendar, notifications: notifications
            )
            _ = await processor.processPending(limit: 500)
        }
        let completedResults = outcomes.map { outcome in
            let row = try? database.query(
                "SELECT id, display_name FROM source_accounts WHERE source_kind=? AND instance_url=? LIMIT 1",
                bindings: [
                    .text(outcome.source.rawValue), .text(instanceBySource[outcome.source] ?? "")
                ]
            ).first
            let error: String?
            switch outcome.result { case .success: error = nil; case .failure(let value): error = value.category.rawValue }
            return ScheduledSourceResult(
                sourceAccountID: row?.string("id") ?? outcome.source.rawValue,
                sourceName: row?.string("display_name") ?? outcome.source.rawValue,
                errorCategory: error
            )
        }
        return (completedResults + skippedResults).sorted { $0.sourceName < $1.sourceName }
    }

    static func shouldAttemptSIweb(trigger: SyncTrigger, authorizationState: String?) -> Bool {
        guard trigger != .manual else { return true }
        return !["missing", "expired", "revoked", "unauthorized"].contains(authorizationState)
    }
}
