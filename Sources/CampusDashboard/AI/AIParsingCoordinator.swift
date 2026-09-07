import CryptoKit
import Foundation

final class AIParsingCoordinator: @unchecked Sendable {
    static let promptVersion = "canvas-organize-v2"
    static let schemaVersion = "2"
    static let maximumKnownObjects = 8

    private let database: SQLiteDatabase
    private let persistence: AIPersistence
    private let provider: any AIParsingProvider
    private let deepSeekConfiguration: DeepSeekConfigurationService?
    private let clock: any Clock
    private let ids: any IDGenerator
    private let rules = DeterministicOrganizationRules()

    init(
        database: SQLiteDatabase,
        provider: any AIParsingProvider = DeterministicFakeAIProvider(),
        deepSeekConfiguration: DeepSeekConfigurationService? = nil,
        clock: any Clock = SystemClock(), ids: any IDGenerator = SystemIDGenerator()
    ) {
        self.database = database
        self.persistence = AIPersistence(database: database)
        self.provider = provider
        self.deepSeekConfiguration = deepSeekConfiguration
        self.clock = clock
        self.ids = ids
    }

    func settings() throws -> AIAssistanceSettings {
        var value = try persistence.settings()
        if value.providerKind == .external, value.enabled,
           (!DeepSeekDisclosure.isCurrent(value) || deepSeekConfiguration?.hasKey() != true) {
            value.enabled = false
            value.consentedAt = nil
            value.consentVersion = nil
            value.consentSignature = nil
            value.schoolPolicyConfirmed = false
            value.updatedAt = clock.now
            try persistence.saveSettings(value)
        }
        return value
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled { try provider.validateAvailability() }
        var value = try persistence.settings()
        if deepSeekConfiguration == nil {
            value.providerKind = .deterministicFake
        }
        value.enabled = enabled
        value.updatedAt = clock.now
        try persistence.saveSettings(value)
    }

    func hasDeepSeekKey() -> Bool { deepSeekConfiguration?.hasKey() ?? false }
    func deepSeekUsage() -> DeepSeekUsageSnapshot? { try? deepSeekConfiguration?.currentUsage() }
    func saveDeepSeekKey(_ key: String) throws { try deepSeekConfiguration?.saveKey(key) }
    func removeDeepSeekKey() throws { try deepSeekConfiguration?.removeKey() }
    func grantDeepSeekConsent(schoolPolicyConfirmed: Bool) throws {
        try deepSeekConfiguration?.grantCurrentConsent(schoolPolicyConfirmed: schoolPolicyConfirmed)
    }
    func revokeDeepSeekConsent() throws { try deepSeekConfiguration?.disableAndRevoke() }
    func updateDeepSeekBudgets(runRequests: Int, dailyRequests: Int, runTokens: Int, dailyTokens: Int) throws {
        try deepSeekConfiguration?.updateBudgets(runRequests: runRequests, dailyRequests: dailyRequests,
                                                  runTokens: runTokens, dailyTokens: dailyTokens)
    }
    func setDeepSeekDirectHTTPS(_ enabled: Bool) throws {
        try deepSeekConfiguration?.setDirectHTTPS(enabled)
    }

    func pendingConfirmations() throws -> [AIParseRecord] {
        try persistence.records(states: [.pending, .undone])
    }

    func history() throws -> [AIParseRecord] { try persistence.records() }

