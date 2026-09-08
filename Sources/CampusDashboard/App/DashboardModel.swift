import AppKit
import Foundation

enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case today = "Today"
    case schedule = "Schedule"
    case tasks = "Tasks"
    case announcements = "Announcements"
    case confirmations = "AI Confirmation Queue"
    case settings = "Settings"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .schedule: "calendar"
        case .tasks: "checklist"
        case .announcements: "megaphone"
        case .confirmations: "checkmark.bubble"
        case .settings: "gearshape"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

enum DemoScenario: String, CaseIterable, Identifiable, Sendable {
    case populated = "Sample data"
    case empty = "Empty"
    case loading = "Loading"
    case error = "Error"
    case permissionDenied = "Permission denied"

    var id: Self { self }
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published var selectedSection: AppSection = .today
    @Published var language: AppLanguage = .english
    @Published private(set) var scenario: DemoScenario
    @Published private(set) var snapshot: DashboardSnapshot
    let isPreviewMode: Bool
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshCount = 0
    @Published private(set) var persistenceError: String?
    @Published private(set) var calendarAccessStatus: CalendarAccessStatus = .notDetermined
    @Published private(set) var dedicatedCalendarValidationState: ManagedCalendarValidationState?
    @Published private(set) var calendarSources: [CalendarSourceDescriptor] = []
    @Published private(set) var writableCalendars: [CalendarDescriptor] = []
    @Published private(set) var calendarMessage = "Calendar sync is not configured."
    @Published private(set) var isCalendarBusy = false
    @Published var selectedCalendarSourceID: String?
    @Published var selectedDedicatedCalendarID: String?
    @Published private(set) var notificationAccessStatus: NotificationAuthorizationState = .notDetermined
    @Published private(set) var notificationPreferences = NotificationPreferences()
    @Published private(set) var notificationCourses: [NotificationCourseSetting] = []
    @Published private(set) var notificationMessage = "Notifications are not enabled."
    @Published private(set) var isNotificationBusy = false
    @Published private(set) var backgroundConfiguration = BackgroundScheduleConfiguration(
        enabled: false, targetInterval: 3_600, lastAttemptAt: nil, lastCompletedAt: nil,
        lastTrigger: nil, lastResult: nil, lastErrorCategory: nil
    )
    @Published private(set) var backgroundItemState: BackgroundItemState = .disabled
    @Published private(set) var backgroundMessage = "Background sync is disabled."
    @Published private(set) var isBackgroundBusy = false
    @Published private(set) var aiSettings = AIAssistanceSettings(
        enabled: false, providerKind: .deterministicFake, providerDisclosure: nil,
        transmittedFields: nil, retentionPolicy: nil, consentedAt: nil,
        updatedAt: Date(timeIntervalSince1970: 0)
    )
    @Published private(set) var aiConfirmations: [AIParseRecord] = []
    @Published private(set) var aiHistory: [AIParseRecord] = []
    @Published private(set) var academicAnalyses: [AcademicAnnouncementAnalysis] = []
    @Published private(set) var academicSignals: [AcademicSignalRecord] = []
    @Published private(set) var aiHasKey = false
    @Published private(set) var deepSeekUsage = DeepSeekUsageSnapshot(
        requestCount: 0, inputTokens: 0, outputTokens: 0, estimatedCostMicrousd: 0
    )
    @Published private(set) var aiMessage = "AI assistance is off. Deterministic organization remains available."
    @Published private(set) var outlookStatus: OutlookAuthorizationStatus = .disconnected
    @Published private(set) var outlookMessage = "School Outlook is not configured."
    @Published private(set) var outlookClientID = ""
    @Published private(set) var outlookTenantID = ""
    @Published private(set) var isOutlookBusy = false
    @Published private(set) var sourceHealth: [DiagnosticSourceHealth] = []
    @Published private(set) var diagnosticPreview = "Diagnostics have not been refreshed."
    @Published private(set) var privacyMessage = "Local data, credentials, and Calendar cleanup are separate operations."
    @Published private(set) var calendarCleanupPreview: [CalendarCleanupItem] = []
    @Published private(set) var isPrivacyBusy = false
    @Published private(set) var setupItems: [ReleaseSetupItem] = []
    @Published var isSetupAssistantPresented = false
    @Published private(set) var recoveryItems: [RecoveryPresentation] = []
    @Published private(set) var outcomeMetrics: OutcomeMetricSnapshot?
    @Published private(set) var canvasSetupMessage = "Canvas is not configured."
    @Published private(set) var siwebSetupMessage = "SIweb is not configured."
    @Published var isSIwebAuthorizationPresented = false
    @Published var calendarChangePreview: CalendarChangePreview?
    @Published private(set) var calendarWrittenSignalIDs: Set<UUID> = []
    @Published private(set) var ignoredAcademicAnalysisIDs: Set<UUID> = []
    @Published private(set) var courseMappingDecisions: [CourseMappingDecision] = []

    private let localStateRepository: any LocalStateRepository
    private let dataReader: (any DashboardDataReading)?
    private let calendarService: CampusCalendarService?
    private let notificationService: CampusNotificationService?
    private let backgroundScheduler: BackgroundSyncScheduler?
    private let aiCoordinator: AIParsingCoordinator?
    private let academicSignalCoordinator: AcademicSignalCoordinator?
    private let courseReconciliation: CourseReconciliationService?
    private let outlookAuthorization: OutlookAuthorizationService?
    private let outlookIsPreviewOverride: Bool
    private let privacyDiagnostics: PrivacyDiagnosticsService?
    private let releaseReadiness: ReleaseReadinessService?
    private let showsSyntheticAIResultsForQA: Bool
    private let nowProvider: @Sendable () -> Date
    let presentationTimeZone: TimeZone
    private var recoveryMonitor: RuntimeRecoveryMonitor?
    private var runtimeStarted = false
    private var academicReviewStartedAt: [UUID: Date] = [:]

