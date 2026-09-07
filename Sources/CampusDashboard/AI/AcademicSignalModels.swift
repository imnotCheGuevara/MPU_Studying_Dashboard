import Foundation

enum AcademicSignalCategory: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case courseScheduleChange = "course_schedule_change"
    case assignmentDeadline = "assignment_deadline"
    case examTime = "exam_time"
    case other

    var id: Self { self }
}

enum AcademicAnalysisStatus: String, Codable, Sendable {
    case deterministicOnly = "deterministic_only"
    case analyzed
    case failed
    case disabled
}

enum AcademicSignalConfirmationState: String, Codable, Sendable {
    case notRequired = "not_required"
    case pending
    case confirmed
    case corrected
    case rejected
    case undone
}

enum AcademicDecisionOrigin: String, Codable, Sendable {
    case automated
    case userCorrection = "user_correction"
    case localSupervisedRule = "local_supervised_rule"
}

struct AcademicSignalInput: Equatable, Codable, Sendable {
    let announcementID: String
    let title: String
    let visibleTextExcerpt: String
    let courseName: String?
    let courseCode: String?
    let localSection: String?
    let meetingCandidates: [AcademicMeetingCandidate]
    let locale: String

    init(announcementID: String, title: String, visibleTextExcerpt: String,
         courseName: String?, courseCode: String? = nil, localSection: String? = nil,
         meetingCandidates: [AcademicMeetingCandidate] = [], locale: String) {
        self.announcementID = announcementID
        self.title = title
        self.visibleTextExcerpt = visibleTextExcerpt
        self.courseName = courseName
        self.courseCode = courseCode
        self.localSection = localSection
        self.meetingCandidates = meetingCandidates
        self.locale = locale
    }
}

struct AcademicMeetingCandidate: Equatable, Codable, Sendable {
    let meetingID: UUID
    let courseCode: String
    let section: String?
    let startsAt: Date
    let endsAt: Date
    let timeZoneIdentifier: String
    let location: String
}

enum AcademicAudienceResolution: String, Codable, Sendable {
    case noTarget = "no_target"
    case resolved
    case pendingReview = "pending_review"
}

struct AcademicSignalSuggestion: Equatable, Codable, Sendable {
    let category: AcademicSignalCategory
    let evidence: String
    let keyRequirement: String
    let inferredDate: Date?
    let isAllDay: Bool
    let timeZoneIdentifier: String?
    let confidence: Double
    let reason: String
    let conflicts: [String]
}

struct AcademicSignalProviderResponse: Equatable, Codable, Sendable {
    let primaryCategory: AcademicSignalCategory
    let signals: [AcademicSignalSuggestion]
}

protocol AcademicSignalProvider: Sendable {
    var providerName: String { get }
    var modelName: String { get }
    func validateAvailability() throws
    func beginRun() async
    func academicSignals(for input: AcademicSignalInput) async throws -> Data
}

struct AcademicAnnouncementAnalysis: Identifiable, Equatable, Sendable {
    let id: UUID
    let rawSourceRecordID: UUID
    let announcementID: UUID
    let sourceAccountID: String
    let sourceObjectID: String
    let contentHash: String
    let primaryCategory: AcademicSignalCategory
    let status: AcademicAnalysisStatus
    let provider: String
    let model: String
    let promptVersion: String
    let schemaVersion: String
    let failureCategory: String?
    let createdAt: Date
    let updatedAt: Date
}