    func processPendingCanvasRecords(limit: Int = 100) async -> [AIProcessingOutcome] {
        guard (try? persistence.settings().enabled) == true else { return [] }
        let rows = (try? database.query(
            """
            SELECT raw_source_records.id AS raw_id, raw_source_records.source_account_id,
              raw_source_records.source_object_id, raw_source_records.object_type,
              raw_source_records.payload
            FROM raw_source_records
            JOIN source_accounts ON source_accounts.id=raw_source_records.source_account_id
            WHERE source_accounts.source_kind='Canvas'
              AND raw_source_records.object_type='learning_task'
              AND NOT EXISTS (
                SELECT 1 FROM ai_parse_results
                WHERE ai_parse_results.raw_source_record_id=raw_source_records.id
                  AND ai_parse_results.provider=? AND ai_parse_results.model=?
                  AND ai_parse_results.prompt_version=? AND ai_parse_results.schema_version=?
              )
            ORDER BY raw_source_records.fetched_at, raw_source_records.id
            LIMIT ?
            """,
            bindings: [
                .text(provider.providerName), .text(provider.modelName),
                .text(Self.promptVersion), .text(Self.schemaVersion),
                .integer(Int64(max(0, limit)))
            ]
        )) ?? []
        var outcomes: [AIProcessingOutcome] = []
        await provider.beginRun()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        for row in rows {
            guard !Task.isCancelled,
                  let rawText = row.string("raw_id"), let rawID = UUID(uuidString: rawText),
                  let accountID = row.string("source_account_id"),
                  let sourceObjectID = row.string("source_object_id"),
                  let objectType = row.string("object_type"), let payload = row.data("payload"),
                  let raw = try? decoder.decode(RawSyncRecord.self, from: payload),
                  let target = try? targetInput(
                    accountID: accountID, sourceObjectID: sourceObjectID,
                    objectType: objectType, raw: raw
                  )
            else { continue }
            outcomes.append(await process(rawSourceRecordID: rawID, input: target))
        }
        return outcomes
    }

    func auditTrail(parseResultID: UUID) throws -> [AIConfirmationAuditRecord] {
        try persistence.audits(parseResultID: parseResultID)
    }

    func process(rawSourceRecordID: UUID, input original: AIParseInput) async -> AIProcessingOutcome {
        let localSourceURL = original.sourceURL
        let input = Self.minimalInput(original)
        let deterministic = rules.normalizedType(title: input.title, officialType: input.officialType)
        let settings: AIAssistanceSettings
        do { settings = try persistence.settings() }
        catch { return AIProcessingOutcome(deterministicType: deterministic, parseResult: nil, failureCategory: "persistence") }
        guard settings.enabled else {
            return AIProcessingOutcome(deterministicType: deterministic, parseResult: nil, failureCategory: nil)
        }
        guard input.source == .canvas else {
            return AIProcessingOutcome(
                deterministicType: deterministic, parseResult: nil,
                failureCategory: "unsupported_source"
            )
        }
        guard settings.mayUseProvider else {
            return AIProcessingOutcome(deterministicType: deterministic, parseResult: nil, failureCategory: "consent_required")
        }

        let inputHash = Self.hash(input)
        do {
            let data = try await provider.structuredSuggestion(for: input)
            let output = try AIStructuredOutputValidator.decode(data, input: input)
            let now = clock.now
            let record = AIParseRecord(
                id: ids.next(), rawSourceRecordID: rawSourceRecordID,
                targetObjectType: input.objectType, targetObjectID: input.objectID,
                inputHash: inputHash, provider: provider.providerName, model: provider.modelName,
                promptVersion: Self.promptVersion, schemaVersion: Self.schemaVersion,
                suggestedType: output.suggestedType, normalizedTitle: output.normalizedTitle,
                officialDateEcho: output.officialDateEcho, suggestedDate: output.suggestedDate,
                relatedObjectIDs: output.relatedObjectIDs,
                actionItems: output.actionItems, confidence: output.confidence,
                rationale: output.rationale, hasConflict: output.hasConflict || output.uncertain,
                changeSummary: output.changeSummary, confirmationState: .pending,
                failureCategory: nil, adoptedNormalizedTitle: nil,
                adoptedType: nil, adoptedDate: nil, sourceSummary: input.minimalText,
                sourceURL: localSourceURL, createdAt: now, updatedAt: now
            )
            let stored = try persistence.save(record, output: data)
            return AIProcessingOutcome(deterministicType: deterministic, parseResult: stored, failureCategory: nil)
        } catch {
            let failureCategory: String
            if let deepSeek = error as? DeepSeekProviderError { failureCategory = deepSeek.category.rawValue }
            else if error as? AIParsingError == .budgetExceeded { failureCategory = "budget_exceeded" }
            else if error as? AIParsingError == .missingCredential { failureCategory = "missing_credential" }
            else { failureCategory = "invalid_output" }
            let now = clock.now
            let record = AIParseRecord(
                id: ids.next(), rawSourceRecordID: rawSourceRecordID,
                targetObjectType: input.objectType, targetObjectID: input.objectID,
                inputHash: inputHash, provider: provider.providerName, model: provider.modelName,
                promptVersion: Self.promptVersion, schemaVersion: Self.schemaVersion,
                suggestedType: nil, normalizedTitle: nil, officialDateEcho: input.officialDueAt,
                suggestedDate: nil, relatedObjectIDs: [], actionItems: [], confidence: 0,
                rationale: "Provider output was rejected without affecting synchronized data.",
                hasConflict: true, changeSummary: "AI suggestion unavailable.",
                confirmationState: .failed, failureCategory: failureCategory,
                adoptedNormalizedTitle: nil, adoptedType: nil, adoptedDate: nil,
                sourceSummary: input.minimalText, sourceURL: localSourceURL,
                createdAt: now, updatedAt: now
            )
            _ = try? persistence.save(record, output: nil)
            return AIProcessingOutcome(
                deterministicType: deterministic, parseResult: nil, failureCategory: failureCategory
            )
        }
    }