    init(
        scenario: DemoScenario? = nil,
        snapshot: DashboardSnapshot? = nil,
        localStateRepository: any LocalStateRepository = InMemoryLocalStateRepository(),
        dataReader: (any DashboardDataReading)? = nil,
        calendarService: CampusCalendarService? = nil,
        notificationService: CampusNotificationService? = nil,
        backgroundScheduler: BackgroundSyncScheduler? = nil,
        aiCoordinator: AIParsingCoordinator? = nil,
        academicSignalCoordinator: AcademicSignalCoordinator? = nil,
        courseReconciliation: CourseReconciliationService? = nil,
        outlookAuthorization: OutlookAuthorizationService? = nil,
        outlookPreviewStatus: OutlookAuthorizationStatus? = nil,
        privacyDiagnostics: PrivacyDiagnosticsService? = nil,
        releaseReadiness: ReleaseReadinessService? = nil,
        showsSyntheticAIResultsForQA: Bool = false,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        isPreviewMode = scenario != nil
        self.scenario = scenario ?? .populated
        self.snapshot = snapshot ?? .empty
        self.localStateRepository = localStateRepository
        self.dataReader = dataReader
        self.calendarService = calendarService
        self.notificationService = notificationService
        self.backgroundScheduler = backgroundScheduler
        self.aiCoordinator = aiCoordinator
        self.academicSignalCoordinator = academicSignalCoordinator
        self.courseReconciliation = courseReconciliation
        self.outlookAuthorization = outlookAuthorization
        outlookIsPreviewOverride = outlookPreviewStatus != nil
        self.privacyDiagnostics = privacyDiagnostics
        self.releaseReadiness = releaseReadiness
        self.showsSyntheticAIResultsForQA = showsSyntheticAIResultsForQA
        nowProvider = now
        presentationTimeZone = timeZone
        if let scenario, snapshot == nil { applyScenario(scenario) }
        else { restoreLocalState() }
        if let outlookPreviewStatus {
            outlookStatus = outlookPreviewStatus
            outlookClientID = "11111111-1111-4111-8111-111111111111"
            outlookTenantID = "22222222-2222-4222-8222-222222222222"
            updateOutlookMessage()
        }
    }

    func startRuntimeServices() async {
        guard !runtimeStarted else { return }
        runtimeStarted = true
        await reloadDashboardData()
        refreshCourseMappings()
        await refreshNotificationConfiguration()
        try? await notificationService?.reconcileReminders()
        await refreshBackgroundConfiguration()
        refreshAIConfiguration()
        try? await refreshCalendarConfiguration()
        await refreshDiagnostics()
        refreshReleaseReadiness()
        if let backgroundScheduler {
            await backgroundScheduler.setCompletionHandler { [weak self] in
                await self?.reloadDashboardData()
                await self?.refreshDiagnostics()
            }
            let monitor = RuntimeRecoveryMonitor(scheduler: backgroundScheduler)
            monitor.start()
            recoveryMonitor = monitor
            await backgroundScheduler.start()
            await refreshBackgroundConfiguration()
        }
    }

    func refreshReleaseReadiness() {
        guard let releaseReadiness else { return }
        setupItems = releaseReadiness.sourceSetupItems(
            calendarReady: calendarAccessStatus == .fullAccess && dedicatedCalendarValidationState == .valid,
            notificationsReady: notificationAccessStatus == .authorized && notificationPreferences.enabled,
            deepSeekReady: aiSettings.enabled && aiHasKey
        )
        recoveryItems = ReleaseReadinessService.recoveries(
            sources: sourceHealth,
            calendar: calendarAccessStatus,
            notifications: notificationAccessStatus,
            aiFailureCategories: academicAnalyses.compactMap(\.failureCategory)
        )
        outcomeMetrics = try? releaseReadiness.outcomeMetrics()
        calendarWrittenSignalIDs = (try? releaseReadiness.calendarWrittenSignalIDs()) ?? []
        ignoredAcademicAnalysisIDs = (try? releaseReadiness.ignoredAnalysisIDs()) ?? []
        if releaseReadiness.shouldPresentFirstRun() {
            isSetupAssistantPresented = true
        }
    }

    func finishSetupAssistant() {
        releaseReadiness?.markFirstRunPresented()
        isSetupAssistantPresented = false
    }

    func configureCanvas(baseURL: String, token: String) {
        guard let releaseReadiness else { return }
        do {
            try releaseReadiness.configureCanvas(baseURL: baseURL, token: token)
            canvasSetupMessage = "Canvas credentials were saved securely in Keychain."
        } catch {
            canvasSetupMessage = "Canvas could not be configured. Check the exact HTTPS host and token."
        }
        refreshReleaseReadiness()
    }

    func revokeCanvas() {
        do {
            try releaseReadiness?.revokeCanvas()
            canvasSetupMessage = "Canvas credentials were removed. Other integrations were not changed."
        } catch { canvasSetupMessage = "Canvas credentials could not be removed from Keychain." }
        refreshReleaseReadiness()
    }

    func revokeSIweb() {
        do {
            try releaseReadiness?.revokeSIweb()
            siwebSetupMessage = "SIweb authorization was removed. Other integrations were not changed."
        } catch { siwebSetupMessage = "SIweb authorization could not be removed from Keychain." }
        refreshReleaseReadiness()
    }

    func completeSIwebAuthorization(_ message: String, authorized: Bool) async {
        siwebSetupMessage = message
        isSIwebAuthorizationPresented = false
        guard authorized, let backgroundScheduler else {
            refreshReleaseReadiness()
            return
        }
        isRefreshing = true
        _ = await backgroundScheduler.runManual(source: .siweb)
        isRefreshing = false
        await reloadDashboardData()
        await refreshDiagnostics()
        await refreshBackgroundConfiguration()
        refreshReleaseReadiness()
    }

    func setAcademicAnalysisIgnored(_ id: UUID, ignored: Bool) {
        do {
            try releaseReadiness?.setAnalysisIgnored(id, ignored: ignored)
            refreshReleaseReadiness()
        } catch { aiMessage = "The local analysis decision could not be saved." }
    }