struct AcademicSignalRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let analysisID: UUID
    let announcementID: UUID
    let sourceAccountID: String
    let sourceObjectID: String
    let category: AcademicSignalCategory
    let evidence: String
    let keyRequirement: String
    let inferredDate: Date?
    let isAllDay: Bool
    let timeZoneIdentifier: String?
    let confidence: Double
    let reason: String
    let conflicts: [String]
    let provider: String
    let model: String
    let promptVersion: String
    let schemaVersion: String
    let confirmationState: AcademicSignalConfirmationState
    let adoptedCategory: AcademicSignalCategory?
    let adoptedDate: Date?
    let adoptedIsAllDay: Bool?
    let courseID: UUID?
    let adoptedKeyRequirement: String?
    let adoptedTimeZoneIdentifier: String?
    let decisionOrigin: AcademicDecisionOrigin
    let personalizationRuleVersion: String?
    let targetMeetingID: UUID?
    let audienceResolution: AcademicAudienceResolution
    let createdAt: Date
    let updatedAt: Date

    var requiresDateConfirmation: Bool { inferredDate != nil }

    init(
        id: UUID,
        analysisID: UUID,
        announcementID: UUID,
        sourceAccountID: String,
        sourceObjectID: String,
        category: AcademicSignalCategory,
        evidence: String,
        keyRequirement: String,
        inferredDate: Date?,
        isAllDay: Bool,
        timeZoneIdentifier: String?,
        confidence: Double,
        reason: String,
        conflicts: [String],
        provider: String,
        model: String,
        promptVersion: String,
        schemaVersion: String,
        confirmationState: AcademicSignalConfirmationState,
        adoptedCategory: AcademicSignalCategory?,
        adoptedDate: Date?,
        adoptedIsAllDay: Bool?,
        courseID: UUID? = nil,
        adoptedKeyRequirement: String? = nil,
        adoptedTimeZoneIdentifier: String? = nil,
        decisionOrigin: AcademicDecisionOrigin = .automated,
        personalizationRuleVersion: String? = nil,
        targetMeetingID: UUID? = nil,
        audienceResolution: AcademicAudienceResolution = .noTarget,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.analysisID = analysisID
        self.announcementID = announcementID
        self.sourceAccountID = sourceAccountID
        self.sourceObjectID = sourceObjectID
        self.category = category
        self.evidence = evidence
        self.keyRequirement = keyRequirement
        self.inferredDate = inferredDate
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.confidence = confidence
        self.reason = reason
        self.conflicts = conflicts
        self.provider = provider
        self.model = model
        self.promptVersion = promptVersion
        self.schemaVersion = schemaVersion
        self.confirmationState = confirmationState
        self.adoptedCategory = adoptedCategory
        self.adoptedDate = adoptedDate
        self.adoptedIsAllDay = adoptedIsAllDay
        self.courseID = courseID
        self.adoptedKeyRequirement = adoptedKeyRequirement
        self.adoptedTimeZoneIdentifier = adoptedTimeZoneIdentifier
        self.decisionOrigin = decisionOrigin
        self.personalizationRuleVersion = personalizationRuleVersion
        self.targetMeetingID = targetMeetingID
        self.audienceResolution = audienceResolution
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct AcademicSignalCorrection: Equatable, Codable, Sendable {
    let category: AcademicSignalCategory
    let keyRequirement: String
    let inferredDate: Date?
    let isAllDay: Bool
    let timeZoneIdentifier: String?
    let courseID: UUID?

    init(category: AcademicSignalCategory, keyRequirement: String = "Review this academic update.",
         inferredDate: Date?, isAllDay: Bool, timeZoneIdentifier: String? = nil,
         courseID: UUID? = nil) {
        self.category = category
        self.keyRequirement = keyRequirement
        self.inferredDate = inferredDate
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.courseID = courseID
    }
}

struct AcademicProviderFailurePresentation: Equatable, Sendable {
    let categoryKey: String
    let retryable: Bool
    let recoveryKey: String

    static func safe(_ raw: String?) -> Self? {
        guard let raw else { return nil }
        switch raw {
        case "consent_required", "configuration":
            return .init(categoryKey: "AI consent or configuration", retryable: false,
                         recoveryKey: "Review AI settings in Campus Dashboard.")
        case "missing_credential", "keychain_denied", "keychain_unavailable":
            return .init(categoryKey: "API key unavailable in Keychain", retryable: false,
                         recoveryKey: "Review the API key in Campus Dashboard settings.")
        case "invalid_request":
            return .init(categoryKey: "Provider request configuration", retryable: false,
                         recoveryKey: "Review AI settings in Campus Dashboard.")
        case "offline", "timed_out", "service_unavailable":
            return .init(categoryKey: "Temporary connection or service issue", retryable: true,
                         recoveryKey: "Retry later or review the app's DeepSeek route setting.")
        case "unauthorized", "forbidden":
            return .init(categoryKey: "Provider authorization rejected", retryable: false,
                         recoveryKey: "Replace or verify the API key in Campus Dashboard settings.")
        case "insufficient_balance":
            return .init(categoryKey: "Provider balance unavailable", retryable: false,
                         recoveryKey: "Review the provider account, then retry here.")
        case "rate_limited":
            return .init(categoryKey: "Provider rate limit", retryable: true,
                         recoveryKey: "Wait, then reprocess this announcement.")
        case "budget_exceeded":
            return .init(categoryKey: "Local AI budget reached", retryable: false,
                         recoveryKey: "Review the local AI budget in Campus Dashboard settings.")
        case "malformed_response", "root_missing_key", "root_unknown_key",
             "signal_missing_core_key", "signal_unknown_key", "invalid_category",
             "invalid_primary_index", "invalid_date", "invalid_timezone", "bounds_violation",
             "type_mismatch", "model_mismatch", "tool_call_rejected", "truncated",
             "content_filtered":
            return .init(categoryKey: "Provider response could not be safely used", retryable: false,
                         recoveryKey: "Use the retained local result or reprocess later.")
        case "cancelled":
            return .init(categoryKey: "Analysis cancelled", retryable: true,
                         recoveryKey: "Reprocess when ready.")
        default:
            return .init(categoryKey: "Provider unavailable", retryable: false,
                         recoveryKey: "Use the retained local result or review AI settings.")
        }
    }
}

struct AcademicSignalAuditRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let signalID: UUID
    let action: String
    let previousState: AcademicSignalConfirmationState
    let newState: AcademicSignalConfirmationState
    let correction: AcademicSignalCorrection?
    let occurredAt: Date
}

