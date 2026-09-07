import Foundation

enum AppEnvironment {
    /// Stage 15R release boundary: Outlook is intentionally absent from the
    /// production dependency graph and therefore cannot authorize or send traffic.
    static let outlookEnabledInRelease = false

    struct Dependencies {
        let localStateRepository: any LocalStateRepository
        let dashboardDataReader: (any DashboardDataReading)?
        let calendarService: CampusCalendarService?
        let notificationService: CampusNotificationService?
        let backgroundScheduler: BackgroundSyncScheduler?
        let aiCoordinator: AIParsingCoordinator?
        let academicSignalCoordinator: AcademicSignalCoordinator?
        let courseReconciliation: CourseReconciliationService?
        let outlookAuthorization: OutlookAuthorizationService?
        let privacyDiagnostics: PrivacyDiagnosticsService?
        let releaseReadiness: ReleaseReadinessService?
    }

    static func dependencies() -> Dependencies {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = base.appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "com.campusdashboard.desktop",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let database = try SQLiteDatabase(path: directory.appendingPathComponent("campus-dashboard.sqlite3").path)
            let persistence = SQLitePersistenceRepository(database: database)
            let calendar = CampusCalendarService(database: database, store: EventKitEventStore())
            let notifications = CampusNotificationService(
                database: database, center: SystemUserNotificationCenterClient()
            )
            let deepSeekConfiguration = DeepSeekConfigurationService(
                database: database,
                secrets: KeychainSecretStore(service: DeepSeekConfigurationService.keychainService)
            )
            let deepSeek = DeepSeekAIProvider(database: database, configuration: deepSeekConfiguration)
            let ai = AIParsingCoordinator(
                database: database, provider: deepSeek,
                deepSeekConfiguration: deepSeekConfiguration
            )
            let academicSignals = AcademicSignalCoordinator(database: database, provider: deepSeek)
            let courseReconciliation = CourseReconciliationService(database: database)
            let runner = ProductionSyncRunner(
                database: database, calendar: calendar, notifications: notifications,
                aiCoordinator: ai, academicSignalCoordinator: academicSignals
            )
            let scheduler = BackgroundSyncScheduler(
                database: database, runner: runner, notifications: notifications
            )
            let privacyDiagnostics = PrivacyDiagnosticsService(
                database: database,
                credentialTargets: [
                    CredentialTarget(
                        store: KeychainSecretStore(service: "com.campusdashboard.desktop.canvas"),
                        account: CanvasConfiguration.tokenAccount
                    ),
                    CredentialTarget(
                        store: KeychainSecretStore(service: SIwebLocalTool.keychainService),
                        account: SIwebConfiguration.sessionAccount
                    )
                ]
            )
            let releaseReadiness = ReleaseReadinessService(database: database)
            return Dependencies(
                localStateRepository: SQLiteLocalStateRepository(persistence: persistence),
                dashboardDataReader: SQLiteDashboardDataReader(database: database),
                calendarService: calendar, notificationService: notifications,
                backgroundScheduler: scheduler, aiCoordinator: ai,
                academicSignalCoordinator: academicSignals,
                courseReconciliation: courseReconciliation,
                outlookAuthorization: nil,
                privacyDiagnostics: privacyDiagnostics,
                releaseReadiness: releaseReadiness
            )
        } catch {
            return Dependencies(
                localStateRepository: UnavailableLocalStateRepository(error: LocalPersistenceUnavailable(
                    reason: String(describing: error)
                )),
                dashboardDataReader: nil,
                calendarService: nil, notificationService: nil, backgroundScheduler: nil,
                aiCoordinator: nil, academicSignalCoordinator: nil,
                courseReconciliation: nil,
                outlookAuthorization: nil, privacyDiagnostics: nil, releaseReadiness: nil
            )
        }
    }

    static func localStateRepository() -> any LocalStateRepository {
        dependencies().localStateRepository
    }
}
