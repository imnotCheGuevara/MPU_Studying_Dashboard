import AppKit
import Foundation

enum ReleaseSetupIntegration: String, CaseIterable, Identifiable, Sendable {
    case canvas = "Canvas"
    case siweb = "SIweb"
    case calendar = "Dedicated Calendar"
    case notifications = "Notifications"
    case deepSeek = "Optional DeepSeek"

    var id: Self { self }
    var isOptional: Bool { self == .deepSeek }
}

struct ReleaseSetupItem: Identifiable, Equatable, Sendable {
    var id: ReleaseSetupIntegration { integration }
    let integration: ReleaseSetupIntegration
    let isComplete: Bool
    let detail: String
    let minimumData: String
}

enum RecoveryCategory: String, CaseIterable, Identifiable, Sendable {
    case authenticationExpired = "Authentication expired"
    case missingConsentOrKey = "Missing consent or Keychain item"
    case networkOrExactHost = "Network or exact-host route"
    case httpOrRateLimit = "HTTP or rate limit"
    case timeout = "Timeout"
    case schemaOrDecoding = "Schema or decoding"
    case budget = "Local AI budget"
    case calendarPermission = "Calendar permission"
    case notificationPermission = "Notification permission"

    var id: Self { self }

    var unaffectedFeatures: String {
        switch self {
        case .authenticationExpired: "Cached data and other connected sources remain available."
        case .missingConsentOrKey, .networkOrExactHost, .httpOrRateLimit, .timeout, .schemaOrDecoding, .budget:
            "Deterministic organization, source sync, and existing local history remain available."
        case .calendarPermission: "Sync, review, and notifications remain available; no Calendar event is changed."
        case .notificationPermission: "Sync, review, and Calendar remain available."
        }
    }

    var recoveryAction: String {
        switch self {
        case .authenticationExpired: "Reconnect only the affected source in Settings, then refresh."
        case .missingConsentOrKey: "Review consent and the Keychain-backed credential in Settings."
        case .networkOrExactHost: "Restore the network or review the DeepSeek exact-host route, then retry."
        case .httpOrRateLimit: "Wait for the requested delay, then retry only the affected subsystem."
        case .timeout: "Retry later; repeated attempts remain idempotent."
        case .schemaOrDecoding: "Keep the retained local result and retry after the connector or provider is repaired."
        case .budget: "Review the local request/token budget, then explicitly reprocess."
        case .calendarPermission: "Restore Calendar access in System Settings, then revalidate the dedicated calendar."
        case .notificationPermission: "Restore Notifications in System Settings, then enable them here."
        }
    }
}

struct RecoveryPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let subsystem: String
    let category: RecoveryCategory
    let detail: String
}

enum CalendarPreviewOperation: String, Sendable, Equatable {
    case create
    case update
    case cancel
}

enum AcademicEventSemantic: String, Sendable, Equatable {
    case courseCancellation = "Course cancellation"
    case makeupOrChange = "Makeup / schedule change"
    case assignmentDeadline = "Assignment deadline"
    case exam = "Exam or Quiz"
}

struct CalendarChangePreview: Identifiable, Equatable, Sendable {
    let id: UUID
    let signalID: UUID
    let operation: CalendarPreviewOperation
    let calendarTitle: String
    let courseTitle: String
    let semantic: AcademicEventSemantic
    let startsAt: Date?
    let endsAt: Date?
    let isAllDay: Bool
    let affectedBoundEvent: String
    let undoEffect: String
    let displayMarker: String
}

struct OutcomeMetricSnapshot: Equatable, Sendable {
    let completedSyncs: Int
    let failedSyncs: Int
    let averageSyncLatencySeconds: Double?
    let reviewedCorrections: Int
    let recoveredProviderFailures: Int
    let providerFailures: Int
    let criticalCorrectionsFromOther: Int
    let duplicateActiveBindings: Int
    let unsafeCalendarBindings: Int
    let duplicateNotificationKeys: Int
    let observedHandlingSamples: Int
    let averageHandlingSeconds: Double?

    static let empty = OutcomeMetricSnapshot(
        completedSyncs: 0, failedSyncs: 0, averageSyncLatencySeconds: nil,
        reviewedCorrections: 0, recoveredProviderFailures: 0, providerFailures: 0,
        criticalCorrectionsFromOther: 0, duplicateActiveBindings: 0,
        unsafeCalendarBindings: 0, duplicateNotificationKeys: 0,
        observedHandlingSamples: 0, averageHandlingSeconds: nil
    )
}