    func confirm(_ id: UUID) throws { try transition(id, action: .confirm, correction: nil) }

    func correct(_ id: UUID, correction: AIConfirmationCorrection) throws {
        try transition(id, action: .correct, correction: correction)
    }

    func reject(_ id: UUID) throws { try transition(id, action: .reject, correction: nil) }

    func undo(_ id: UUID) throws {
        guard let record = try persistence.record(id: id) else {
            throw AIParsingError.invalidTransition
        }
        if record.confirmationState == .undone { return }
        guard [.confirmed, .corrected, .rejected].contains(record.confirmationState) else {
            throw AIParsingError.invalidTransition
        }
        let now = clock.now
        try database.transaction {
            let transitionSequence = try persistence.auditCount(parseResultID: id) + 1
            if record.confirmationState != .rejected {
                try persistence.undoSuggestion(
                    record, restoredAt: now, transitionSequence: transitionSequence
                )
            }
            try persistence.setAdoptedValues(
                id: id, title: nil, type: nil, date: nil, at: now
            )
            try persistence.updateState(id: id, state: .undone, at: now)
            try persistence.addAudit(AIConfirmationAuditRecord(
                id: ids.next(), parseResultID: id, action: .undo,
                previousState: record.confirmationState, newState: .undone,
                correction: nil, occurredAt: now
            ))
        }
    }

    private func transition(
        _ id: UUID, action: AIConfirmationAction, correction: AIConfirmationCorrection?
    ) throws {
        guard let record = try persistence.record(id: id),
              [.pending, .undone].contains(record.confirmationState)
        else { throw AIParsingError.invalidTransition }
        let next: AIConfirmationState = action == .reject ? .rejected : (action == .correct ? .corrected : .confirmed)
        let now = clock.now
        let adoptedTitle = correction == nil ? record.normalizedTitle : correction?.normalizedTitle
        let adoptedType = correction == nil ? record.suggestedType : correction?.suggestedType
        let adoptedDate = correction == nil ? record.suggestedDate : correction?.suggestedDate
        try database.transaction {
            let transitionSequence = try persistence.auditCount(parseResultID: id) + 1
            if next != .rejected {
                try persistence.applySuggestion(
                    record, correction: correction, confirmedAt: now,
                    transitionSequence: transitionSequence
                )
            }
            try persistence.setAdoptedValues(
                id: id,
                title: next == .rejected ? nil : adoptedTitle,
                type: next == .rejected ? nil : adoptedType,
                date: next == .rejected ? nil : adoptedDate,
                at: now
            )
            try persistence.updateState(id: id, state: next, at: now)
            try persistence.addAudit(AIConfirmationAuditRecord(
                id: ids.next(), parseResultID: id, action: action,
                previousState: record.confirmationState, newState: next,
                correction: correction, occurredAt: now
            ))
        }
    }