    func performRecovery(_ item: RecoveryPresentation) {
        switch item.category {
        case .calendarPermission:
            ReleaseReadinessService.openSystemSettings(for: .calendarPermission)
        case .notificationPermission:
            ReleaseReadinessService.openSystemSettings(for: .notificationPermission)
        default:
            selectedSection = .settings
        }
    }

    func refreshOutlookAuthorization() async {
        if outlookIsPreviewOverride { return }
        guard let outlookAuthorization else {
            outlookStatus = .disconnected
            outlookMessage = "School Outlook authorization is unavailable. Canvas and SIweb remain available."
            return
        }
        await outlookAuthorization.restoreStatus(); outlookStatus = await outlookAuthorization.status
        if let configuration = await outlookAuthorization.currentConfiguration() {
            outlookClientID = configuration.clientID; outlookTenantID = configuration.tenantID
        }
        updateOutlookMessage()
    }
    func configureAndConnectOutlook(clientID: String, tenantID: String) async {
        guard let outlookAuthorization else { return }; isOutlookBusy = true; defer { isOutlookBusy = false }
        do {
            try await outlookAuthorization.configure(clientID: clientID, tenantID: tenantID)
            outlookClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            outlookTenantID = tenantID.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = try await outlookAuthorization.beginAuthorization(); outlookStatus = await outlookAuthorization.status
            updateOutlookMessage()
            guard NSWorkspace.shared.open(url) else {
                await outlookAuthorization.cancelAuthorization(); throw OutlookAuthorizationError.authorizationCancelled
            }
        } catch {
            outlookStatus = await outlookAuthorization.status
            outlookMessage = "Outlook configuration or authorization could not start. Check the registered client and tenant values."
        }
    }
    func handleOutlookCallback(_ url: URL) async {
        guard let outlookAuthorization else { return }; isOutlookBusy = true; defer { isOutlookBusy = false }
        try? await outlookAuthorization.handleCallback(url); outlookStatus = await outlookAuthorization.status
        updateOutlookMessage()
    }
    func disconnectOutlook() async {
        guard let outlookAuthorization else { return }; isOutlookBusy = true; defer { isOutlookBusy = false }
        do {
            _ = try await outlookAuthorization.disconnect(); outlookStatus = await outlookAuthorization.status
            outlookMessage = "School Outlook tokens were removed from Keychain. No mailbox content was changed."
        } catch { outlookMessage = "School Outlook could not be disconnected because Keychain was unavailable." }
    }
    func runOutlookMetadataCheck() async {
        guard let outlookAuthorization else { return }; isOutlookBusy = true; defer { isOutlookBusy = false }
        do {
            let token = try await outlookAuthorization.validAccessToken()
            let result = try await OutlookGraphMetadataProbe().run(accessToken: token)
            outlookStatus = await outlookAuthorization.status
            outlookMessage = result.messageCount == 0
                ? "Connected. The minimum metadata-only check succeeded with no recent item returned."
                : "Connected. The minimum metadata-only check succeeded."
        } catch let error as OutlookGraphError {
            await outlookAuthorization.markRevokedOrClaimsChallenge(claims: error.claims)
            outlookStatus = await outlookAuthorization.status
            outlookMessage = error.category == .claimsChallenge
                ? "Microsoft requires another interactive sign-in for MFA or Conditional Access."
                : "The metadata-only check failed safely. Canvas and SIweb remain available."
        } catch { outlookStatus = await outlookAuthorization.status; updateOutlookMessage() }
    }
    private func updateOutlookMessage() {
        outlookMessage = switch outlookStatus {
        case .disconnected: outlookClientID.isEmpty ? "School Outlook is not configured." : "School Outlook is disconnected."
        case .authorizing: "Continue authorization in the system browser."
        case .connected: "Connected with delegated Mail.ReadBasic. Mail content is not synchronized in this stage."
        case .expired: "School Outlook authorization expired or was revoked. Reconnect interactively."
        case .adminApprovalRequired: "The school tenant requires administrator approval. Outlook remains off."
        case .policyBlocked: "The school tenant policy blocked this app. Outlook remains off."
        }
    }

    func refreshAIConfiguration() {
        guard let aiCoordinator else {
            aiMessage = "AI persistence is unavailable; deterministic screens remain usable."
            return
        }
        do {
            aiSettings = try aiCoordinator.settings()
            aiHasKey = aiCoordinator.hasDeepSeekKey()
            deepSeekUsage = aiCoordinator.deepSeekUsage() ?? DeepSeekUsageSnapshot(
                requestCount: 0, inputTokens: 0, outputTokens: 0, estimatedCostMicrousd: 0
            )
            aiConfirmations = try aiCoordinator.productionPendingConfirmations()
            aiHistory = try aiCoordinator.productionHistory().filter { $0.confirmationState != .pending && $0.confirmationState != .undone }
            let analyses = try academicSignalCoordinator?.analyses() ?? []
            let signals = try academicSignalCoordinator?.activeSignals() ?? []
            academicAnalyses = showsSyntheticAIResultsForQA ? analyses : analyses.filter {
                ProductionAIResultPolicy.includes(provider: $0.provider, model: $0.model)
            }
            academicSignals = showsSyntheticAIResultsForQA ? signals : signals.filter {
                ProductionAIResultPolicy.includes(provider: $0.provider, model: $0.model)
            }
            if aiSettings.enabled && aiSettings.providerKind == .external {
                aiMessage = "DeepSeek is enabled with current consent. Only approved bounded fields may leave this Mac."
            } else if aiSettings.enabled {
                aiMessage = "Deterministic fake provider enabled. No content leaves this Mac."
            } else {
                aiMessage = "AI assistance is off. Deterministic organization remains available."
            }
        } catch { aiMessage = "AI settings could not be loaded. Deterministic synchronization remains available." }
    }

    func setAIAssistanceEnabled(_ enabled: Bool) {
        guard let aiCoordinator else { return }
        do {
            try aiCoordinator.setEnabled(enabled)
            refreshAIConfiguration()
        } catch { aiMessage = "AI settings could not be saved. No source or Calendar data was changed." }
    }