final class ReleaseReadinessService: @unchecked Sendable {
    private let database: SQLiteDatabase
    private let canvasConfigurations: any CanvasConfigurationStore
    private let canvasSecrets: any SecretStore
    private let siwebConfigurations: any SIwebConfigurationStore
    private let siwebSecrets: any SecretStore
    private let defaults: UserDefaults

    init(
        database: SQLiteDatabase,
        canvasConfigurations: any CanvasConfigurationStore = UserDefaultsCanvasConfigurationStore(),
        canvasSecrets: any SecretStore = KeychainSecretStore(service: CanvasLocalTool.keychainService),
        siwebConfigurations: any SIwebConfigurationStore = UserDefaultsSIwebConfigurationStore(),
        siwebSecrets: any SecretStore = KeychainSecretStore(service: SIwebLocalTool.keychainService),
        defaults: UserDefaults = .standard
    ) {
        self.database = database
        self.canvasConfigurations = canvasConfigurations
        self.canvasSecrets = canvasSecrets
        self.siwebConfigurations = siwebConfigurations
        self.siwebSecrets = siwebSecrets
        self.defaults = defaults
    }

    func shouldPresentFirstRun() -> Bool {
        !defaults.bool(forKey: "Stage15RSetupAssistantPresented")
    }

    func markFirstRunPresented() {
        defaults.set(true, forKey: "Stage15RSetupAssistantPresented")
    }

    func sourceSetupItems(
        calendarReady: Bool, notificationsReady: Bool, deepSeekReady: Bool
    ) -> [ReleaseSetupItem] {
        let canvasCredentialConfigured = (try? canvasConfigurations.load()) != nil
            && ((try? canvasSecrets.data(account: CanvasConfiguration.tokenAccount).isEmpty == false) ?? false)
        let siwebCredentialConfigured = (try? siwebConfigurations.load()) != nil
            && ((try? siwebSecrets.data(account: SIwebConfiguration.sessionAccount).isEmpty == false) ?? false)
        return [
            .init(integration: .canvas, isComplete: canvasCredentialConfigured,
                  detail: canvasCredentialConfigured ? "Configured securely."
                    : "Add the Canvas HTTPS address and access token.",
                  minimumData: "Reads active courses, assignments, and announcements; the token stays in Keychain."),
            .init(integration: .siweb, isComplete: siwebCredentialConfigured,
                  detail: siwebCredentialConfigured ? "Authorized session is in Keychain."
                    : "Sign in on MPU's non-persistent page.",
                  minimumData: "Reads the approved timetable page; Campus Dashboard never reads login fields."),
            .init(integration: .calendar, isComplete: calendarReady,
                  detail: calendarReady ? "Dedicated calendar verified." : "Grant access and select or create one dedicated calendar.",
                  minimumData: "Writes only app-owned bound events in that calendar."),
            .init(integration: .notifications, isComplete: notificationsReady,
                  detail: notificationsReady ? "Local notifications enabled." : "Enable notifications from a user action.",
                  minimumData: "Schedules local reminders; no notification content is sent to a server."),
            .init(integration: .deepSeek, isComplete: deepSeekReady,
                  detail: deepSeekReady ? "Optional assistance enabled with current consent." : "Optional; deterministic results remain available.",
                  minimumData: "Sends only the bounded fields shown in the disclosure after explicit consent.")
        ]
    }