    private func targetInput(
        accountID: String, sourceObjectID: String, objectType: String, raw: RawSyncRecord
    ) throws -> AIParseInput? {
        let table: String
        switch objectType {
        case "learning_task": table = "learning_tasks"
        case "announcement": table = "announcements"
        default: return nil
        }
        guard let target = try database.query(
            """
            SELECT \(table).*, courses.name AS course_name
            FROM \(table) LEFT JOIN courses ON courses.id=\(table).course_id
            WHERE \(table).source_account_id=? AND \(table).source_object_id=?
            """,
            bindings: [.text(accountID), .text(sourceObjectID)]
        ).first, let targetID = target.string("id"), let title = target.string("title") else { return nil }
        let officialType = target.string("official_type") ?? "announcement"
        let summary: String? = raw.fields["summary"] ?? nil
        let rawTitle: String? = raw.fields["title"] ?? nil
        let minimalText = summary ?? rawTitle ?? title
        let knownObjects = try knownObjectContext(
            courseID: target.string("course_id"), excludingObjectID: targetID
        )
        return AIParseInput(
            source: .canvas, objectType: objectType, objectID: targetID, title: title,
            officialType: officialType, courseName: target.string("course_name"),
            officialDueAt: target.double("official_due_at").map(Date.init(timeIntervalSince1970:)),
            minimalText: minimalText, language: "source",
            knownObjectSummaries: knownObjects, sourceURL: target.string("source_url")
        )
    }

    private func knownObjectContext(
        courseID: String?, excludingObjectID: String
    ) throws -> [AIKnownObjectSummary] {
        guard let courseID else { return [] }
        return try database.query(
            """
            SELECT id, 'learning_task' AS object_type, title,
              COALESCE(normalized_type, official_type) AS item_type,
              official_due_at AS item_date
            FROM learning_tasks
            WHERE course_id=? AND id<>? AND source_state='active'
            UNION ALL
            SELECT id, 'announcement' AS object_type, title,
              'announcement' AS item_type, published_at AS item_date
            FROM announcements
            WHERE course_id=? AND id<>? AND source_state='active'
            ORDER BY object_type, id
            LIMIT ?
            """,
            bindings: [
                .text(courseID), .text(excludingObjectID),
                .text(courseID), .text(excludingObjectID),
                .integer(Int64(Self.maximumKnownObjects))
            ]
        ).compactMap { row in
            guard let objectID = row.string("id"),
                  let objectType = row.string("object_type"),
                  let title = row.string("title") else { return nil }
            return AIKnownObjectSummary(
                objectID: objectID, objectType: objectType, title: title,
                type: row.string("item_type"),
                date: row.double("item_date").map(Date.init(timeIntervalSince1970:))
            )
        }
    }

    static func minimalInput(_ value: AIParseInput) -> AIParseInput {
        func bounded(_ text: String, limit: Int) -> String {
            let patterns = [
                "(?i)bearer\\s+[A-Za-z0-9._~+/-]+",
                "(?i)(token|password|cookie|secret)\\s*[:=]\\s*[^\\s]+",
                "https?://[^\\s]+"
            ]
            var cleaned = text
            for pattern in patterns {
                cleaned = cleaned.replacingOccurrences(
                    of: pattern, with: "[REDACTED]", options: .regularExpression
                )
            }
            return String(cleaned.prefix(limit))
        }
        return AIParseInput(
            source: value.source,
            objectType: bounded(value.objectType, limit: 40),
            objectID: bounded(value.objectID, limit: 128),
            title: bounded(value.title, limit: 240),
            officialType: bounded(value.officialType, limit: 80),
            courseName: value.courseName.map { bounded($0, limit: 160) },
            officialDueAt: value.officialDueAt,
            minimalText: bounded(value.minimalText, limit: 1_200),
            language: bounded(value.language, limit: 24),
            knownObjectSummaries: value.knownObjectSummaries
                .filter { $0.objectID != value.objectID }
                .prefix(Self.maximumKnownObjects)
                .map {
                    AIKnownObjectSummary(
                        objectID: bounded($0.objectID, limit: 128),
                        objectType: bounded($0.objectType, limit: 40),
                        title: bounded($0.title, limit: 160),
                        type: $0.type.map { bounded($0, limit: 80) },
                        date: $0.date
                    )
                },
            sourceURL: nil
        )
    }

    private static func hash(_ value: AIParseInput) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