    func saveDeepSeekAPIKey(_ key: String) {
        guard let aiCoordinator else { return }
        do {
            try aiCoordinator.saveDeepSeekKey(key)
            refreshAIConfiguration()
            aiMessage = "DeepSeek API key saved in Keychain. It is never displayed again."
        } catch { aiMessage = "The DeepSeek API key could not be saved. No key was retained in ordinary settings." }
    }

    func removeDeepSeekAPIKey() {
        guard let aiCoordinator else { return }
        do {
            try aiCoordinator.removeDeepSeekKey()
            refreshAIConfiguration()
            aiMessage = "DeepSeek was disabled, consent revoked, and its API key removed from Keychain."
        } catch { aiMessage = "The DeepSeek key could not be removed. DeepSeek remains disabled." }
    }

    func grantDeepSeekConsent(schoolPolicyConfirmed: Bool) {
        guard let aiCoordinator else { return }
        do {
            try aiCoordinator.grantDeepSeekConsent(schoolPolicyConfirmed: schoolPolicyConfirmed)
            refreshAIConfiguration()
        } catch {
            aiMessage = "DeepSeek was not enabled. Save a Keychain API key and confirm the school-policy warning first."
        }
    }

    func revokeDeepSeekConsent() {
        guard let aiCoordinator else { return }
        do { try aiCoordinator.revokeDeepSeekConsent(); refreshAIConfiguration() }
        catch { aiMessage = "Consent could not be updated. DeepSeek remains unavailable." }
    }

    func updateDeepSeekBudgets(runRequests: Int, dailyRequests: Int,
                               runTokens: Int, dailyTokens: Int) {
        guard let aiCoordinator else { return }
        do {
            try aiCoordinator.updateDeepSeekBudgets(
                runRequests: runRequests, dailyRequests: dailyRequests,
                runTokens: runTokens, dailyTokens: dailyTokens
            )
            refreshAIConfiguration()
            aiMessage = "DeepSeek request and token budgets were updated."
        } catch { aiMessage = "DeepSeek budgets were invalid and were not changed." }
    }

    func setDeepSeekDirectHTTPS(_ enabled: Bool) {
        guard let aiCoordinator else { return }
        do {
            try aiCoordinator.setDeepSeekDirectHTTPS(enabled)
            refreshAIConfiguration()
            aiMessage = enabled
                ? "Direct HTTPS is enabled only for api.deepseek.com. FlClash and global network settings were not changed."
                : "DeepSeek uses the macOS system proxy. FlClash and global network settings were not changed."
        } catch {
            aiMessage = "The DeepSeek network route could not be updated. No system network setting was changed."
        }
    }

    func confirmAIResult(_ id: UUID) async {
        guard let aiCoordinator else { return }
        do {
            try aiCoordinator.confirm(id)
            refreshAIConfiguration()
            await reconcileNotificationsAfterAIDecision()
        }
        catch { aiMessage = "The AI decision could not be saved. No downstream action was taken." }
    }

    func correctAIResult(_ id: UUID, title: String?, type: String?, date: Date?) async {
        guard let aiCoordinator else { return }
        do {
            try aiCoordinator.correct(id, correction: AIConfirmationCorrection(
                normalizedTitle: title?.nilIfBlank, suggestedType: type?.nilIfBlank, suggestedDate: date
            ))
            refreshAIConfiguration()
            await reconcileNotificationsAfterAIDecision()
        } catch { aiMessage = "The AI correction could not be saved. No downstream action was taken." }
    }

    func rejectAIResult(_ id: UUID) {
        do { try aiCoordinator?.reject(id); refreshAIConfiguration() }
        catch { aiMessage = "The AI decision could not be saved. No downstream action was taken." }
    }

    func undoAIResult(_ id: UUID) async {
        guard let aiCoordinator else { return }
        do {
            try aiCoordinator.undo(id)
            refreshAIConfiguration()
            await reconcileNotificationsAfterAIDecision()
        }
        catch { aiMessage = "The AI decision could not be undone. Existing confirmed state was preserved." }
    }

    func academicAnalysis(for announcementID: UUID) -> AcademicAnnouncementAnalysis? {
        academicAnalyses.first { $0.announcementID == announcementID }
    }

    func academicSignals(for announcementID: UUID) -> [AcademicSignalRecord] {
        academicSignals.filter { $0.announcementID == announcementID }
    }

    func reprocessAcademicSignals(for announcementID: UUID) async {
        guard let academicSignalCoordinator else { return }
        _ = await academicSignalCoordinator.reprocess(
            announcementID: announcementID,
            locale: language == .english ? "en" : "zh-Hans"
        )
        refreshAIConfiguration()
    }

    func confirmAcademicSignal(_ id: UUID) {
        do {
            try academicSignalCoordinator?.confirm(id)
            recordAcademicHandling(id: id, action: "confirm")
            refreshAIConfiguration()
        }
        catch { aiMessage = "The academic-signal decision could not be saved." }
    }

    func rejectAcademicSignal(_ id: UUID) {
        do {
            try academicSignalCoordinator?.reject(id)
            recordAcademicHandling(id: id, action: "ignore")
            refreshAIConfiguration()
        }
        catch { aiMessage = "The academic-signal decision could not be saved." }
    }

    func correctAcademicSignal(_ id: UUID, category: AcademicSignalCategory,
                               keyRequirement: String, date: Date?, isAllDay: Bool,
                               timeZoneIdentifier: String?, courseID: UUID?) {
        do {
            try academicSignalCoordinator?.correct(id, correction: AcademicSignalCorrection(
                category: category, keyRequirement: keyRequirement, inferredDate: date,
                isAllDay: isAllDay, timeZoneIdentifier: timeZoneIdentifier, courseID: courseID
            ))
            recordAcademicHandling(id: id, action: "correct")
            refreshAIConfiguration()
        } catch { aiMessage = "The academic-signal correction could not be saved." }
    }