enum AcademicSignalValidationError: String, Error, Equatable, CaseIterable, Sendable {
    case rootMissingKey = "root_missing_key"
    case rootUnknownKey = "root_unknown_key"
    case signalMissingCoreKey = "signal_missing_core_key"
    case signalUnknownKey = "signal_unknown_key"
    case invalidCategory = "invalid_category"
    case invalidPrimaryIndex = "invalid_primary_index"
    case invalidDate = "invalid_date"
    case invalidTimezone = "invalid_timezone"
    case boundsViolation = "bounds_violation"
    case typeMismatch = "type_mismatch"
    case other
}

enum AcademicSignalOutputValidator {
    static let maximumOutputBytes = 48 * 1_024
    private static let rootKeys: Set<String> = ["primaryCategory", "signals"]
    private static let signalKeys: Set<String> = [
        "category", "evidence", "keyRequirement", "inferredDate", "isAllDay",
        "timeZoneIdentifier", "confidence", "reason", "conflicts"
    ]
    private static let requiredSignalKeys: Set<String> = [
        "category", "evidence", "keyRequirement", "isAllDay", "confidence", "reason", "conflicts"
    ]

    static func decode(_ data: Data) throws -> AcademicSignalProviderResponse {
        guard !data.isEmpty, data.count <= maximumOutputBytes else {
            throw AcademicSignalValidationError.boundsViolation
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw AcademicSignalValidationError.typeMismatch
        }
        let actualRootKeys = Set(root.keys)
        guard rootKeys.isSubset(of: actualRootKeys) else {
            throw AcademicSignalValidationError.rootMissingKey
        }
        guard actualRootKeys.isSubset(of: rootKeys) else {
            throw AcademicSignalValidationError.rootUnknownKey
        }
        guard let categoryText = root["primaryCategory"] as? String else {
            throw AcademicSignalValidationError.typeMismatch
        }
        guard let primary = AcademicSignalCategory(rawValue: categoryText) else {
            throw AcademicSignalValidationError.invalidCategory
        }
        guard let rawSignals = root["signals"] as? [[String: Any]] else {
            throw AcademicSignalValidationError.typeMismatch
        }
        guard rawSignals.count <= 8 else { throw AcademicSignalValidationError.boundsViolation }

        let formatter = ISO8601DateFormatter()
        let signals = try rawSignals.map { value -> AcademicSignalSuggestion in
            let keys = Set(value.keys)
            guard requiredSignalKeys.isSubset(of: keys) else {
                throw AcademicSignalValidationError.signalMissingCoreKey
            }
            guard keys.isSubset(of: signalKeys) else {
                throw AcademicSignalValidationError.signalUnknownKey
            }
            guard let rawCategory = value["category"] as? String else {
                throw AcademicSignalValidationError.typeMismatch
            }
            guard let category = AcademicSignalCategory(rawValue: rawCategory), category != .other else {
                throw AcademicSignalValidationError.invalidCategory
            }
            guard let evidence = value["evidence"] as? String,
                  let requirement = value["keyRequirement"] as? String,
                  let allDay = value["isAllDay"] as? Bool,
                  let confidence = value["confidence"] as? NSNumber,
                  let reason = value["reason"] as? String,
                  let conflicts = value["conflicts"] as? [String] else {
                throw AcademicSignalValidationError.typeMismatch
            }
            guard !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  evidence.count <= 280, !requirement.isEmpty, requirement.count <= 400,
                  (0...1).contains(confidence.doubleValue), !reason.isEmpty, reason.count <= 600,
                  conflicts.count <= 8, conflicts.allSatisfy({ !$0.isEmpty && $0.count <= 240 }) else {
                throw AcademicSignalValidationError.boundsViolation
            }
            let date: Date?
            if value["inferredDate"] == nil || value["inferredDate"] is NSNull { date = nil }
            else if let text = value["inferredDate"] as? String, let parsed = formatter.date(from: text) { date = parsed }
            else if value["inferredDate"] is String { throw AcademicSignalValidationError.invalidDate }
            else { throw AcademicSignalValidationError.typeMismatch }
            let zone: String?
            if value["timeZoneIdentifier"] == nil || value["timeZoneIdentifier"] is NSNull { zone = nil }
            else if let text = value["timeZoneIdentifier"] as? String,
                    text.count <= 80, TimeZone(identifier: text) != nil { zone = text }
            else if value["timeZoneIdentifier"] is String { throw AcademicSignalValidationError.invalidTimezone }
            else { throw AcademicSignalValidationError.typeMismatch }
            if date == nil && allDay { throw AcademicSignalValidationError.invalidDate }
            if date == nil && zone != nil { throw AcademicSignalValidationError.invalidTimezone }
            return AcademicSignalSuggestion(
                category: category, evidence: evidence, keyRequirement: requirement,
                inferredDate: date, isAllDay: allDay, timeZoneIdentifier: zone,
                confidence: confidence.doubleValue, reason: reason, conflicts: conflicts
            )
        }
        if signals.isEmpty && primary != .other { throw AcademicSignalValidationError.invalidPrimaryIndex }
        if !signals.isEmpty && (primary == .other || !signals.contains(where: { $0.category == primary })) {
            throw AcademicSignalValidationError.invalidPrimaryIndex
        }
        return AcademicSignalProviderResponse(primaryCategory: primary, signals: signals)
    }
}