    func configureCanvas(baseURL: String, token: String) throws {
        guard let url = URL(string: baseURL) else { throw CanvasConfigurationError.invalidBaseURL }
        let configuration = try CanvasConfiguration(baseURL: url)
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CanvasConfigurationError.emptyToken }
        try canvasConfigurations.saveBaseURL(configuration.baseURL)
        try canvasSecrets.remove(account: CanvasConfiguration.tokenAccount)
        try canvasSecrets.set(Data(trimmed.utf8), account: CanvasConfiguration.tokenAccount)
    }

    func revokeCanvas() throws {
        try canvasSecrets.remove(account: CanvasConfiguration.tokenAccount)
    }

    func revokeSIweb() throws {
        try siwebSecrets.remove(account: SIwebConfiguration.sessionAccount)
    }

    func recordHandlingDuration(_ duration: TimeInterval, action: String, at date: Date = Date()) throws {
        guard duration >= 0, duration < 86_400 else { return }
        try database.execute(
            "INSERT INTO release_metric_events(id,metric_kind,category,numeric_value,occurred_at) VALUES(?,?,?,?,?)",
            bindings: [.text(UUID().uuidString), .text("handling_seconds"), .text(action),
                       .real(duration), .real(date.timeIntervalSince1970)]
        )
    }

    func outcomeMetrics() throws -> OutcomeMetricSnapshot {
        let sync = try database.query(
            "SELECT COUNT(*) total,SUM(CASE WHEN r.persistence_state='committed' THEN 1 ELSE 0 END) ok,AVG(CASE WHEN r.finished_at IS NOT NULL THEN r.finished_at-r.started_at END) latency FROM sync_runs r JOIN source_accounts sa ON sa.id=r.source_account_id WHERE LOWER(sa.source_kind) IN ('canvas','siweb')"
        ).first
        let corrections = try database.scalarInt(
            "SELECT COUNT(*) FROM academic_signal_audit a JOIN academic_signals s ON s.id=a.signal_id JOIN source_accounts sa ON sa.id=s.source_account_id WHERE a.action IN ('correct','correct_analysis') AND LOWER(sa.source_kind) IN ('canvas','siweb') AND LOWER(s.provider) NOT LIKE '%fixture%' AND LOWER(s.provider) NOT LIKE '%synthetic%' AND LOWER(s.model) NOT LIKE '%fixture%' AND LOWER(s.model) NOT LIKE '%synthetic%'"
        )
        let failures = try database.scalarInt(
            "SELECT COUNT(*) FROM academic_signal_analyses a JOIN source_accounts sa ON sa.id=a.source_account_id WHERE a.status='failed' AND LOWER(sa.source_kind) IN ('canvas','siweb') AND LOWER(a.provider) NOT LIKE '%fixture%' AND LOWER(a.provider) NOT LIKE '%synthetic%' AND LOWER(a.model) NOT LIKE '%fixture%' AND LOWER(a.model) NOT LIKE '%synthetic%'"
        )
        let recovered = try database.scalarInt(
            "SELECT COUNT(DISTINCT f.announcement_id) FROM academic_signal_analyses f JOIN academic_signal_analyses s ON s.announcement_id=f.announcement_id AND s.created_at>f.created_at JOIN source_accounts sa ON sa.id=f.source_account_id WHERE f.status='failed' AND s.status IN ('analyzed','deterministic_only') AND LOWER(sa.source_kind) IN ('canvas','siweb') AND LOWER(f.provider) NOT LIKE '%fixture%' AND LOWER(f.provider) NOT LIKE '%synthetic%' AND LOWER(f.model) NOT LIKE '%fixture%' AND LOWER(f.model) NOT LIKE '%synthetic%' AND LOWER(s.provider) NOT LIKE '%fixture%' AND LOWER(s.provider) NOT LIKE '%synthetic%' AND LOWER(s.model) NOT LIKE '%fixture%' AND LOWER(s.model) NOT LIKE '%synthetic%'"
        )
        let criticalMisses = try database.scalarInt(
            "SELECT COUNT(*) FROM academic_signal_audit a JOIN academic_signals s ON s.id=a.signal_id JOIN academic_signal_analyses n ON n.id=s.analysis_id JOIN source_accounts sa ON sa.id=s.source_account_id WHERE a.action='correct_analysis' AND n.primary_category='other' AND s.category IN ('course_schedule_change','assignment_deadline','exam_time') AND LOWER(sa.source_kind) IN ('canvas','siweb') AND LOWER(n.provider) NOT LIKE '%fixture%' AND LOWER(n.provider) NOT LIKE '%synthetic%' AND LOWER(n.model) NOT LIKE '%fixture%' AND LOWER(n.model) NOT LIKE '%synthetic%' AND LOWER(s.provider) NOT LIKE '%fixture%' AND LOWER(s.provider) NOT LIKE '%synthetic%' AND LOWER(s.model) NOT LIKE '%fixture%' AND LOWER(s.model) NOT LIKE '%synthetic%'"
        )
        let duplicateBindings = try database.scalarInt(
            """
            SELECT COALESCE(SUM(n-1),0) FROM (
              SELECT COUNT(*) n FROM calendar_bindings b
              WHERE b.sync_state!='removed' AND (
                (b.object_type='learning_task' AND EXISTS (
                  SELECT 1 FROM learning_tasks t JOIN source_accounts sa ON sa.id=t.source_account_id
                  WHERE t.id=b.object_id AND LOWER(sa.source_kind) IN ('canvas','siweb')
                )) OR
                (b.object_type='course_meeting' AND EXISTS (
                  SELECT 1 FROM course_meetings cm JOIN courses c ON c.id=cm.course_id
                  JOIN source_accounts sa ON sa.id=c.source_account_id
                  WHERE cm.id=b.object_id AND LOWER(sa.source_kind) IN ('canvas','siweb')
                )) OR
                (b.object_type='academic_signal' AND EXISTS (
                  SELECT 1 FROM academic_signals s JOIN source_accounts sa ON sa.id=s.source_account_id
                  WHERE s.id=b.object_id AND LOWER(sa.source_kind) IN ('canvas','siweb')
                ))
              ) GROUP BY b.object_type,b.object_id HAVING COUNT(*)>1
            )
            """
        )
        let unsafeBindings = try database.scalarInt(
            """
            SELECT COUNT(*) FROM calendar_bindings b
            LEFT JOIN managed_calendar_identity m
              ON b.calendar_identifier=m.calendar_identifier
              AND b.calendar_source_identifier=m.source_identifier
            WHERE b.sync_state!='removed' AND m.internal_id IS NULL AND (
              (b.object_type='learning_task' AND EXISTS (
                SELECT 1 FROM learning_tasks t JOIN source_accounts sa ON sa.id=t.source_account_id
                WHERE t.id=b.object_id AND LOWER(sa.source_kind) IN ('canvas','siweb')
              )) OR
              (b.object_type='course_meeting' AND EXISTS (
                SELECT 1 FROM course_meetings cm JOIN courses c ON c.id=cm.course_id
                JOIN source_accounts sa ON sa.id=c.source_account_id
                WHERE cm.id=b.object_id AND LOWER(sa.source_kind) IN ('canvas','siweb')
              )) OR
              (b.object_type='academic_signal' AND EXISTS (
                SELECT 1 FROM academic_signals s JOIN source_accounts sa ON sa.id=s.source_account_id
                WHERE s.id=b.object_id AND LOWER(sa.source_kind) IN ('canvas','siweb')
              ))
            )
            """
        )
        let duplicateNotifications = try database.scalarInt(
            """
            SELECT COALESCE(SUM(n-1),0) FROM (
              SELECT COUNT(*) n FROM notification_deliveries d WHERE
                (d.object_type='source_account' AND EXISTS (
                  SELECT 1 FROM source_accounts sa WHERE sa.id=d.object_id
                  AND LOWER(sa.source_kind) IN ('canvas','siweb')
                )) OR
                (d.object_type='learning_task' AND EXISTS (
                  SELECT 1 FROM learning_tasks t JOIN source_accounts sa ON sa.id=t.source_account_id
                  WHERE t.id=d.object_id AND LOWER(sa.source_kind) IN ('canvas','siweb')
                )) OR
                (d.object_type='announcement' AND EXISTS (
                  SELECT 1 FROM announcements a JOIN source_accounts sa ON sa.id=a.source_account_id
                  WHERE a.id=d.object_id AND LOWER(sa.source_kind) IN ('canvas','siweb')
                )) OR
                (d.object_type='course_meeting' AND EXISTS (
                  SELECT 1 FROM course_meetings cm JOIN courses c ON c.id=cm.course_id
                  JOIN source_accounts sa ON sa.id=c.source_account_id
                  WHERE cm.id=d.object_id AND LOWER(sa.source_kind) IN ('canvas','siweb')
                ))
              GROUP BY d.notification_key HAVING COUNT(*)>1
            )
            """
        )
        let handling = try database.query(
            "SELECT COUNT(*) count,AVG(numeric_value) average FROM release_metric_events WHERE metric_kind='handling_seconds'"
        ).first
        let total = Int(sync?.int("total") ?? 0)
        let completed = Int(sync?.int("ok") ?? 0)
        return OutcomeMetricSnapshot(
            completedSyncs: completed, failedSyncs: max(0, total - completed),
            averageSyncLatencySeconds: sync?.double("latency"), reviewedCorrections: corrections,
            recoveredProviderFailures: recovered, providerFailures: failures,
            criticalCorrectionsFromOther: criticalMisses, duplicateActiveBindings: duplicateBindings,
            unsafeCalendarBindings: unsafeBindings, duplicateNotificationKeys: duplicateNotifications,
            observedHandlingSamples: Int(handling?.int("count") ?? 0),
            averageHandlingSeconds: handling?.double("average")
        )
    }

    func calendarWrittenSignalIDs() throws -> Set<UUID> {
        let rows = try database.query(
            """
            SELECT s.id FROM academic_signals s JOIN calendar_bindings b
              ON (b.object_type='academic_signal' AND b.object_id=s.id)
              OR (b.object_type='course_meeting' AND b.object_id=s.target_meeting_id)
            WHERE s.is_active=1 AND b.sync_state!='removed'
            """
        )
        return Set(rows.compactMap { $0.string("id").flatMap(UUID.init(uuidString:)) })
    }

    func ignoredAnalysisIDs() throws -> Set<UUID> {
        Set(try database.query("SELECT analysis_id FROM academic_analysis_decisions WHERE decision_state='ignored'")
            .compactMap { $0.string("analysis_id").flatMap(UUID.init(uuidString:)) })
    }

    func setAnalysisIgnored(_ id: UUID, ignored: Bool) throws {
        if ignored {
            try database.execute(
                "INSERT OR REPLACE INTO academic_analysis_decisions(analysis_id,decision_state,updated_at) VALUES(?,'ignored',?)",
                bindings: [.text(id.uuidString), .real(Date().timeIntervalSince1970)]
            )
        } else {
            try database.execute("DELETE FROM academic_analysis_decisions WHERE analysis_id=?",
                                 bindings: [.text(id.uuidString)])
        }
    }

    static func recoveries(
        sources: [DiagnosticSourceHealth], calendar: CalendarAccessStatus,
        notifications: NotificationAuthorizationState, aiFailureCategories: [String]
    ) -> [RecoveryPresentation] {
        var results: [RecoveryPresentation] = []
        for source in sources where source.category != .ready {
            let category: RecoveryCategory = switch source.category {
            case .authorizationRequired, .permissionDenied: .authenticationExpired
            case .offline, .serviceUnavailable: .networkOrExactHost
            case .rateLimited: .httpOrRateLimit
            case .sourceChanged, .failed: .schemaOrDecoding
            case .notConfigured: .missingConsentOrKey
            case .cancelled: .timeout
            case .ready: .schemaOrDecoding
            }
            results.append(.init(id: "source-\(source.source)", subsystem: source.source,
                                 category: category, detail: source.message))
        }
        if calendar != .fullAccess {
            results.append(.init(id: "calendar", subsystem: "Calendar",
                                 category: .calendarPermission, detail: "Calendar access is not available."))
        }
        if notifications != .authorized {
            results.append(.init(id: "notifications", subsystem: "Notifications",
                                 category: .notificationPermission, detail: "Notification access is not available."))
        }
        for raw in Set(aiFailureCategories) {
            let category: RecoveryCategory = switch raw {
            case "consent_required", "configuration", "missing_credential", "keychain_denied", "keychain_unavailable": .missingConsentOrKey
            case "offline", "service_unavailable": .networkOrExactHost
            case "rate_limited", "unauthorized", "forbidden", "insufficient_balance": .httpOrRateLimit
            case "timed_out", "cancelled": .timeout
            case "budget_exceeded": .budget
            default: .schemaOrDecoding
            }
            results.append(.init(id: "ai-\(raw)", subsystem: "DeepSeek", category: category,
                                 detail: AcademicProviderFailurePresentation.safe(raw)?.categoryKey ?? "Provider unavailable"))
        }
        return results.sorted { $0.id < $1.id }
    }

    static func openSystemSettings(for category: RecoveryCategory) {
        let url: URL? = switch category {
        case .calendarPermission: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        case .notificationPermission: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        default: nil
        }
        if let url { NSWorkspace.shared.open(url) }
    }
}
