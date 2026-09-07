import Foundation

enum ProductionAIResultPolicy {
    static func includes(provider: String, model: String) -> Bool {
        let identity = "\(provider) \(model)".lowercased()
        return !identity.contains("fixture") && !identity.contains("synthetic")
    }
}

enum AIProviderKind: String, Codable, Sendable {
    case deterministicFake = "deterministic_fake"
    case external
}

struct AIAssistanceSettings: Equatable, Sendable {
    var enabled: Bool
    var providerKind: AIProviderKind
    var providerDisclosure: String?
    var transmittedFields: String?
    var retentionPolicy: String?
    var consentedAt: Date?
    var consentVersion: String? = nil
    var consentSignature: String? = nil
    var schoolPolicyConfirmed: Bool = false
    var providerModel: String? = nil
    var perRunRequestBudget: Int = 10
    var dailyRequestBudget: Int = 50
    var perRunTokenBudget: Int = 20_000
    var dailyTokenBudget: Int = 100_000
    var directHTTPSForDeepSeek: Bool = false
    var updatedAt: Date

    var mayUseProvider: Bool {
        guard enabled else { return false }
        if providerKind == .deterministicFake { return true }
        return providerDisclosure?.isEmpty == false
            && transmittedFields?.isEmpty == false
            && retentionPolicy?.isEmpty == false
            && consentedAt != nil
    }
}

struct AIKnownObjectSummary: Equatable, Codable, Sendable {
    let objectID: String
    let objectType: String
    let title: String
    let type: String?
    let date: Date?
}

struct AIParseInput: Equatable, Codable, Sendable {
    let source: SourceKind
    let objectType: String
    let objectID: String
    let title: String
    let officialType: String
    let courseName: String?
    let officialDueAt: Date?
    let minimalText: String
    let language: String
    let knownObjectSummaries: [AIKnownObjectSummary]
    let sourceURL: String?
}

struct AIProviderResponse: Equatable, Codable, Sendable {
    let normalizedTitle: String?
    let suggestedType: String?
    let officialDateEcho: Date?
    let suggestedDate: Date?
    let relatedObjectIDs: [String]
    let actionItems: [String]
    let confidence: Double
    let rationale: String
    let hasConflict: Bool
    let changeSummary: String
    let uncertain: Bool

    enum CodingKeys: String, CodingKey {
        case normalizedTitle, suggestedType, officialDateEcho, suggestedDate
        case relatedObjectIDs, actionItems, confidence, rationale, hasConflict, changeSummary, uncertain
    }

    init(
        normalizedTitle: String?, suggestedType: String?, officialDateEcho: Date?,
        suggestedDate: Date?, relatedObjectIDs: [String], actionItems: [String],
        confidence: Double, rationale: String, hasConflict: Bool,
        changeSummary: String, uncertain: Bool
    ) {
        self.normalizedTitle = normalizedTitle
        self.suggestedType = suggestedType
        self.officialDateEcho = officialDateEcho
        self.suggestedDate = suggestedDate
        self.relatedObjectIDs = relatedObjectIDs
        self.actionItems = actionItems
        self.confidence = confidence
        self.rationale = rationale
        self.hasConflict = hasConflict
        self.changeSummary = changeSummary
        self.uncertain = uncertain
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let normalizedTitle { try container.encode(normalizedTitle, forKey: .normalizedTitle) }
        else { try container.encodeNil(forKey: .normalizedTitle) }
        if let suggestedType { try container.encode(suggestedType, forKey: .suggestedType) }
        else { try container.encodeNil(forKey: .suggestedType) }
        if let officialDateEcho { try container.encode(officialDateEcho, forKey: .officialDateEcho) }
        else { try container.encodeNil(forKey: .officialDateEcho) }
        if let suggestedDate { try container.encode(suggestedDate, forKey: .suggestedDate) }
        else { try container.encodeNil(forKey: .suggestedDate) }
        try container.encode(relatedObjectIDs, forKey: .relatedObjectIDs)
        try container.encode(actionItems, forKey: .actionItems)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(rationale, forKey: .rationale)
        try container.encode(hasConflict, forKey: .hasConflict)
        try container.encode(changeSummary, forKey: .changeSummary)
        try container.encode(uncertain, forKey: .uncertain)
    }
}

protocol AIParsingProvider: Sendable {
    var providerName: String { get }
    var modelName: String { get }
    func structuredSuggestion(for input: AIParseInput) async throws -> Data
    func validateAvailability() throws
    func beginRun() async
}

extension AIParsingProvider {
    func validateAvailability() throws {}
    func beginRun() async {}
}

enum AIParsingError: Error, Equatable, CustomStringConvertible {
    case disabled
    case consentRequired
    case invalidOutput(String)
    case missingTarget
    case invalidTransition
    case immutableOfficialDate
    case missingCredential
    case budgetExceeded

    var description: String {
        switch self {
        case .disabled: "AI assistance is disabled. Deterministic organization remains available."
        case .consentRequired: "External AI requires provider disclosure, transmitted-field disclosure, retention information, and consent."
        case .invalidOutput(let reason): "AI output was rejected: \(reason)"
        case .missingTarget: "The local target record no longer exists."
        case .invalidTransition: "This confirmation action is not valid for the current state."
        case .immutableOfficialDate: "Official dates cannot be changed by AI confirmation."
        case .missingCredential: "The DeepSeek API key is unavailable in Keychain."
        case .budgetExceeded: "The configured DeepSeek request or token budget was reached."
        }
    }
}

enum AIConfirmationState: String, Codable, Sendable {
    case pending
    case confirmed
    case corrected
    case rejected
    case undone
    case failed
}

enum AIConfirmationAction: String, Sendable {
    case confirm
    case correct
    case reject
    case undo
}

struct AIParseRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let rawSourceRecordID: UUID
    let targetObjectType: String
    let targetObjectID: String
    let inputHash: String
    let provider: String
    let model: String
    let promptVersion: String
    let schemaVersion: String
    let suggestedType: String?
    let normalizedTitle: String?
    let officialDateEcho: Date?
    let suggestedDate: Date?
    let relatedObjectIDs: [String]
    let actionItems: [String]
    let confidence: Double
    let rationale: String
    let hasConflict: Bool
    let changeSummary: String
    let confirmationState: AIConfirmationState
    let failureCategory: String?
    let adoptedNormalizedTitle: String?
    let adoptedType: String?
    let adoptedDate: Date?
    let sourceSummary: String
    let sourceURL: String?
    let createdAt: Date
    let updatedAt: Date

    var suggestedDateIsInferred: Bool { suggestedDate != nil }
}

struct AIConfirmationCorrection: Equatable, Codable, Sendable {
    let normalizedTitle: String?
    let suggestedType: String?
    let suggestedDate: Date?
}

struct AIConfirmationAuditRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let parseResultID: UUID
    let action: AIConfirmationAction
    let previousState: AIConfirmationState
    let newState: AIConfirmationState
    let correction: AIConfirmationCorrection?
    let occurredAt: Date
}

struct AIProcessingOutcome: Equatable, Sendable {
    let deterministicType: String?
    let parseResult: AIParseRecord?
    let failureCategory: String?
}