    func correctAcademicAnalysis(_ id: UUID, category: AcademicSignalCategory,
                                 keyRequirement: String, date: Date?, isAllDay: Bool,
                                 timeZoneIdentifier: String?, courseID: UUID?) {
        do {
            try academicSignalCoordinator?.correctAnalysis(id, correction: .init(
                category: category, keyRequirement: keyRequirement, inferredDate: date,
                isAllDay: isAllDay, timeZoneIdentifier: timeZoneIdentifier, courseID: courseID))
            refreshAIConfiguration()
        } catch { aiMessage = "The analysis-level correction could not be saved." }
    }

    func undoAcademicSignal(_ id: UUID) {
        do {
            try academicSignalCoordinator?.undo(id)
            refreshAIConfiguration()
            if let calendarService {
                Task {
                    do {
                        _ = try await calendarService.reconcileAcademicSignal(signalID: id)
                        await MainActor.run { self.refreshReleaseReadiness() }
                    } catch {
                        await MainActor.run {
                            self.aiMessage = "The decision was undone, but its app-owned Calendar event could not yet be reconciled. Retry from Settings."
                        }
                    }
                }
            }
        }
        catch { aiMessage = "The academic-signal decision could not be undone." }
    }

    func resetAcademicSignal(_ id: UUID) {
        do { try academicSignalCoordinator?.reset(id); refreshAIConfiguration() }
        catch { aiMessage = "Only a local correction can be reset." }
    }

    func beginAcademicReview(_ id: UUID) {
        if academicReviewStartedAt[id] == nil { academicReviewStartedAt[id] = nowProvider() }
    }

    func previewAcademicSignal(_ id: UUID) async {
        guard let calendarService else {
            aiMessage = "Calendar preview is required before a course schedule change can be confirmed."
            return
        }
        do { calendarChangePreview = try await calendarService.previewAcademicSignal(signalID: id) }
        catch { aiMessage = "Calendar preview is unavailable. No event was changed; correct or ignore this item." }
    }

    func confirmCalendarChangePreview() {
        guard let preview = calendarChangePreview else { return }
        calendarChangePreview = nil
        do {
            if let targetMeetingID = preview.targetMeetingID {
                try academicSignalCoordinator?.confirmPreviewed(
                    preview.signalID, targetMeetingID: targetMeetingID,
                    signalUpdatedAt: preview.signalUpdatedAt
                )
            } else {
                try academicSignalCoordinator?.confirm(preview.signalID)
            }
            recordAcademicHandling(id: preview.signalID, action: "confirm")
            refreshAIConfiguration()
        } catch {
            aiMessage = "This preview is stale or its SIweb meeting is no longer unique. No Calendar event was changed."
            return
        }
        guard let calendarService else { return }
        Task {
            do {
                _ = try await calendarService.reconcileAcademicSignal(signalID: preview.signalID)
                await MainActor.run {
                    self.aiMessage = "The confirmed result was written once to the dedicated Calendar."
                    self.refreshReleaseReadiness()
                }
            } catch {
                await MainActor.run {
                    self.aiMessage = "The decision was saved, but Calendar was not changed. Restore Calendar access and retry the preview."
                }
            }
        }
    }

    private func recordAcademicHandling(id: UUID, action: String) {
        guard let started = academicReviewStartedAt.removeValue(forKey: id) else { return }
        try? releaseReadiness?.recordHandlingDuration(nowProvider().timeIntervalSince(started), action: action)
    }

    private func reconcileNotificationsAfterAIDecision() async {
        guard let notificationService else { return }
        do {
            try await notificationService.reconcileReminders()
        } catch {
            aiMessage = "The AI decision was saved, but deadline notifications could not be updated. They will be reconciled on the next refresh."
        }
    }

    var usesPersistentAIQueue: Bool { aiCoordinator != nil }

    func refreshNotificationConfiguration() async {
        guard let notificationService else {
            notificationMessage = "Notification persistence is unavailable."
            return
        }
        notificationAccessStatus = await notificationService.authorizationState()
        do {
            notificationPreferences = try notificationService.preferences()
            notificationCourses = try notificationService.courseSettings()
            switch notificationAccessStatus {
            case .notDetermined:
                notificationMessage = "Permission has not been requested. Use Enable to ask from this screen."
            case .denied:
                notificationMessage = "Notification permission is denied or was revoked. Sync and other views remain available."
            case .authorized:
                notificationMessage = notificationPreferences.enabled
                    ? "Local notifications are enabled."
                    : "Permission is available, but the notification master switch is off."
            }
        } catch { notificationMessage = "Notification settings could not be loaded. Other features remain available." }
    }

    func enableNotificationsFromUserAction() async {
        guard let notificationService else { return }
        isNotificationBusy = true
        defer { isNotificationBusy = false }
        do {
            guard try await notificationService.requestAccessFromUserAction() else {
                await refreshNotificationConfiguration()
                return
            }
            var preferences = try notificationService.preferences()
            preferences.enabled = true
            try await notificationService.updatePreferences(preferences)
            await refreshNotificationConfiguration()
        } catch { notificationMessage = "Notification permission or settings could not be updated. Other features remain available." }
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        guard let notificationService else { return }
        isNotificationBusy = true
        defer { isNotificationBusy = false }
        do {
            var preferences = try notificationService.preferences()
            preferences.enabled = enabled
            try await notificationService.updatePreferences(preferences)
            await refreshNotificationConfiguration()
        } catch { notificationMessage = "Notification settings could not be updated. Existing settings were preserved." }
    }

    func updateNotificationTiming(
        deadlineOffsets: [Int]? = nil, classLead: Int? = nil,
        quietStart: Int? = nil, quietEnd: Int? = nil
    ) async {
        guard let notificationService else { return }
        do {
            var value = try notificationService.preferences()
            if let deadlineOffsets { value.deadlineOffsetsMinutes = deadlineOffsets }
            if let classLead { value.classLeadMinutes = classLead }
            if let quietStart { value.quietStartMinutes = quietStart }
            if let quietEnd { value.quietEndMinutes = quietEnd }
            try await notificationService.updatePreferences(value)
            await refreshNotificationConfiguration()
        } catch { notificationMessage = "Notification timing could not be updated. Existing settings were preserved." }
    }

