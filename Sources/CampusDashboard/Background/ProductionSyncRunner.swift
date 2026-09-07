import Foundation

struct ProductionSyncRunner: ScheduledSyncRunner {
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
        var accounts: [SyncSourceAccount] = []
        var readers: [any SyncSourceReader] = []
        var instanceBySource: [SourceKind: String] = [:]
        if let configuration = try? UserDefaultsCanvasConfigurationStore().load() {
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
        if let configuration = try? UserDefaultsSIwebConfigurationStore().load() {
            instanceBySource[.siweb] = configuration.baseURL.absoluteString
            accounts.append(SyncSourceAccount(
                id: UUID(), source: .siweb, instanceURL: configuration.baseURL.absoluteString,
                displayName: "SIweb"
            ))
            readers.append(SIwebSyncSourceReader(service: SIwebConnector(
                configuration: configuration,
                authorizer: KeychainSIwebSessionAuthorizer(
                    secretStore: KeychainSecretStore(service: SIwebLocalTool.keychainService),
                    account: configuration.sessionAccount
                )
            )))
        }
        guard !accounts.isEmpty else { return [] }
        let engine = DeterministicSyncEngine(database: database, accounts: accounts, readers: readers)
        let outcomes = await engine.synchronizeAll(trigger: trigger)
        // AI runs only after deterministic source transactions commit. Its failure cannot
        // change source outcomes, and the coordinator is a no-op while AI is disabled.
        _ = await aiCoordinator?.processPendingCanvasRecords(limit: 100)
        _ = await academicSignalCoordinator?.processPending(limit: 100)
        let processor = OutboxProcessor(
            database: database, calendar: calendar, notifications: notifications
        )
        _ = await processor.processPending(limit: 500)
        return outcomes.map { outcome in
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
    }
}