    func setCourseNotifications(_ enabled: Bool, courseID: String) async {
        guard let notificationService else { return }
        do {
            try await notificationService.setCourseEnabled(enabled, courseID: courseID)
            await refreshNotificationConfiguration()
        } catch { notificationMessage = "Course notification settings could not be updated." }
    }

    func sendTestNotification() async {
        guard let notificationService else { return }
        do {
            _ = try await notificationService.scheduleTestNotification()
            notificationMessage = "A synthetic test notification is scheduled for about five seconds from now."
        } catch { notificationMessage = "The test notification could not be scheduled." }
    }

    func refreshBackgroundConfiguration() async {
        guard let backgroundScheduler else {
            backgroundMessage = "Background scheduling is unavailable."
            return
        }
        do {
            backgroundConfiguration = try await backgroundScheduler.configuration()
            backgroundItemState = await backgroundScheduler.backgroundItemState()
            backgroundMessage = backgroundStatusMessage()
        } catch { backgroundMessage = "Background settings could not be loaded. Foreground refresh remains available." }
    }

    func setBackgroundEnabled(_ enabled: Bool) async {
        guard let backgroundScheduler else { return }
        isBackgroundBusy = true
        defer { isBackgroundBusy = false }
        do {
            try await backgroundScheduler.setEnabled(enabled)
            await refreshBackgroundConfiguration()
        } catch {
            backgroundMessage = "Background item could not be changed. Foreground refresh remains available."
            await refreshBackgroundConfiguration()
        }
    }

    func openLoginItemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func backgroundStatusMessage() -> String {
        guard backgroundConfiguration.enabled else { return "Background sync is disabled." }
        switch backgroundItemState {
        case .enabled:
            return "Enabled with a 60-minute target while you are logged in and the Mac can run. Missed intervals are recovered after launch, wake, or network return."
        case .requiresApproval:
            return "Enabled in the app, but macOS requires approval in Login Items."
        case .disabled:
            return "The app setting is on, but the macOS Login Item is off. Enable it in System Settings or toggle this setting again."
        case .unavailable:
            return "The macOS background item status is unavailable; foreground use still works."
        }
    }

    func enableCalendarFromUserAction() async {
        guard let calendarService else {
            calendarMessage = "Calendar persistence is unavailable."
            return
        }
        isCalendarBusy = true
        defer { isCalendarBusy = false }
        do {
            guard try await calendarService.requestAccessFromUserAction() else {
                calendarAccessStatus = .denied
                calendarMessage = "Calendar permission was denied. Other app features remain available."
                return
            }
            try await refreshCalendarConfiguration()
        } catch {
            calendarMessage = "Calendar access could not be updated. No event was changed."
        }
    }

    func refreshCalendarConfiguration() async throws {
        guard let calendarService else { return }
        defer { refreshReleaseReadiness() }
        calendarAccessStatus = await calendarService.authorizationStatus()
        guard calendarAccessStatus == .fullAccess else {
            calendarSources = []
            writableCalendars = []
            dedicatedCalendarValidationState = nil
            if try await calendarService.configuredIdentity() == nil {
                calendarMessage = "Full Calendar access is required to configure app-owned events."
            } else {
                calendarMessage = "Calendar permission was revoked. Existing bindings are preserved and no event will be touched."
            }
            return
        }
        calendarSources = try await calendarService.availableSources()
        writableCalendars = try await calendarService.availableWritableCalendars()
        selectedCalendarSourceID = selectedCalendarSourceID ?? calendarSources.first?.identifier
        if let identity = try await calendarService.configuredIdentity() {
            selectedDedicatedCalendarID = identity.calendarIdentifier
            let state = try await calendarService.validateDedicatedCalendar()
            dedicatedCalendarValidationState = state
            calendarMessage = calendarMessage(identity: identity, state: state)
        } else {
            selectedDedicatedCalendarID = nil
            dedicatedCalendarValidationState = nil
            calendarMessage = "Choose a writable source to create, or explicitly select, a dedicated calendar."
        }
    }

    func createDedicatedCalendar() async {
        guard let calendarService, let sourceID = selectedCalendarSourceID else { return }
        isCalendarBusy = true
        defer { isCalendarBusy = false }
        do {
            let identity = try await calendarService.createDedicatedCalendar(sourceIdentifier: sourceID)
            selectedDedicatedCalendarID = identity.calendarIdentifier
            try await refreshCalendarConfiguration()
        } catch {
            calendarMessage = "The dedicated calendar could not be created. No unrelated calendar was changed."
        }
    }

    func selectDedicatedCalendar() async {
        guard let calendarService, let calendarID = selectedDedicatedCalendarID else { return }
        isCalendarBusy = true
        defer { isCalendarBusy = false }
        do {
            _ = try await calendarService.selectDedicatedCalendar(calendarIdentifier: calendarID)
            try await refreshCalendarConfiguration()
        } catch {
            calendarMessage = "The dedicated calendar could not be selected. No event was changed."
        }
    }

    func refreshDiagnostics() async {
        guard let privacyDiagnostics else {
            sourceHealth = [
                DiagnosticSourceHealth(source: SourceKind.canvas.rawValue, category: .notConfigured, lastSuccessfulSync: nil,
                             message: "Not configured.", recoveryAction: "Configure this source before synchronizing."),
                DiagnosticSourceHealth(source: SourceKind.siweb.rawValue, category: .notConfigured, lastSuccessfulSync: nil,
                             message: "Not configured.", recoveryAction: "Configure this source before synchronizing.")
            ]
            diagnosticPreview = "Diagnostic persistence is unavailable. Other local screens remain usable."
            return
        }
        do {
            let subsystems = subsystemHealth()
            let result = try await Task.detached {
                let health = try privacyDiagnostics.sourceHealth()
                let data = try privacyDiagnostics.encodedDiagnosticSnapshot(subsystems: subsystems)
                return (health, data)
            }.value
            sourceHealth = result.0
            refreshReleaseReadiness()
            refreshSourceSetupMessages()
            let data = result.1
            diagnosticPreview = String(decoding: data, as: UTF8.self)
        } catch {
            diagnosticPreview = PrivacyDiagnosticsError.diagnosticExportFailed.description
        }
    }

    private func refreshSourceSetupMessages() {
        func message(for source: SourceKind) -> String {
            guard let health = sourceHealth.first(where: { $0.source == source.rawValue }) else {
                return "\(source.rawValue) is not configured."
            }
            if health.category == .ready {
                let integration: ReleaseSetupIntegration = source == .canvas ? .canvas : .siweb
                if setupItems.first(where: { $0.integration == integration })?.isComplete == true {
                    return "\(source.rawValue) is authorized. Credential fields stay blank for security."
                }
                return setupItems.first(where: { $0.integration == integration })?.detail
                    ?? "\(source.rawValue) is not configured."
            }
            return "\(health.message) \(health.recoveryAction)"
        }
        canvasSetupMessage = message(for: .canvas)
        siwebSetupMessage = message(for: .siweb)
    }

    func clearLocalData(_ category: LocalDataCategory) async {
        guard let privacyDiagnostics else { return }
        isPrivacyBusy = true
        defer { isPrivacyBusy = false }
        do {
            let result = try await Task.detached { try privacyDiagnostics.clear(category) }.value
            _ = result.deletedRows
            privacyMessage = "Clear operation completed. Credentials and Apple Calendar events were not changed."
            if category == .sourceCache {
                // Reconciliation may cancel obsolete local reminders, but the clear
                // operation never sends a Calendar command.
                try? await notificationService?.reconcileReminders()
            }
            await refreshDiagnostics()
            refreshAIConfiguration()
        } catch {
            privacyMessage = "That local data category could not be cleared. No credential or Calendar cleanup was attempted."
        }
    }

    func clearCredentials() async {
        guard let privacyDiagnostics else { return }
        isPrivacyBusy = true
        defer { isPrivacyBusy = false }
        do {
            try await Task.detached { try privacyDiagnostics.clearCredentials() }.value
            privacyMessage = "Canvas, SIweb, and School Outlook credentials were cleared from Keychain. Cached local data and Apple Calendar events were retained."
        } catch {
            privacyMessage = PrivacyDiagnosticsError.credentialClearFailed.description
        }
    }

    func previewCalendarCleanup() async {
        guard let calendarService else {
            privacyMessage = "Calendar cleanup is unavailable; no local data was changed."
            return
        }
        isPrivacyBusy = true
        defer { isPrivacyBusy = false }
        do {
            calendarCleanupPreview = try await calendarService.cleanupPreview()
            privacyMessage = calendarCleanupPreview.isEmpty
                ? "No verified app-owned Calendar events are eligible for cleanup."
                : "Review the verified app-owned events below before deleting them."
        } catch {
            calendarCleanupPreview = []
            privacyMessage = "Calendar cleanup preview requires full access and a valid dedicated calendar. No event was changed."
        }
    }

    func removePreviewedCalendarEvents() async {
        guard let calendarService else { return }
        isPrivacyBusy = true
        defer { isPrivacyBusy = false }
        do {
            let removed = try await calendarService.cleanupPreviewedEvents(
                bindingIDs: Set(calendarCleanupPreview.map(\.id))
            )
            calendarCleanupPreview = []
            _ = removed
            privacyMessage = "Verified app-owned Calendar events were removed from the dedicated calendar."
            await refreshDiagnostics()
        } catch {
            privacyMessage = "Calendar cleanup stopped because ownership could not be revalidated. Unrelated events were not touched."
        }
    }

    func exportDiagnosticsFromUserAction() async {
        guard let privacyDiagnostics else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "campus-dashboard-diagnostics.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let subsystems = subsystemHealth()
            try await Task.detached {
                try privacyDiagnostics.exportDiagnostics(to: url, subsystems: subsystems)
            }.value
            privacyMessage = "Redacted diagnostics exported. The report contains categories and aggregate counts only."
        } catch {
            privacyMessage = PrivacyDiagnosticsError.diagnosticExportFailed.description
        }
    }

    private func subsystemHealth() -> [SubsystemHealth] {
        [
            SubsystemHealth(
                subsystem: "calendar", category: calendarAccessStatus.rawValue,
                recoveryAction: calendarAccessStatus == .fullAccess ? "No action needed." : "Enable or restore Calendar access in Settings."
            ),
            SubsystemHealth(
                subsystem: "notifications", category: notificationAccessStatus.rawValue,
                recoveryAction: notificationAccessStatus == .authorized ? "No action needed." : "Enable or restore Notifications in Settings."
            ),
            SubsystemHealth(
                subsystem: "ai", category: aiSettings.enabled ? "enabled_local" : "disabled",
                recoveryAction: "AI is optional; deterministic synchronization remains available."
            ),
            SubsystemHealth(
                subsystem: "background", category: backgroundItemState.rawValue,
                recoveryAction: backgroundItemState == .enabled ? "No action needed." : "Foreground refresh remains available; review Login Items if desired."
            )
        ]
    }

    func selectScenario(_ scenario: DemoScenario) {
        guard isPreviewMode else { return }
        self.scenario = scenario
        applyScenario(scenario)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if isPreviewMode {
            try? await Task.sleep(for: .milliseconds(250))
            refreshCount += 1
            if scenario == .error || scenario == .loading {
                selectScenario(.populated)
            }
            return
        }
        _ = await backgroundScheduler?.runManual()
        await reloadDashboardData()
        refreshAIConfiguration()
        await refreshDiagnostics()
        await refreshBackgroundConfiguration()
        refreshCount += 1
    }

    func toggleTask(_ id: UUID) {
        guard let index = snapshot.tasks.firstIndex(where: { $0.id == id }) else { return }
        snapshot.tasks[index].isLocallyComplete.toggle()
        let task = snapshot.tasks[index]
        persist(LocalUserStateRecord(
            objectType: "learning_task", objectID: task.id.uuidString,
            isComplete: task.isLocallyComplete, isRead: false, isHidden: false,
            priority: task.localPriority.rawValue, modifiedAt: Date()
        ))
    }

    func toggleAnnouncement(_ id: UUID) {
        guard let index = snapshot.announcements.firstIndex(where: { $0.id == id }) else { return }
        snapshot.announcements[index].isLocallyRead.toggle()
        let announcement = snapshot.announcements[index]
        persist(LocalUserStateRecord(
            objectType: "announcement", objectID: announcement.id.uuidString,
            isComplete: false, isRead: announcement.isLocallyRead, isHidden: false,
            priority: nil, modifiedAt: Date()
        ))
    }

    func rejectConfirmation(_ id: UUID) {
        snapshot.confirmations.removeAll { $0.id == id }
    }

    var dueToday: [LearningTask] {
        let calendar = Calendar.autoupdatingCurrent
        let now = nowProvider()
        return snapshot.tasks.filter {
            guard let due = $0.officialDueAt else { return false }
            return calendar.isDate(due, inSameDayAs: now)
        }
    }

    var nextMeeting: CourseMeeting? {
        let now = nowProvider()
        return snapshot.meetings
            .filter { !$0.isCancelled && $0.end >= now }
            .sorted { $0.start < $1.start }
            .first
    }

    var todaySubtitle: String {
        Localizer.format(nowProvider(), date: .long, time: .omitted, language: language, timeZone: presentationTimeZone)
    }

    var now: Date { nowProvider() }

    func format(_ date: Date, date dateStyle: Date.FormatStyle.DateStyle = .abbreviated,
                time timeStyle: Date.FormatStyle.TimeStyle = .shortened) -> String {
        Localizer.format(date, date: dateStyle, time: timeStyle, language: language, timeZone: presentationTimeZone)
    }

    func relativeTime(_ date: Date) -> String {
        Localizer.relative(date, relativeTo: nowProvider(), language: language)
    }

    func scenarioForEmpty(_ isEmpty: Bool) -> DemoScenario {
        isPreviewMode ? scenario : (isEmpty ? .empty : .populated)
    }

    var unreadAnnouncements: [Announcement] {
        snapshot.announcements.filter { !$0.isLocallyRead }
    }

    func text(_ english: String) -> String {
        Localizer.text(english, language: language)
    }

    func localizedSourceSetupMessage(for source: SourceKind) -> String {
        let storedMessage = source == .canvas ? canvasSetupMessage : siwebSetupMessage
        guard let health = sourceHealth.first(where: { $0.source == source.rawValue }),
              health.category != .ready else {
            return text(storedMessage)
        }
        return [health.message, health.recoveryAction]
            .map(text)
            .joined(separator: " ")
    }

    func title(for section: AppSection) -> String {
        text(section.rawValue)
    }

    private func applyScenario(_ scenario: DemoScenario) {
        guard isPreviewMode else { return }
        switch scenario {
        case .populated:
            snapshot = SyntheticFixtures.populated
        case .empty:
            snapshot = .empty
        case .loading, .error, .permissionDenied:
            snapshot = SyntheticFixtures.populated
        }
        restoreLocalState()
    }

    func reloadDashboardData() async {
        guard !isPreviewMode, let dataReader else {
            if !isPreviewMode { snapshot = .empty }
            return
        }
        do {
            let loaded = try await Task.detached { try dataReader.loadSnapshot() }.value
            snapshot = loaded
            refreshCourseMappings()
            persistenceError = nil
        } catch {
            snapshot = .empty
            persistenceError = "Dashboard data is temporarily unavailable. Existing source data was not replaced."
        }
    }

    func refreshCourseMappings() {
        guard let courseReconciliation else { return }
        do {
            courseMappingDecisions = try courseReconciliation.reconcile()
            persistenceError = nil
        } catch {
            persistenceError = "Course reconciliation is temporarily unavailable. Source courses were not changed."
        }
    }

    func mapCourses(_ id: UUID) { updateCourseMapping(id, action: { try $0.map(id) }) }
    func keepCoursesSeparate(_ id: UUID) { updateCourseMapping(id, action: { try $0.keepSeparate(id) }) }
    func undoCourseMapping(_ id: UUID) { updateCourseMapping(id, action: { try $0.undo(id) }) }
    func resetCourseMapping(_ id: UUID) { updateCourseMapping(id, action: { try $0.reset(id) }) }

    private func updateCourseMapping(
        _ id: UUID, action: (CourseReconciliationService) throws -> Void
    ) {
        guard let courseReconciliation else { return }
        do {
            try action(courseReconciliation)
            courseMappingDecisions = try courseReconciliation.decisions()
            Task {
                await reloadDashboardData()
                await refreshNotificationConfiguration()
            }
        } catch {
            persistenceError = "The local course decision could not be saved. Source courses were not changed."
        }
    }

    private func persist(_ state: LocalUserStateRecord) {
        do {
            try localStateRepository.save(state)
            persistenceError = nil
        } catch {
            persistenceError = "Local state could not be saved. Source data was not changed."
        }
    }

    private func restoreLocalState() {
        do {
            for index in snapshot.tasks.indices {
                if let state = try localStateRepository.state(
                    objectType: "learning_task", objectID: snapshot.tasks[index].id.uuidString
                ) {
                    snapshot.tasks[index].isLocallyComplete = state.isComplete
                    if let priority = state.priority.flatMap(TaskPriority.init(rawValue:)) {
                        snapshot.tasks[index].localPriority = priority
                    }
                }
            }
            for index in snapshot.announcements.indices {
                if let state = try localStateRepository.state(
                    objectType: "announcement", objectID: snapshot.announcements[index].id.uuidString
                ) {
                    snapshot.announcements[index].isLocallyRead = state.isRead
                }
            }
            persistenceError = nil
        } catch {
            persistenceError = "Local state could not be loaded. Source data was not changed."
        }
    }

    private func calendarMessage(
        identity: ManagedCalendarIdentity,
        state: ManagedCalendarValidationState
    ) -> String {
        guard state == .valid else { return "The dedicated calendar needs attention. Revalidate it in Settings." }
        return identity.isICloud
            ? "Dedicated calendar verified in iCloud; iPhone arrival timing is controlled by iCloud."
            : "Dedicated calendar verified; this source is not iCloud and is available only on this Mac/account source."
    }
}
